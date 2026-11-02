import Testing
import Foundation
import CoreGraphics
@testable import MacDirStat

/// Creates a scratch directory tree and removes it afterwards
private final class TempTree {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("MacDirStatTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ relativePath: String, bytes: Int) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: fileURL)
        return fileURL
    }

    func scan(inspectPackages: Bool = false) -> FileItem {
        let root = FileItem(name: url.lastPathComponent, url: url, isDirectory: true)
        DirectoryScanner.scan(
            url: url,
            options: DirectoryScanner.ScanOptions(inspectInsidePackages: inspectPackages, showFreeSpace: true),
            rootItem: root
        )
        return root
    }
}

private func child(_ item: FileItem, _ name: String) -> FileItem? {
    return item.children.first(where: { $0.name == name })
}

@Suite("WinDirStat Port Treemap & Scanner Tests")
struct MacDirStatTests {

    @Test("Test Squarified TreeMap Layout with proportional child boxes")
    func testTreeMapSquarified() {
        let root = FileItem(
            name: "root",
            url: URL(fileURLWithPath: "/test"),
            isDirectory: true,
            size: 1000,
            children: [
                FileItem(name: "fileA.dat", url: URL(fileURLWithPath: "/test/fileA.dat"), isDirectory: false, size: 600),
                FileItem(name: "fileB.dat", url: URL(fileURLWithPath: "/test/fileB.dat"), isDirectory: false, size: 300),
                FileItem(name: "fileC.dat", url: URL(fileURLWithPath: "/test/fileC.dat"), isDirectory: false, size: 100)
            ]
        )

        let containerRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        TreeMapEngine.layout(item: root, in: containerRect)

        #expect(root.bounds == containerRect)
        #expect(root.children.count == 3)

        var totalArea: CGFloat = 0
        for child in root.children {
            #expect(child.bounds.width > 0)
            #expect(child.bounds.height > 0)
            #expect(containerRect.insetBy(dx: -0.01, dy: -0.01).contains(child.bounds))
            totalArea += child.bounds.width * child.bounds.height
        }
        #expect(abs(totalArea - containerRect.width * containerRect.height) < 1.0)

        let areaA = root.children[0].bounds.width * root.children[0].bounds.height
        let areaB = root.children[1].bounds.width * root.children[1].bounds.height
        let areaC = root.children[2].bounds.width * root.children[2].bounds.height
        #expect(areaA > areaB)
        #expect(areaB > areaC)
        #expect(abs(areaA / (containerRect.width * containerRect.height) - 0.6) < 0.01)
    }

    @Test("Folders too small to subdivide render as one tile, so stale child bounds are never used")
    func testSmallFolderIsLeaf() {
        let inner = FileItem(name: "inner.dat", url: URL(fileURLWithPath: "/t/d/inner.dat"), isDirectory: false, size: 1_000)
        let dir = FileItem(name: "d", url: URL(fileURLWithPath: "/t/d"), isDirectory: true, size: 1_000, children: [inner])
        let big = FileItem(name: "big.dat", url: URL(fileURLWithPath: "/t/big.dat"), isDirectory: false, size: 1_000)
        let root = FileItem(name: "t", url: URL(fileURLWithPath: "/t"), isDirectory: true, size: 2_000, children: [big, dir])

        TreeMapEngine.layout(item: root, in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        #expect(!TreeMapEngine.isRenderedAsLeaf(dir))
        let oldInnerBounds = inner.bounds

        // Shrink the canvas so `d` no longer gets subdivided; `inner` keeps its old, now invalid rect
        TreeMapEngine.layout(item: root, in: CGRect(x: 0, y: 0, width: 6, height: 6))
        #expect(TreeMapEngine.isRenderedAsLeaf(dir))
        #expect(inner.bounds == oldInnerBounds)
    }

    @Test("Directory Scanner correctly calculates cumulative size")
    func testDirectoryScanner() throws {
        let tree = try TempTree()
        try tree.file("sample.txt", bytes: 22)
        try tree.file("sub/a.bin", bytes: 10_000)
        try tree.file("sub/deeper/b.bin", bytes: 20_000)

        let root = tree.scan()
        #expect(root.size >= 30_022)
        #expect(root.fileCount == 3)
        #expect(root.subdirCount == 2)
        let sub = try #require(child(root, "sub"))
        #expect(sub.fileCount == 2)
        #expect(sub.subdirCount == 1)
        #expect(sub.size == sub.children.reduce(0) { $0 + $1.size })
        #expect(root.size == root.children.reduce(0) { $0 + $1.size })
        // Children are kept largest-first, as WinDirStat lists them
        #expect(root.children.map(\.size) == root.children.map(\.size).sorted(by: >))
    }

    @Test("Hidden files and folders count toward disk usage")
    func testHiddenFilesIncluded() throws {
        let tree = try TempTree()
        try tree.file(".hidden-cache/blob", bytes: 50_000)
        try tree.file(".env", bytes: 100)

        let root = tree.scan()
        #expect(child(root, ".hidden-cache") != nil)
        #expect(child(root, ".env") != nil)
        #expect(root.size >= 50_100)
    }

    @Test("A symlink never steals the size of its target")
    func testSymlinkDoesNotHideTarget() throws {
        let tree = try TempTree()
        let target = try tree.file("real.bin", bytes: 40_000)
        // "a-link" sorts before "real.bin", so a stat()-based scanner would claim the inode via the link first
        try FileManager.default.createSymbolicLink(at: tree.url.appendingPathComponent("a-link"), withDestinationURL: target)

        let root = tree.scan()
        let real = try #require(child(root, "real.bin"))
        let link = try #require(child(root, "a-link"))
        #expect(real.size >= 40_000)
        #expect(link.size < 40_000)
    }

    @Test("Hard links are counted once")
    func testHardLinksCountedOnce() throws {
        let tree = try TempTree()
        let original = try tree.file("one.bin", bytes: 64_000)
        try FileManager.default.linkItem(at: original, to: tree.url.appendingPathComponent("two.bin"))

        let root = tree.scan()
        let sizes = root.children.map(\.size).sorted()
        #expect(sizes.count == 2)
        #expect(sizes[0] == 0)
        #expect(sizes[1] >= 64_000)
    }

    @Test("Packages are sized in full and collapsed unless inspected")
    func testPackageSizing() throws {
        let tree = try TempTree()
        try tree.file("Demo.app/Contents/MacOS/Demo", bytes: 120_000)
        try tree.file("Demo.app/Contents/Info.plist", bytes: 1_000)

        let collapsed = try #require(child(tree.scan(), "Demo.app"))
        #expect(collapsed.isPackage)
        #expect(collapsed.size >= 121_000)
        #expect(collapsed.children.isEmpty)
        #expect(collapsed.isLeafLike)
        #expect(collapsed.extensionStats()["app/pkg"]?.count == 1)

        let inspected = try #require(child(tree.scan(inspectPackages: true), "Demo.app"))
        #expect(inspected.size == collapsed.size)
        #expect(!inspected.children.isEmpty)
        #expect(!inspected.isLeafLike)
    }

    @Test("<Free Space> is only added when scanning a volume root")
    func testNoFreeSpaceForPlainFolder() throws {
        let tree = try TempTree()
        try tree.file("x.bin", bytes: 1_000)
        let root = tree.scan()
        #expect(!root.children.contains(where: { $0.isSpecialNode }))
        #expect(DirectoryScanner.freeSpaceNodes(for: tree.url, scannedBytes: 0).isEmpty)

        let volumeNodes = DirectoryScanner.freeSpaceNodes(for: URL(fileURLWithPath: "/"), scannedBytes: 0)
        #expect(volumeNodes.contains(where: { $0.name == "<Free Space>" }))
    }

    @Test("Delivered subtrees are fully built before they reach the caller")
    func testDeliveredSubtreesAreComplete() throws {
        let tree = try TempTree()
        for i in 0..<20 {
            try tree.file("d\(i)/f.bin", bytes: 1_000 * (i + 1))
        }
        let root = FileItem(name: "r", url: tree.url, isDirectory: true)
        let delivered = LockedBox<[FileItem]>([])
        DirectoryScanner.scan(url: tree.url, rootItem: root) { item in
            #expect(item.parent == nil)
            #expect(item.children.count == 1)
            delivered.mutate { $0.append(item) }
        }
        #expect(delivered.value.count == 20)
        #expect(root.children.isEmpty) // with a deliver callback the scanner leaves attaching to the caller
    }

    @Test("Cancelled scans stop early")
    func testCancellation() throws {
        let tree = try TempTree()
        try tree.file("a/b.bin", bytes: 10)
        let session = ScanSession()
        session.cancel()
        let root = FileItem(name: "r", url: tree.url, isDirectory: true)
        DirectoryScanner.scan(url: tree.url, rootItem: root, session: session)
        #expect(root.children.isEmpty)
    }

    @Test("attach and detach keep ancestor totals consistent")
    func testAttachDetach() {
        let root = FileItem(name: "r", url: URL(fileURLWithPath: "/r"), isDirectory: true)
        let dir = FileItem(name: "d", url: URL(fileURLWithPath: "/r/d"), isDirectory: true)
        root.attach(dir)
        let sub = FileItem(name: "s", url: URL(fileURLWithPath: "/r/d/s"), isDirectory: true, size: 300, fileCount: 2, subdirCount: 1)
        dir.attach(sub)
        dir.attach(FileItem(name: "f", url: URL(fileURLWithPath: "/r/d/f"), isDirectory: false, size: 500))
        root.attach(FileItem(name: "<Free Space>", url: URL(fileURLWithPath: "/r/<Free Space>"), isDirectory: false, isSpecialNode: true, size: 1_000))

        #expect(root.size == 1_800)
        #expect(root.fileCount == 3)
        #expect(root.subdirCount == 3)
        #expect(dir.children.map(\.name) == ["f", "s"])

        sub.detachFromParent()
        #expect(sub.parent == nil)
        #expect(dir.size == 500)
        #expect(root.size == 1_500)
        #expect(root.fileCount == 1)
        #expect(root.subdirCount == 1)
    }

    @Test("User cleanup commands cannot be hijacked by file names")
    func testCleanupCommandInjection() throws {
        let tree = try TempTree()
        let pwned = tree.url.appendingPathComponent("pwned")
        let output = tree.url.appendingPathComponent("out.txt")
        let evilName = "x\"; touch \"\(pwned.path)\"; echo \"$(touch \(pwned.path))"

        let process = UserCleanupCommand.makeProcess(
            template: "print -rn -- \"%n\" > \"\(output.path)\"",
            path: "/tmp/\(evilName)",
            name: evilName,
            size: "1 KB"
        )
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: pwned.path))
        #expect(try String(contentsOf: output, encoding: .utf8) == evilName)
    }

    @Test("Command-line scan target skips AppKit flags and ignores non-folders")
    @MainActor
    func testCommandLineScanTarget() throws {
        let tree = try TempTree()
        #expect(AppDelegate.commandLineScanTarget(arguments: ["app"]) == nil)
        #expect(AppDelegate.commandLineScanTarget(arguments: ["app", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
        #expect(AppDelegate.commandLineScanTarget(arguments: ["app", "/definitely/not/here"]) == nil)
        let target = AppDelegate.commandLineScanTarget(arguments: ["app", "-NSDocumentRevisionsDebugMode", "YES", tree.url.path])
        #expect(target?.standardizedFileURL == tree.url.standardizedFileURL)
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}
