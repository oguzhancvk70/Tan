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
        m.addItem(modeSwitchItem())
        m.addItem(.separator())
        m.addItem(item("Rastgele Duvar Kâğıdı", #selector(shuffle)))
        if Preferences.shared.choice(for: app.mode)?.isFolder == true {
            m.addItem(item("Klasörde Sonraki", #selector(next)))
        }
        m.addItem(item("Galeri…", #selector(gallery)))
        m.addItem(.separator())
        let claude = item("Claude ile Sohbet" + (Preferences.shared.claudeHotKey.map { "  \($0.display)" } ?? ""), #selector(claudeChat))
        claude.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
        m.addItem(claude)
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

    // menüde açık/koyu anahtarı
    private weak var modeIcon: NSImageView?

    private func modeSwitchItem() -> NSMenuItem {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 32))
        let icon = NSImageView(frame: NSRect(x: 14, y: 8, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: app.isDark ? "moon.fill" : "sun.max.fill", accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: "Karanlık Mod")
        label.font = .menuFont(ofSize: 0)
        label.frame = NSRect(x: 38, y: 7, width: 120, height: 18)
        let sw = NSSwitch(frame: NSRect(x: 172, y: 5, width: 44, height: 22))
        sw.state = app.isDark ? .on : .off
        sw.target = self
        sw.action = #selector(switchChanged(_:))
        [icon, label, sw].forEach(v.addSubview)
        modeIcon = icon
        let item = NSMenuItem()
        item.view = v
        return item
    }

    @objc private func switchChanged(_ s: NSSwitch) {
        if (s.state == .on) != app.isDark { app.toggle() }
        s.state = app.isDark ? .on : .off
        modeIcon?.image = NSImage(systemSymbolName: app.isDark ? "moon.fill" : "sun.max.fill", accessibilityDescription: nil)
    }
    @objc private func shuffle() { app.shuffle() }
    @objc private func next() { app.nextInFolder() }
    @objc private func claudeChat() { ClaudePanelController.shared.show() }
    @objc private func gallery() { SettingsWindow.shared.show(tab: .gallery) }
    @objc private func settings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
