import Foundation

public struct InodeIdentifier: Hashable, Sendable {
    public let device: dev_t
    public let inode: ino_t
}

public final class DirectoryScanner: @unchecked Sendable {
    
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
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isPackageKey,
            .contentModificationDateKey,
            .nameKey
        ]
        
        var visitedInodes = Set<InodeIdentifier>()
        let lock = NSLock()
        
        func scanItem(at itemURL: URL, parentNode: FileItem) -> FileItem {
            let name = itemURL.lastPathComponent
            let values = try? itemURL.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let isPkg = values?.isPackage ?? false
            let modDate = values?.contentModificationDate
            
            var fileStat = stat()
            var isUniqueInode = true
            if stat(itemURL.path, &fileStat) == 0 {
                let identifier = InodeIdentifier(device: fileStat.st_dev, inode: fileStat.st_ino)
                lock.lock()
                if visitedInodes.contains(identifier) {
                    isUniqueInode = false
                } else {
                    visitedInodes.insert(identifier)
                }
                lock.unlock()
            }
            
            var size: UInt64 = 0
            if isUniqueInode && (!isDir || isPkg) {
                if let allocated = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                    size = UInt64(max(0, allocated))
                } else if let fileSize = values?.fileSize {
                    size = UInt64(max(0, fileSize))
                } else {
                    size = UInt64(max(0, fileStat.st_blocks * 512))
                }
            }
            
            let itemNode = FileItem(
                name: name,
                url: itemURL,
                isDirectory: isDir,
                isPackage: isPkg,
                size: max(1, size),
                fileCount: isDir ? 0 : 1,
                subdirCount: 0,
                modificationDate: modDate
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
            
            if isDir && (!isPkg || options.inspectInsidePackages) {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(
                    at: itemURL,
                    includingPropertiesForKeys: keys,
                    options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
                ) {
                    for case let childURL as URL in enumerator {
                        _ = scanItem(at: childURL, parentNode: itemNode)
                    }
                }
            }
            
            return itemNode
        }
        
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) {
            for case let childURL as URL in enumerator {
                _ = scanItem(at: childURL, parentNode: rootItem)
            }
        }
        
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
