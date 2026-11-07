import AppKit

// çeviri kısayolu (anahtarlar Türkçe kaynak metin)
func L(_ k: String.LocalizationValue) -> String { String(localized: k) }

// yerel yüzde biçimi (tr: %80, en: 80%)
func pct(_ v: Int) -> String { v.formatted(.percent) }

// uygulama dili
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, tr, en
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: L("Sistem")
        case .tr: "Türkçe"
        case .en: "English"
        }
    }

    static var current: AppLanguage {
        guard let l = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let f = l.first else { return .system }
        return f.hasPrefix("en") ? .en : f.hasPrefix("tr") ? .tr : .system
    }

    static var isEnglish: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true }

    func apply() {
        if self == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([rawValue], forKey: "AppleLanguages") }
    }

    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.8; open \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}
