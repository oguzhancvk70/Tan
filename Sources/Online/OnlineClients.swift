import Foundation

struct OnlineWallpaper: Identifiable, Hashable {
    enum Source: String { case wallhaven, bing }
    let id: String
    let source: Source
    let thumb: URL
    let full: URL
    let title: String
    let credit: String
    let page: URL?

    var fileName: String {
        let ext = full.pathExtension.isEmpty ? "jpg" : full.pathExtension
        return "\(source.rawValue)-\(id).\(ext)"
    }
}

enum OnlineError: LocalizedError {
    case rateLimited, status(Int)
    var errorDescription: String? {
        switch self {
        case .rateLimited: "Çok fazla istek gönderildi. Bir dakika sonra tekrar deneyin."
        case .status(let c): "Sunucu hatası (\(c))."
        }
    }
}

// ağ
enum Net {
    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Tan/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 { throw OnlineError.rateLimited }
        guard (200..<300).contains(code) else { throw OnlineError.status(code) }
        return data
    }

    static func download(_ w: OnlineWallpaper) async throws -> URL {
        let dest = Storage.downloads.appendingPathComponent(w.fileName)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        try await get(w.full).write(to: dest, options: .atomic)
        return dest
    }
}

// Wallhaven (anahtarsız, yalnızca SFW)
enum WallhavenSort: String, CaseIterable, Identifiable {
    case toplist, favorites, date_added, random
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toplist: "Popüler"
        case .favorites: "En çok beğenilen"
        case .date_added: "En yeni"
        case .random: "Rastgele"
        }
    }
}

enum Wallhaven {
    private struct Response: Decodable { let data: [Item]; let meta: Meta }
    private struct Meta: Decodable { let last_page: Int }
    private struct Item: Decodable { let id: String; let url: String; let path: String; let resolution: String; let thumbs: Thumbs }
    private struct Thumbs: Decodable { let large: String }

    static func search(query: String, sort: WallhavenSort, page: Int, anime: Bool) async throws -> (items: [OnlineWallpaper], lastPage: Int) {
        var c = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var q = [
            URLQueryItem(name: "categories", value: anime ? "110" : "100"),
            URLQueryItem(name: "purity", value: "100"),
            URLQueryItem(name: "sorting", value: sort.rawValue),
            URLQueryItem(name: "atleast", value: "2560x1440"),
            URLQueryItem(name: "ratios", value: "16x9,16x10"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { q.append(URLQueryItem(name: "q", value: trimmed)) }
        if sort == .toplist { q.append(URLQueryItem(name: "topRange", value: "1y")) }
        c.queryItems = q

        let r = try JSONDecoder().decode(Response.self, from: try await Net.get(c.url!))
        let items = r.data.compactMap { i -> OnlineWallpaper? in
            guard let t = URL(string: i.thumbs.large), let f = URL(string: i.path) else { return nil }
            return OnlineWallpaper(id: i.id, source: .wallhaven, thumb: t, full: f, title: i.resolution,
                                   credit: "Wallhaven", page: URL(string: i.url))
        }
        return (items, r.meta.last_page)
    }
}

// Bing günün görseli
enum Bing {
    private struct Response: Decodable { let images: [Img] }
    private struct Img: Decodable { let startdate: String; let urlbase: String; let copyright: String; let copyrightlink: String?; let title: String? }

    static func latest(count: Int = 8) async throws -> [OnlineWallpaper] {
        let url = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=\(count)&mkt=tr-TR")!
        let r = try JSONDecoder().decode(Response.self, from: try await Net.get(url))
        return r.images.compactMap { i in
            let base = "https://www.bing.com" + i.urlbase
            guard let thumb = URL(string: base + "_800x480.jpg"), let full = URL(string: base + "_UHD.jpg") else { return nil }
            let raw = i.urlbase.components(separatedBy: "id=").last ?? i.startdate
            let id = raw.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "", options: .regularExpression)
            let page = i.copyrightlink.flatMap(URL.init(string:)).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }
            return OnlineWallpaper(id: id, source: .bing, thumb: thumb, full: full, title: i.title ?? i.copyright,
                                   credit: i.copyright, page: page)
        }
    }
}
