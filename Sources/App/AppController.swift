import AppKit

// uygulama akışı: mod, duvar kâğıdı, zamanlayıcılar
@MainActor @Observable final class AppController {
    static let shared = AppController()

    @ObservationIgnored let prefs = Preferences.shared
    @ObservationIgnored let wallpaper = WallpaperManager()
    @ObservationIgnored let island = IslandController()
    @ObservationIgnored var onModeChange: (() -> Void)?
    @ObservationIgnored private var observer: AppearanceObserver?
    @ObservationIgnored private var rotationTimer: Timer?
    @ObservationIgnored private var bingTimer: Timer?

    var isDark = false
    var revision = 0
    var mode: Mode { isDark ? .dark : .light }

    func start() {
        isDark = Appearance.isDark
        island.model.isDark = isDark
        observer = AppearanceObserver(
            onAppearance: { AppController.shared.syncAppearance() },
            onEnvironment: { AppController.shared.reapply() })
        wallpaper.onApplied = { url, mode in AppController.shared.applied(url, mode) }
        HotKeyManager.shared.action = { AppController.shared.toggle() }
        HotKeyManager.shared.register(prefs.hotKey)
        island.setup()
        reapply()
        scheduleRotation()
        bingTimer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { _ in
            Task { @MainActor in await AppController.shared.checkBing() }
        }
        Task { await checkBing() }
    }

    // mod
    func syncAppearance() {
        let now = Appearance.isDark
        guard now != isDark else { return }
        isDark = now
        island.model.isDark = now
        onModeChange?()
        reapply()
        island.toast(icon: now ? "moon.fill" : "sun.max.fill", text: now ? "Karanlık Mod" : "Açık Mod",
                     tint: now ? .indigo : .yellow)
    }

    func toggle() {
        if let err = Appearance.setDark(!isDark) { report(err); return }
        syncAppearance()
    }

    // duvar kâğıdı
    func reapply() { wallpaper.apply(mode) }

    private func applied(_ url: URL, _ mode: Mode) {
        revision += 1
        guard mode == self.mode else { return }
        island.model.thumb = Thumbnail.make(url, maxPixel: 360)
        island.model.subtitle = prefs.choice(for: mode)?.caption ?? url.lastPathComponent
    }

    func choose(_ c: WallpaperChoice?, for mode: Mode) {
        prefs.set(c, for: mode)
        if c?.isFolder == true { wallpaper.advance(mode) }
        if mode == self.mode { reapply() } else { revision += 1 }
    }

    func nextInFolder() {
        wallpaper.advance(mode)
        reapply()
    }

    func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard prefs.rotation != .off else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(prefs.rotation.rawValue), repeats: true) { _ in
            Task { @MainActor in
                let c = AppController.shared
                for m in Mode.allCases { c.wallpaper.advance(m) }
                c.reapply()
            }
        }
    }

    // çevrimiçi
    func setOnline(_ w: OnlineWallpaper, for modes: [Mode]) async throws {
        let file = try await Net.download(w)
        let c = WallpaperChoice(path: file.path, title: w.title, credit: w.credit, link: w.page?.absoluteString)
        for m in modes { prefs.set(c, for: m) }
        if modes.contains(mode) { reapply() } else { revision += 1 }
    }

    func shuffle() {
        Task {
            island.toast(icon: "arrow.triangle.2.circlepath", text: "Aranıyor…", tint: .white)
            do {
                let r = try await Wallhaven.search(query: prefs.shuffleQuery, sort: .random, page: 1, anime: prefs.includeAnime)
                guard let w = r.items.first else { report("Sonuç bulunamadı. Arama terimini değiştirin."); return }
                try await setOnline(w, for: [mode])
                island.toast(icon: "sparkles", text: "Yeni duvar kâğıdı", tint: .mint)
            } catch {
                report(error.localizedDescription)
            }
        }
    }

    func checkBing() async {
        let target = prefs.bingTarget
        guard target != .off else { return }
        do {
            guard let w = try await Bing.latest(count: 1).first else { return }
            let key = "bing.last.\(target.rawValue)"
            guard UserDefaults.standard.string(forKey: key) != w.id else { return }
            try await setOnline(w, for: target.modes)
            UserDefaults.standard.set(w.id, forKey: key)
        } catch {
            NSLog("Tan Bing: \(error.localizedDescription)")
        }
    }

    func report(_ msg: String) {
        let a = NSAlert()
        a.messageText = "Tan"
        a.informativeText = msg
        NSApp.activate()
        a.runModal()
    }
}
