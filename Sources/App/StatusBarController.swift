import AppKit

// menü çubuğu simgesi
@MainActor final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let app = AppController.shared

    override init() {
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
        app.onModeChange = { [weak self] in self?.updateIcon() }
    }

    private func updateIcon() {
        let img = NSImage(systemSymbolName: app.isDark ? "moon.fill" : "sun.max.fill", accessibilityDescription: "Tan")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    @objc private func clicked() {
        if let e = NSApp.currentEvent, e.type == .leftMouseUp, e.modifierFlags.contains(.option) {
            app.toggle()
            return
        }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item(app.isDark ? "Açık Moda Geç" : "Karanlık Moda Geç", #selector(toggle)))
        m.addItem(.separator())
        m.addItem(item("Rastgele Duvar Kâğıdı", #selector(shuffle)))
        if Preferences.shared.choice(for: app.mode)?.isFolder == true {
            m.addItem(item("Klasörde Sonraki", #selector(next)))
        }
        m.addItem(item("Galeri…", #selector(gallery)))
        m.addItem(.separator())
        m.addItem(item("Ayarlar…", #selector(settings), key: ","))
        m.addItem(item("Çıkış", #selector(quit), key: "q"))
        return m
    }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggle() { app.toggle() }
    @objc private func shuffle() { app.shuffle() }
    @objc private func next() { app.nextInFolder() }
    @objc private func gallery() { SettingsWindow.shared.show(tab: .gallery) }
    @objc private func settings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
