import AppKit

@main
enum TanMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.enableOnFirstLaunch()
        AppController.shared.start()
        statusBar = StatusBarController()
        let p = Preferences.shared
        if p.light == nil && p.dark == nil { SettingsWindow.shared.show() }
    }
}
