import AppKit

// uygulama akışı: mod, duvar kâğıdı, zamanlayıcılar
@MainActor @Observable final class AppController {
    static let shared = AppController()

    @ObservationIgnored let prefs = Preferences.shared
    @ObservationIgnored let wallpaper = WallpaperManager()
    @ObservationIgnored let island = IslandController()
    @ObservationIgnored let nowPlaying = NowPlayingService()
    @ObservationIgnored let battery = BatteryService()
    @ObservationIgnored let calendar = CalendarService()
    @ObservationIgnored let privacy = PrivacyService()
    @ObservationIgnored let audio = AudioDeviceService()
    @ObservationIgnored let timer = TimerService()
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
        startActivities()
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
        island.show(IslandToast(icon: now ? "moon.fill" : "sun.max.fill", tint: now ? .indigo : .yellow,
                                title: now ? "Karanlık Mod" : "Açık Mod"))
    }

    // ada etkinlikleri
    private func startActivities() {
        nowPlaying.onChange = { np, changed in
            let c = AppController.shared, m = c.island.model
            m.nowPlaying = np
            guard let np, c.prefs.islandMusic else { return }
            if changed, np.isPlaying {
                c.island.show(IslandToast(icon: "music.note", tint: .green, title: np.title,
                                          subtitle: np.artist.isEmpty ? (np.appName ?? "") : np.artist, image: np.artwork))
            } else if m.phase == .toast, m.toast.title == np.title, m.toast.image == nil, let art = np.artwork {
                m.toast.image = art
            }
        }
        nowPlaying.start()

        battery.onChange = { new, old in AppController.shared.batteryChanged(new, old) }
        battery.start()

        calendar.onChange = { AppController.shared.island.model.meeting = $0 }
        calendar.onAlert = { m, mins in
            AppController.shared.island.show(IslandToast(icon: "calendar", tint: .red, title: m.title,
                                                         subtitle: mins <= 0 ? "Şimdi başlıyor" : "\(mins) dk sonra başlıyor"), seconds: 6)
        }
        if prefs.islandCalendar { calendar.start() }

        privacy.onChange = { mic, cam in
            let m = AppController.shared.island.model
            m.mic = mic
            m.cam = cam
        }
        privacy.start()

        audio.onConnect = { name, level in
            guard AppController.shared.prefs.islandAudio else { return }
            AppController.shared.island.show(IslandToast(icon: AudioDeviceService.symbol(for: name), tint: .white, title: name,
                                                         subtitle: level.map { "Pil %\($0)" } ?? "Bağlandı"))
        }
        audio.start()

        timer.onFinish = { kind in
            let t: IslandToast = switch kind {
            case .focus: IslandToast(icon: "brain.head.profile", tint: .orange, title: "Odak süresi bitti", subtitle: "5 dakika mola")
            case .rest: IslandToast(icon: "cup.and.saucer.fill", tint: .green, title: "Mola bitti", subtitle: "Yeni odak başladı")
            case .simple: IslandToast(icon: "timer", tint: .orange, title: "Süre doldu", subtitle: "Zamanlayıcı")
            }
            AppController.shared.island.show(t, seconds: 6)
        }
    }

    private func batteryChanged(_ new: BatteryState, _ old: BatteryState?) {
        island.model.battery = new
        guard prefs.islandBattery, let old else { return }
        let pct = "%\(new.percent)"
        if new.onAC && !old.onAC {
            island.show(IslandToast(icon: "battery.100percent.bolt", tint: .green, title: "Şarj oluyor", subtitle: pct))
        } else if !new.onAC && old.onAC {
            island.show(IslandToast(icon: new.symbol, tint: .white, title: "Pil · \(pct)"))
        } else if !new.onAC, (new.percent <= 10 && old.percent > 10) || (new.percent <= 20 && old.percent > 20) {
            island.show(IslandToast(icon: "battery.25percent", tint: .red, title: "Pil zayıf", subtitle: "\(pct) kaldı"), seconds: 5)
        } else if new.onAC, new.percent == 100, old.percent < 100 {
            island.show(IslandToast(icon: "battery.100percent", tint: .green, title: "Tam dolu"))
        }
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
            island.show(IslandToast(icon: "arrow.triangle.2.circlepath", tint: .white, title: "Aranıyor…"))
            do {
                let r = try await Wallhaven.search(query: prefs.shuffleQuery, sort: .random, page: 1, anime: prefs.includeAnime)
                guard let w = r.items.first else { report("Sonuç bulunamadı. Arama terimini değiştirin."); return }
                try await setOnline(w, for: [mode])
                island.show(IslandToast(icon: "sparkles", tint: .mint, title: "Yeni duvar kâğıdı"))
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
