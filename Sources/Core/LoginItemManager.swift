import Foundation
import ServiceManagement

// oturum açılışında başlat
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var isInstalled: Bool { Bundle.main.bundlePath.hasPrefix("/Applications") }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func enableOnFirstLaunch() {
        let key = "loginItemConfigured"
        guard isInstalled, !UserDefaults.standard.bool(forKey: key) else { return }
        try? set(true)
        UserDefaults.standard.set(true, forKey: key)
    }
}
