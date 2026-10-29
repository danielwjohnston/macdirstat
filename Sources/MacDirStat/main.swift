import Cocoa

@MainActor
func runApplication() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

runApplication()
