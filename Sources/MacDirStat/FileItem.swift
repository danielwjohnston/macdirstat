import Cocoa

public struct ExtensionStat: Sendable, Equatable {
    public var bytes: UInt64 = 0
    public var count: Int = 0
}

public final class FileItem: @unchecked Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isSpecialNode: Bool // True for <Free Space> and <Unknown>
    public var size: UInt64
    public var fileCount: Int = 0   // Files in the whole subtree (WinDirStat semantics)
    public var subdirCount: Int = 0 // Subdirectories in the whole subtree
    public var modificationDate: Date?
    public var children: [FileItem]
    public weak var parent: FileItem?

    // Treemap computed layout rect
    public var bounds: CGRect = .zero

    public var extensionName: String {
        if isSpecialNode { return name }
        if isDirectory && !isPackage { return "<dir>" }
        if isPackage { return "app/pkg" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "<none>" : ext
    }

    /// True for nodes the treemap and extension list treat as a single file
    /// (collapsed packages have no children; inspected ones are walked like folders)
    public var isLeafLike: Bool {
        return !isDirectory || isSpecialNode || (isPackage && children.isEmpty)
    }

    public init(
        name: String,
        url: URL,
        isDirectory: Bool,
        isPackage: Bool = false,
        isSpecialNode: Bool = false,
        size: UInt64 = 0,
        fileCount: Int = 0,
        subdirCount: Int = 0,
        modificationDate: Date? = nil,
        children: [FileItem] = []
    ) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSpecialNode = isSpecialNode
        self.size = size
        self.fileCount = fileCount
        self.subdirCount = subdirCount
        self.modificationDate = modificationDate
        self.children = children
        for child in children {
            child.parent = self
        }
    }

    /// Files and directories this node contributes to its ancestors' counts
    private var countContribution: (files: Int, dirs: Int) {
        if isSpecialNode { return (0, 0) }
        if isDirectory { return (fileCount, subdirCount + 1) }
        return (1, 0)
    }

    /// Inserts a fully built subtree, keeping children sorted by size and rolling totals up to the root.
    public func attach(_ child: FileItem) {
        child.parent = self
        let index = children.firstIndex(where: { $0.size < child.size }) ?? children.count
        children.insert(child, at: index)
        let delta = child.countContribution
        var node: FileItem? = self
        while let n = node {
            n.size += child.size
            n.fileCount += delta.files
            n.subdirCount += delta.dirs
            node = n.parent
        }
    }

    /// Removes this subtree from its parent, subtracting its totals from every ancestor.
    public func detachFromParent() {
        guard let p = parent else { return }
        p.children.removeAll(where: { $0 === self })
        let delta = countContribution
        var node: FileItem? = p
        while let n = node {
            n.size -= min(n.size, size)
            n.fileCount = max(0, n.fileCount - delta.files)
            n.subdirCount = max(0, n.subdirCount - delta.dirs)
            node = n.parent
        }
        parent = nil
    }

    public var depth: Int {
        var d = 0
        var p = parent
        while let node = p {
            d += 1
            p = node.parent
        }
        return d
    }

    /// Per-extension byte and file totals for this subtree
    public func extensionStats() -> [String: ExtensionStat] {
        var stats: [String: ExtensionStat] = [:]
        func collect(_ item: FileItem) {
            if item.isLeafLike {
                stats[item.extensionName, default: ExtensionStat()].bytes += item.size
                stats[item.extensionName, default: ExtensionStat()].count += 1
            } else {
                for child in item.children {
                    collect(child)
                }
            }
        }
        collect(self)
        return stats
    }

    public func formattedSize() -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)
    }

    public func subtreePercentage() -> Double {
        guard let p = parent, p.size > 0 else { return 1.0 }
        return Double(size) / Double(p.size)
    }
}
