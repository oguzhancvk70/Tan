import AppKit

// duvar kâğıdını tüm ekranlara uygula
@MainActor final class WallpaperManager {
    var onApplied: ((URL, Mode) -> Void)?
    private var task: Task<Void, Never>?
    private let prefs = Preferences.shared

    func apply(_ mode: Mode) {
        task?.cancel()
        task = Task {
            guard let src = resolve(mode) else { return }
            var url = src
            if mode == .dark, prefs.dimDark, src.pathExtension.lowercased() != "heic" {
                let amount = prefs.dimAmount
                url = await Task.detached(priority: .userInitiated) { ImageDimmer.dimmed(src, amount: amount) ?? src }.value
            }
            if Task.isCancelled { return }
            set(url)
            onApplied?(src, mode)
        }
    }

    private func set(_ url: URL) {
        for screen in NSScreen.screens where NSWorkspace.shared.desktopImageURL(for: screen)?.path != url.path {
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
            catch { NSLog("Tan: \(error.localizedDescription)") }
        }
    }

    // klasör modu
    func resolve(_ mode: Mode) -> URL? {
        guard let c = prefs.choice(for: mode) else { return nil }
        guard c.isFolder else { return FileManager.default.fileExists(atPath: c.path) ? c.url : nil }
        if let cur = current(mode), cur.path.hasPrefix(c.path), FileManager.default.fileExists(atPath: cur.path) { return cur }
        return advance(mode)
    }

    func preview(_ mode: Mode) -> URL? {
        guard let c = prefs.choice(for: mode) else { return nil }
        guard c.isFolder else { return c.url }
        if let cur = current(mode), cur.path.hasPrefix(c.path) { return cur }
        return LocalFolderSource.images(in: c.url).first
    }

    @discardableResult func advance(_ mode: Mode) -> URL? {
        guard let c = prefs.choice(for: mode), c.isFolder else { return nil }
        let files = LocalFolderSource.images(in: c.url)
        guard !files.isEmpty else { return nil }
        let cur = current(mode)
        let pick = files.filter { $0 != cur }.randomElement() ?? files[0]
        UserDefaults.standard.set(pick.path, forKey: "folderCurrent.\(mode.rawValue)")
        return pick
    }

    private func current(_ mode: Mode) -> URL? {
        UserDefaults.standard.string(forKey: "folderCurrent.\(mode.rawValue)").map { URL(fileURLWithPath: $0) }
    }
}
