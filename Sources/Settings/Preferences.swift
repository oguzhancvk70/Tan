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
    var shuffleQuery: String { didSet { UserDefaults.standard.set(shuffleQuery, forKey: "shuffleQuery") } }
    var includeAnime: Bool { didSet { UserDefaults.standard.set(includeAnime, forKey: "includeAnime") } }
    var hotKey: HotKey? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                UserDefaults.standard.set(data, forKey: "hotKey")
            } else {
                UserDefaults.standard.set(false, forKey: "hotKey")
            }
        }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["dimAmount": 0.3, "islandEnabled": true, "rotation": 3600, "shuffleQuery": "landscape"])
        light = Self.load("wallpaper.light")
        dark = Self.load("wallpaper.dark")
        dimDark = d.bool(forKey: "dimDark")
        dimAmount = d.double(forKey: "dimAmount")
        rotation = RotationInterval(rawValue: d.integer(forKey: "rotation")) ?? .off
        bingTarget = BingTarget(rawValue: d.string(forKey: "bingTarget") ?? "") ?? .off
        islandEnabled = d.bool(forKey: "islandEnabled")
        shuffleQuery = d.string(forKey: "shuffleQuery") ?? ""
        includeAnime = d.bool(forKey: "includeAnime")
        let raw = d.object(forKey: "hotKey")
        hotKey = raw == nil ? .default : (raw as? Data).flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) }
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
