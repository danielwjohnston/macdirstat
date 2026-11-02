import Foundation
import os

public struct InodeIdentifier: Hashable, Sendable {
    public let device: dev_t
    public let inode: ino_t
}

/// Thread-safe handle for one scan: cancellation flag plus a live item counter the UI can poll.
public final class ScanSession: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (cancelled: false, items: 0))

    public init() {}

    public var isCancelled: Bool { state.withLock { $0.cancelled } }
    public var itemCount: Int { state.withLock { $0.items } }

    public func cancel() {
        state.withLock { $0.cancelled = true }
    }

    func addItems(_ count: Int) {
        state.withLock { $0.items += count }
    }
}

public final class DirectoryScanner: Sendable {

    public struct ScanOptions: Sendable {
        public var inspectInsidePackages: Bool
        public var showFreeSpace: Bool
        public init(inspectInsidePackages: Bool = false, showFreeSpace: Bool = true) {
            self.inspectInsidePackages = inspectInsidePackages
            self.showFreeSpace = showFreeSpace
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isPackageKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey
    ]

    /// Directory levels below the scan root whose children are scanned in parallel
    private static let parallelDepth = 2

    private let options: ScanOptions
    private let session: ScanSession
    private let rootDevice: dev_t
    private let visitedInodes = OSAllocatedUnfairLock(initialState: Set<InodeIdentifier>())

    private init(options: ScanOptions, session: ScanSession, rootDevice: dev_t) {
        self.options = options
        self.session = session
        self.rootDevice = rootDevice
    }

    /// Scans `url` and adds its contents to `rootItem`.
    ///
    /// Each top-level child is built as a detached subtree on a worker thread. When `deliver` is
    /// nil the subtree is attached to `rootItem` directly (only safe if nothing else is reading the
    /// tree); otherwise it is handed to `deliver`, which must attach it, e.g. on the main thread.
    /// Children are never mutated after delivery, so the UI never sees a half-built array.
    public static func scan(
        url: URL,
        options: ScanOptions = ScanOptions(),
        rootItem: FileItem,
        session: ScanSession = ScanSession(),
        deliver: (@Sendable (FileItem) -> Void)? = nil
    ) {
        var rootStat = stat()
        guard lstatURL(url, &rootStat) == 0 else { return }

        let scanner = DirectoryScanner(options: options, session: session, rootDevice: rootStat.st_dev)
        _ = scanner.claimInode(rootStat)

        let attachLock = NSLock()
        let scannedBytes = OSAllocatedUnfairLock(initialState: UInt64(0))
        let emit: @Sendable (FileItem) -> Void = { item in
            scannedBytes.withLock { $0 += item.size }
            if let deliver {
                deliver(item)
            } else {
                attachLock.withLock { rootItem.attach(item) }
            }
        }

        let rootDevice = rootStat.st_dev
        let childURLs = scanner.contents(of: url)
        session.addItems(childURLs.count)
        DispatchQueue.concurrentPerform(iterations: childURLs.count) { index in
            if let item = scanner.buildItem(at: childURLs[index], parentDevice: rootDevice, depth: 1) {
                emit(item)
            }
        }

        guard options.showFreeSpace, !session.isCancelled else { return }
        for node in freeSpaceNodes(for: url, scannedBytes: scannedBytes.withLock { $0 }) {
            emit(node)
        }
    }

    /// WinDirStat-style <Free Space> and <Unknown> pseudo-nodes, only when `url` is a volume root
    static func freeSpaceNodes(for url: URL, scannedBytes: UInt64) -> [FileItem] {
        let volumeKeys: Set<URLResourceKey> = [
            .isVolumeKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: volumeKeys),
              values.isVolume == true,
              let total = values.volumeTotalCapacity, total > 0 else {
            return []
        }
        let totalBytes = UInt64(total)
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let freeBytes = UInt64(max(0, important > 0 ? important : Int64(values.volumeAvailableCapacity ?? 0)))

        var nodes: [FileItem] = []
        if freeBytes > 0 {
            nodes.append(FileItem(
                name: "<Free Space>",
                url: url.appendingPathComponent("<Free Space>"),
                isDirectory: false,
                isSpecialNode: true,
                size: freeBytes
            ))
        }
        let accounted = scannedBytes + freeBytes
        if totalBytes > accounted, totalBytes - accounted > 50 * 1024 * 1024 {
            nodes.append(FileItem(
                name: "<Unknown>",
                url: url.appendingPathComponent("<Unknown>"),
                isDirectory: false,
                isSpecialNode: true,
                size: totalBytes - accounted
            ))
        }
        return nodes
    }

    // MARK: - Tree building

    private static func lstatURL(_ url: URL, _ buffer: inout stat) -> Int32 {
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return lstat(path, &buffer)
        }
    }

    private func contents(of url: URL) -> [URL] {
        // Hidden files are included: dotfiles and dot-folders (.git, caches, node toolchains) are real disk usage
        return (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: DirectoryScanner.resourceKeys,
            options: []
        )) ?? []
    }

    /// Returns false when this inode was already counted (hard link, or a firmlinked directory seen twice)
    private func claimInode(_ st: stat) -> Bool {
        let identifier = InodeIdentifier(device: st.st_dev, inode: st.st_ino)
        return visitedInodes.withLock { $0.insert(identifier).inserted }
    }

    /// Whether to cross into a different mounted filesystem found inside the scan
    private func shouldDescend(intoMountAt url: URL) -> Bool {
        var fs = statfs()
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return statfs(path, &fs) == 0
        }
        guard ok else { return false }
        let fsType = withUnsafeBytes(of: fs.f_fstypename) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        let mountPoint = withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        if fs.f_flags & UInt32(MNT_LOCAL) == 0 { return false }        // network shares
        if ["devfs", "autofs", "nullfs"].contains(fsType) { return false }
        if mountPoint.hasPrefix("/Volumes/") { return false }          // other drives are scanned on their own
        return true
    }

    private func buildItem(at url: URL, parentDevice: dev_t, depth: Int) -> FileItem? {
        guard !session.isCancelled else { return nil }

        var st = stat()
        guard DirectoryScanner.lstatURL(url, &st) == 0 else { return nil }

        let mode = st.st_mode & S_IFMT
        let isDir = mode == S_IFDIR
        let values = try? url.resourceValues(forKeys: Set(DirectoryScanner.resourceKeys))
        let modDate = values?.contentModificationDate

        if !isDir {
            // Symlinks are sized as the link itself (lstat), so their targets are never double counted
            var size: UInt64 = 0
            if st.st_nlink <= 1 || claimInode(st) {
                if mode == S_IFREG, let allocated = values?.totalFileAllocatedSize {
                    size = UInt64(max(0, allocated))
                } else {
                    size = UInt64(max(0, st.st_blocks)) * 512
                }
            }
            return FileItem(
                name: url.lastPathComponent,
                url: url,
                isDirectory: false,
                size: size,
                modificationDate: modDate
            )
        }

        // Directories reachable twice (e.g. firmlinks between / and /System/Volumes/Data) are listed once
        guard claimInode(st) else { return nil }
        if st.st_dev != parentDevice && !shouldDescend(intoMountAt: url) {
            return nil
        }

        let isPkg = values?.isPackage ?? false
        let item = FileItem(
            name: url.lastPathComponent,
            url: url,
            isDirectory: true,
            isPackage: isPkg,
            size: UInt64(max(0, st.st_blocks)) * 512,
            modificationDate: modDate
        )

        let childURLs = contents(of: url)
        session.addItems(childURLs.count)

        let device = st.st_dev
        var children: [FileItem]
        if depth <= DirectoryScanner.parallelDepth && childURLs.count > 1 {
            let results = OSAllocatedUnfairLock(initialState: [FileItem]())
            DispatchQueue.concurrentPerform(iterations: childURLs.count) { index in
                if let child = buildItem(at: childURLs[index], parentDevice: device, depth: depth + 1) {
                    results.withLock { $0.append(child) }
                }
            }
            children = results.withLock { $0 }
        } else {
            children = childURLs.compactMap { buildItem(at: $0, parentDevice: device, depth: depth + 1) }
        }

        for child in children {
            item.size += child.size
            if child.isDirectory {
                item.fileCount += child.fileCount
                item.subdirCount += child.subdirCount + 1
            } else {
                item.fileCount += 1
            }
        }

        // Packages are sized in full but shown as one opaque item unless the user asks to look inside
        if !isPkg || options.inspectInsidePackages {
            children.sort { $0.size > $1.size }
            for child in children {
                child.parent = item
            }
            item.children = children
        }
        return item
    }
}
