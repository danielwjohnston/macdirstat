import Foundation

public struct InodeIdentifier: Hashable, Sendable {
    public let device: dev_t
    public let inode: ino_t
}

/// Reads a directory's entries in bulk with `getattrlistbulk`, which returns
/// name, type, device, inode, mtime and allocated size for many entries per
/// system call instead of one `stat` or `resourceValues` call per file.
enum BulkDirectoryReader {
    struct Entry {
        let name: String
        let isDirectory: Bool
        let device: dev_t
        let inode: ino_t
        let modificationDate: Date?
        /// Allocated size for regular files; 0 for directories.
        let allocatedSize: UInt64
    }

    // Values from <sys/attr.h>.
    private static let cmnName: attrgroup_t = 0x0000_0001
    private static let cmnDevID: attrgroup_t = 0x0000_0002
    private static let cmnObjType: attrgroup_t = 0x0000_0008
    private static let cmnModTime: attrgroup_t = 0x0000_0400
    private static let cmnFileID: attrgroup_t = 0x0200_0000
    private static let cmnReturnedAttrs: attrgroup_t = 0x8000_0000
    private static let fileAllocSize: attrgroup_t = 0x0000_0004
    /// `VDIR` from <sys/vnode.h>.
    private static let vdir: UInt32 = 2

    /// Returns nil if the directory can't be opened or read.
    static func entries(at path: String) -> [Entry]? {
        let fd = open(path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = 5 // ATTR_BIT_MAP_COUNT
        request.commonattr = cmnReturnedAttrs | cmnName | cmnDevID | cmnObjType | cmnModTime | cmnFileID
        request.fileattr = fileAllocSize

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var result: [Entry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count < 0 { return nil }
            if count == 0 { return result }

            var entry = buffer
            for _ in 0..<Int(count) {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if let parsed = parse(entry) {
                    result.append(parsed)
                }
                entry += length
            }
        }
    }

    /// Each entry is: length, returned attribute set, then the requested
    /// attributes in bit order (name, devid, objtype, modtime, fileid, and
    /// for files the allocated size).
    private static func parse(_ entry: UnsafeMutableRawPointer) -> Entry? {
        var cursor = entry + MemoryLayout<UInt32>.size
        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size

        // attrreference_t: offset relative to the reference itself, then length.
        let nameOffset = Int(cursor.loadUnaligned(as: Int32.self))
        let name = String(cString: (cursor + nameOffset).assumingMemoryBound(to: CChar.self))
        cursor += 8

        let device = cursor.loadUnaligned(as: dev_t.self)
        cursor += 4

        let objType = cursor.loadUnaligned(as: UInt32.self)
        cursor += 4

        // struct timespec: tv_sec then tv_nsec.
        let modSec = cursor.loadUnaligned(as: Int.self)
        let modNsec = (cursor + 8).loadUnaligned(as: Int.self)
        cursor += 16

        let inode = cursor.loadUnaligned(as: UInt64.self)
        cursor += 8

        var allocated: UInt64 = 0
        if returned.fileattr & fileAllocSize != 0 {
            allocated = UInt64(max(0, cursor.loadUnaligned(as: Int64.self)))
        }

        return Entry(
            name: name,
            isDirectory: objType == vdir,
            device: device,
            inode: inode,
            modificationDate: Date(timeIntervalSince1970: TimeInterval(modSec) + TimeInterval(modNsec) / 1_000_000_000),
            allocatedSize: allocated
        )
    }
}

public final class DirectoryScanner: @unchecked Sendable {

    /// Guards every mutation of the scanned `FileItem` tree. UI code that reads
    /// the tree while a scan is running must hold this lock too. Recursive so
    /// UI callbacks that re-enter each other (e.g. reloadData -> data source)
    /// don't deadlock.
    public static let treeLock = NSRecursiveLock()

    public struct ScanOptions: Sendable {
        public var inspectInsidePackages: Bool
        public var showFreeSpace: Bool
        public init(inspectInsidePackages: Bool = false, showFreeSpace: Bool = true) {
            self.inspectInsidePackages = inspectInsidePackages
            self.showFreeSpace = showFreeSpace
        }
    }

    public static func scan(
        url: URL,
        options: ScanOptions = ScanOptions(),
        rootItem: FileItem,
        onItemDiscovered: (@Sendable (FileItem) -> Void)? = nil
    ) {
        var visitedInodes = Set<InodeIdentifier>()
        let lock = treeLock

        func addChild(_ entry: BulkDirectoryReader.Entry, url itemURL: URL, parentNode: FileItem) -> FileItem {
            let isDir = entry.isDirectory
            let isPkg = isDir && ((try? itemURL.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false)

            let identifier = InodeIdentifier(device: entry.device, inode: entry.inode)
            lock.lock()
            let isUniqueInode = visitedInodes.insert(identifier).inserted
            lock.unlock()

            var size: UInt64 = 0
            if isUniqueInode && (!isDir || isPkg) {
                size = entry.allocatedSize
                if isDir,
                   let total = try? itemURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
                    size = UInt64(max(0, total))
                }
            }

            // Only files get the 1-byte floor so zero-byte files stay visible.
            // Directories start at 0 and accumulate their children's sizes;
            // a floor here would be counted once per directory in every ancestor.
            let itemNode = FileItem(
                name: entry.name,
                url: itemURL,
                isDirectory: isDir,
                isPackage: isPkg,
                size: isDir && !isPkg ? size : max(1, size),
                fileCount: isDir ? 0 : 1,
                subdirCount: 0,
                modificationDate: entry.modificationDate
            )
            itemNode.parent = parentNode

            lock.lock()
            parentNode.children.append(itemNode)
            if isDir {
                parentNode.subdirCount += 1
            } else {
                parentNode.fileCount += 1
            }

            var curr: FileItem? = parentNode
            while let c = curr {
                c.size += itemNode.size
                curr = c.parent
            }
            lock.unlock()

            onItemDiscovered?(itemNode)
            return itemNode
        }

        func scanDirectory(at dirURL: URL, parentNode: FileItem) {
            guard let entries = BulkDirectoryReader.entries(at: dirURL.path) else { return }
            for entry in entries where entry.name != "." && entry.name != ".." {
                let childURL = dirURL.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
                let node = addChild(entry, url: childURL, parentNode: parentNode)
                if node.isDirectory && (!node.isPackage || options.inspectInsidePackages) {
                    scanDirectory(at: childURL, parentNode: node)
                }
            }
        }

        scanDirectory(at: url, parentNode: rootItem)

        // Add WinDirStat Win32 <Free Space> and <Unknown> pseudo-nodes if scanning a volume root
        if options.showFreeSpace {
            let volumeKeys: [URLResourceKey] = [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]
            if let volValues = try? url.resourceValues(forKeys: Set(volumeKeys)),
               let total = volValues.volumeTotalCapacity, total > 0 {
                let totalBytes = UInt64(total)
                let freeBytes = UInt64(volValues.volumeAvailableCapacityForImportantUsage ?? Int64(volValues.volumeAvailableCapacity ?? 0))

                if freeBytes > 0 {
                    let freeNode = FileItem(
                        name: "<Free Space>",
                        url: url.appendingPathComponent("<Free Space>"),
                        isDirectory: false,
                        isPackage: false,
                        isSpecialNode: true,
                        size: freeBytes
                    )
                    freeNode.parent = rootItem
                    rootItem.children.append(freeNode)
                    rootItem.size += freeBytes
                }

                let accounted = rootItem.children.reduce(UInt64(0)) { $0 + $1.size }
                if totalBytes > accounted {
                    let unknownBytes = totalBytes - accounted
                    if unknownBytes > 50 * 1024 * 1024 { // If > 50MB
                        let unknownNode = FileItem(
                            name: "<Unknown>",
                            url: url.appendingPathComponent("<Unknown>"),
                            isDirectory: false,
                            isPackage: false,
                            isSpecialNode: true,
                            size: unknownBytes
                        )
                        unknownNode.parent = rootItem
                        rootItem.children.append(unknownNode)
                        rootItem.size += unknownBytes
                    }
                }
            }
        }
    }
}

/// Thread-safe discovery counter. Incremented from the scan queue without
/// hopping to the main queue for every file.
public final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    public init() {}

    public func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    public var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
