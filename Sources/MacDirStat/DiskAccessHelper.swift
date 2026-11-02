import Cocoa

@MainActor
public struct DiskAccessHelper {
    private static let suppressKey = "MacDirStat.SuppressFullDiskAccessPrompt"
    
    public static var hasFullDiskAccess: Bool {
        // Test reading a protected directory like ~/Library/Application Support/com.apple.TCC
        let testPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC")
        return (try? FileManager.default.contentsOfDirectory(atPath: testPath.path)) != nil
    }
    
    /// Shows the prompt as a sheet so it never blocks a scan that is starting in the same window
    public static func checkAndPromptFullDiskAccess(in window: NSWindow?) {
        guard !hasFullDiskAccess, !UserDefaults.standard.bool(forKey: suppressKey) else { return }
        
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Recommended"
        alert.informativeText = "To accurately scan your entire disk without skipping protected directories (like ~/Library, caches, and backups), please grant Full Disk Access to MacDirStat in System Settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: suppressKey)
            }
            if response == .alertFirstButtonReturn {
                openFullDiskAccessSettings()
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
    
    public static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
