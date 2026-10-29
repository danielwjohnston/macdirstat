import Cocoa

@MainActor
public struct DiskAccessHelper {
    public static func checkAndPromptFullDiskAccess() {
        // Test reading a protected directory like ~/Library/Application Support/com.apple.TCC
        let testPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC")
        
        let hasAccess = (try? FileManager.default.contentsOfDirectory(atPath: testPath.path)) != nil
        
        if !hasAccess {
            let alert = NSAlert()
            alert.messageText = "Full Disk Access Recommended"
            alert.informativeText = "To accurately scan your entire disk without skipping protected directories (like ~/Library, caches, and backups), please grant Full Disk Access to MacDirStat in System Settings."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            if alert.runModal() == .alertFirstButtonReturn {
                openFullDiskAccessSettings()
            }
        }
    }
    
    public static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
