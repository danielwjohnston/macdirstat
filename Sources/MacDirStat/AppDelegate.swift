import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        
        // Menu Bar Setup
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit MacDirStat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        app.mainMenu = mainMenu
        
        windowController = MainWindowController()
        windowController?.showWindow(nil)
        windowController?.window?.center()
        windowController?.window?.makeKeyAndOrderFront(nil)
        
        // Check & prompt for Full Disk Access
        DiskAccessHelper.checkAndPromptFullDiskAccess()
        
        // Default scan current project directory or argument
        let defaultPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        let defaultURL = URL(fileURLWithPath: defaultPath)
        windowController?.startScan(at: defaultURL)
        
        app.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
