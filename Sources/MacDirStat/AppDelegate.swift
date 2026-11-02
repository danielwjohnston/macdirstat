import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        windowController = MainWindowController()
        app.mainMenu = buildMainMenu()
        windowController?.showWindow(nil)
        windowController?.window?.center()
        windowController?.window?.makeKeyAndOrderFront(nil)

        // Scan a folder passed on the command line; otherwise ask, like WinDirStat. (A Finder-launched
        // app's working directory is "/", so defaulting to it would silently start a full-disk scan.)
        if let target = AppDelegate.commandLineScanTarget() {
            windowController?.startScan(at: target)
        } else {
            windowController?.showSelectDrives()
        }

        // Check & prompt for Full Disk Access (as a sheet, so the scan above keeps running)
        DiskAccessHelper.checkAndPromptFullDiskAccess(in: windowController?.window)

        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// First argument that names an existing directory (skips AppKit flags such as -NSDocumentRevisionsDebugMode)
    static func commandLineScanTarget(arguments: [String] = CommandLine.arguments) -> URL? {
        var args = arguments.dropFirst()
        while let arg = args.first {
            args = args.dropFirst()
            if arg.hasPrefix("-") {
                if let next = args.first, !next.hasPrefix("-") { args = args.dropFirst() }
                continue
            }
            let path = (arg as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MacDirStat", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(MainWindowController.showPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MacDirStat", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit MacDirStat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, titled: "MacDirStat", to: mainMenu)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Select Drives…", action: #selector(MainWindowController.showSelectDrives), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Rescan", action: #selector(MainWindowController.rescan), keyEquivalent: "r")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export to CSV…", action: #selector(MainWindowController.exportReport), keyEquivalent: "e")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(fileMenu, titled: "File", to: mainMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, titled: "Edit", to: mainMenu)

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Quick Look", action: #selector(MainWindowController.toggleQuickLook), keyEquivalent: "y")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(MainWindowController.zoomOutAction), keyEquivalent: "\u{1b}")
        addSubmenu(viewMenu, titled: "View", to: mainMenu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        addSubmenu(windowMenu, titled: "Window", to: mainMenu)
        NSApplication.shared.windowsMenu = windowMenu

        return mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, titled title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
