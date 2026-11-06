import AppKit

// karanlık mod oku / değiştir
enum Appearance {
    @MainActor static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    @MainActor static func setDark(_ dark: Bool) -> String? {
        let src = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        guard let err else { return nil }
        let code = err[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 {
            return "System Events'e erişim izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Otomasyon bölümünden Tan için System Events'i açın."
        }
        return err[NSAppleScript.errorMessage] as? String ?? "AppleScript hatası (\(code))"
    }
}
