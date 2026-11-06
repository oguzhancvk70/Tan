import Foundation

enum Mode: String, CaseIterable { case light, dark }

enum RotationInterval: Int, CaseIterable, Identifiable {
    case off = 0, m15 = 900, h1 = 3600, h6 = 21600, d1 = 86400
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: "Kapalı"
        case .m15: "15 dakika"
        case .h1: "1 saat"
        case .h6: "6 saat"
        case .d1: "Günde bir"
        }
    }
}

enum BingTarget: String, CaseIterable, Identifiable {
    case off, light, dark, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Kapalı"
        case .light: "Açık mod"
        case .dark: "Koyu mod"
        case .both: "İkisi"
        }
    }
    var modes: [Mode] {
        switch self {
        case .off: []
        case .light: [.light]
        case .dark: [.dark]
        case .both: [.light, .dark]
        }
    }
}

struct WallpaperChoice: Codable, Equatable {
    var path: String
    var isFolder = false
    var title: String?
    var credit: String?
    var link: String?
    var url: URL { URL(fileURLWithPath: path) }
    var caption: String { title ?? url.lastPathComponent }
}

// ayarlar (UserDefaults)
@MainActor @Observable final class Preferences {
    static let shared = Preferences()

    var light: WallpaperChoice? { didSet { Self.save(light, "wallpaper.light") } }
    var dark: WallpaperChoice? { didSet { Self.save(dark, "wallpaper.dark") } }
    var dimDark: Bool { didSet { UserDefaults.standard.set(dimDark, forKey: "dimDark") } }
    var dimAmount: Double { didSet { UserDefaults.standard.set(dimAmount, forKey: "dimAmount") } }
    var rotation: RotationInterval { didSet { UserDefaults.standard.set(rotation.rawValue, forKey: "rotation") } }
    var bingTarget: BingTarget { didSet { UserDefaults.standard.set(bingTarget.rawValue, forKey: "bingTarget") } }
    var islandEnabled: Bool { didSet { UserDefaults.standard.set(islandEnabled, forKey: "islandEnabled") } }
    var islandMusic: Bool { didSet { UserDefaults.standard.set(islandMusic, forKey: "islandMusic") } }
    var islandBattery: Bool { didSet { UserDefaults.standard.set(islandBattery, forKey: "islandBattery") } }
    var islandCalendar: Bool { didSet { UserDefaults.standard.set(islandCalendar, forKey: "islandCalendar") } }
    var islandPrivacy: Bool { didSet { UserDefaults.standard.set(islandPrivacy, forKey: "islandPrivacy") } }
    var islandAudio: Bool { didSet { UserDefaults.standard.set(islandAudio, forKey: "islandAudio") } }
    var shuffleQuery: String { didSet { UserDefaults.standard.set(shuffleQuery, forKey: "shuffleQuery") } }
    var includeAnime: Bool { didSet { UserDefaults.standard.set(includeAnime, forKey: "includeAnime") } }
    var islandClipboard: Bool { didSet { UserDefaults.standard.set(islandClipboard, forKey: "islandClipboard") } }
    var islandScreenshots: Bool { didSet { UserDefaults.standard.set(islandScreenshots, forKey: "islandScreenshots") } }
    var islandDownloads: Bool { didSet { UserDefaults.standard.set(islandDownloads, forKey: "islandDownloads") } }
    var claudeFolder: String { didSet { UserDefaults.standard.set(claudeFolder, forKey: "claudeFolder") } }
    var claudeEdits: Bool { didSet { UserDefaults.standard.set(claudeEdits, forKey: "claudeEdits") } }
    var hotKey: HotKey? { didSet { Self.saveHotKey(hotKey, "hotKey") } }
    var claudeHotKey: HotKey? { didSet { Self.saveHotKey(claudeHotKey, "claudeHotKey") } }

    private static func saveHotKey(_ hk: HotKey?, _ key: String) {
        if let hk, let data = try? JSONEncoder().encode(hk) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.set(false, forKey: key)
        }
    }

    private static func loadHotKey(_ key: String, _ def: HotKey) -> HotKey? {
        let raw = UserDefaults.standard.object(forKey: key)
        return raw == nil ? def : (raw as? Data).flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["dimAmount": 0.3, "islandEnabled": true, "rotation": 3600, "shuffleQuery": "landscape",
                              "islandMusic": true, "islandBattery": true, "islandCalendar": true, "islandPrivacy": true, "islandAudio": true])
        islandMusic = d.bool(forKey: "islandMusic")
        islandBattery = d.bool(forKey: "islandBattery")
        islandCalendar = d.bool(forKey: "islandCalendar")
        islandPrivacy = d.bool(forKey: "islandPrivacy")
        islandAudio = d.bool(forKey: "islandAudio")
        light = Self.load("wallpaper.light")
        dark = Self.load("wallpaper.dark")
        dimDark = d.bool(forKey: "dimDark")
        dimAmount = d.double(forKey: "dimAmount")
        rotation = RotationInterval(rawValue: d.integer(forKey: "rotation")) ?? .off
        bingTarget = BingTarget(rawValue: d.string(forKey: "bingTarget") ?? "") ?? .off
        islandEnabled = d.bool(forKey: "islandEnabled")
        shuffleQuery = d.string(forKey: "shuffleQuery") ?? ""
        includeAnime = d.bool(forKey: "includeAnime")
        d.register(defaults: ["islandClipboard": true, "islandScreenshots": true, "islandDownloads": true])
        islandClipboard = d.bool(forKey: "islandClipboard")
        islandScreenshots = d.bool(forKey: "islandScreenshots")
        islandDownloads = d.bool(forKey: "islandDownloads")
        claudeFolder = d.string(forKey: "claudeFolder") ?? NSHomeDirectory()
        claudeEdits = d.bool(forKey: "claudeEdits")
        hotKey = Self.loadHotKey("hotKey", .default)
        claudeHotKey = Self.loadHotKey("claudeHotKey", .claudeDefault)
    }

    func choice(for mode: Mode) -> WallpaperChoice? { mode == .light ? light : dark }

    func set(_ c: WallpaperChoice?, for mode: Mode) {
        if mode == .light { light = c } else { dark = c }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// dosya yolları
enum Storage {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Tan")
    static var downloads: URL { dir("Wallpapers") }
    static var dimmed: URL { dir("Dimmed") }

    private static func dir(_ name: String) -> URL {
        let u = root.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
