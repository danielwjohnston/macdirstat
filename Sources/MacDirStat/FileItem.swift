import Cocoa

public final class FileItem: @unchecked Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isSpecialNode: Bool // True for <Free Space> and <Unknown>
    public var size: UInt64
    public var fileCount: Int = 0
    public var subdirCount: Int = 0
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
    
    public func formattedSize() -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    public func subtreePercentage() -> Double {
        guard let p = parent, p.size > 0 else { return 1.0 }
        return Double(size) / Double(p.size)
    }
}
