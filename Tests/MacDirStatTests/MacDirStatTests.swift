import Testing
import Foundation
import CoreGraphics
@testable import MacDirStat

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
        
        for child in root.children {
            #expect(child.bounds.width > 0)
            #expect(child.bounds.height > 0)
            #expect(containerRect.contains(child.bounds) || containerRect.intersects(child.bounds))
        }
        
        let fileA = root.children[0]
        let fileB = root.children[1]
        let fileC = root.children[2]
        
        let areaA = fileA.bounds.width * fileA.bounds.height
        let areaB = fileB.bounds.width * fileB.bounds.height
        let areaC = fileC.bounds.width * fileC.bounds.height
        
        #expect(areaA > areaB)
        #expect(areaB > areaC)
    }
    
    @Test("Directory Scanner correctly calculates cumulative size")
    func testDirectoryScanner() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let testFile = tempDir.appendingPathComponent("sample.txt")
        let data = "Hello WinDirStat Port!".data(using: .utf8)!
        try? data.write(to: testFile)
        
        let root = FileItem(name: tempDir.lastPathComponent, url: tempDir, isDirectory: true)
        DirectoryScanner.scan(url: tempDir, rootItem: root)
        #expect(root.isDirectory == true)
        #expect(root.size >= UInt64(data.count))
        #expect(root.children.contains(where: { $0.name == "sample.txt" }))
        
        try? FileManager.default.removeItem(at: tempDir)
    }
}
