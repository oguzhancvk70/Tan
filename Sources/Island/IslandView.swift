import SwiftUI
import UniformTypeIdentifiers

func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded(.up)))
    let h = s / 3600, m = s % 3600 / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

struct IslandView: View {
    let model: IslandModel

    var body: some View {
        let s = model.shapeSize
        ZStack(alignment: .top) {
            Color.black
            switch model.phase {
            case .idle:
                if let live = model.live {
                    CompactLive(model: model, live: live).transition(.opacity)
                } else if model.showDots {
                    HStack { Spacer(); PrivacyDots(model: model) }.padding(.horizontal, 12).frame(height: model.barHeight)
                }
            case .toast:
                ToastView(model: model).transition(.opacity)
            case .expanded:
                ExpandedView(model: model).transition(.opacity)
            }
        }
        .frame(width: s.width, height: s.height)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: model.radius, bottomTrailingRadius: model.radius, style: .continuous))
        .shadow(color: .black.opacity(model.phase == .expanded ? 0.35 : 0), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.animKey)
        .environment(\.colorScheme, .dark)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            model.drop(providers)
            return true
        }
    }
}

// kompakt canlı etkinlik (çentiğin iki yanı)
struct CompactLive: View {
    let model: IslandModel
    let live: LiveKind
    private var timer: TimerService { AppController.shared.timer }

    var body: some View {
        HStack(spacing: 6) {
            left
            Spacer(minLength: model.hasNotch ? model.notch.width : 8)
            right
            if model.showDots { PrivacyDots(model: model) }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: model.barHeight)
    }

    @ViewBuilder private var left: some View {
        switch live {
        case .music: ArtworkView(image: model.nowPlaying?.artwork, size: 20, radius: 5)
        case .timer: Image(systemName: "timer").foregroundStyle(timer.kind == .rest ? .green : .orange)
        case .meeting: Image(systemName: "calendar").foregroundStyle(.red)
        }
    }

    @ViewBuilder private var right: some View {
        switch live {
        case .music:
            EqualizerBars(playing: model.nowPlaying?.isPlaying == true).frame(width: 20, height: 14)
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(clock(timer.remaining(at: ctx.date))).monospacedDigit()
                    .foregroundStyle(timer.isRunning ? .white : .secondary)
            }
        case .meeting:
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                Text(meetingText(model.meeting, ctx.date))
            }
        }
    }
}

func meetingText(_ m: Meeting?, _ now: Date) -> String {
    guard let m else { return "" }
    let mins = Int(ceil(m.start.timeIntervalSince(now) / 60))
    return mins > 0 ? "\(mins) dk" : "Şimdi"
}

struct PrivacyDots: View {
    let model: IslandModel
    var body: some View {
        HStack(spacing: 3) {
            if model.cam { Circle().fill(.green).frame(width: 6, height: 6).help("Kamera kullanımda") }
            if model.mic { Circle().fill(.orange).frame(width: 6, height: 6).help("Mikrofon kullanımda") }
        }
    }
}

struct EqualizerBars: View {
    let playing: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let h = playing ? 0.3 + 0.7 * abs(sin(t * (2.6 + Double(i) * 0.9) + Double(i))) : 0.3
                    Capsule().fill(.green).frame(width: 3, height: 14 * h)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// bildirim
struct ToastView: View {
    let model: IslandModel

    var body: some View {
        let t = model.toast
        if t.rich {
            VStack(spacing: 0) {
                Color.clear.frame(height: model.topInset)
                HStack(spacing: 12) {
                    if let img = t.image {
                        ArtworkView(image: img, size: 44, radius: 10)
                    } else {
                        Image(systemName: t.icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(t.tint).frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if let s = t.subtitle { Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
        } else {
            HStack(spacing: 8) {
                Image(systemName: t.icon).font(.system(size: 14, weight: .bold)).foregroundStyle(t.tint)
                if model.hasNotch { Spacer(minLength: model.notch.width) }
                Text(t.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: model.barHeight)
        }
    }
}

// açılmış ada
struct ExpandedView: View {
    @Bindable var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    tab(.home, "house.fill", "Ana")
                    tab(.music, "music.note", "Müzik")
                    tab(.timer, "timer", "Zamanlayıcı")
                    tab(.shelf, "tray.fill", "Raf")
                }
                Spacer(minLength: model.hasNotch ? model.notch.width + 8 : 8)
                HStack(spacing: 6) {
                    PrivacyDots(model: model)
                    if let b = model.battery {
                        Image(systemName: b.symbol).foregroundStyle(b.charging ? .green : (b.percent <= 20 ? .red : .white))
                        Text("%\(b.percent)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: model.barHeight)

            Group {
                switch model.page {
                case .home: HomePage(model: model)
                case .music: MusicPage(model: model)
                case .timer: TimerPage()
                case .shelf: ShelfPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
    }

    private func tab(_ p: IslandPage, _ icon: String, _ help: String) -> some View {
        Button { model.page = p } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(model.page == p ? 0.18 : 0)))
                .foregroundStyle(model.page == p ? .white : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct HomePage: View {
    let model: IslandModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Color.white.opacity(0.08)
                    .overlay { if let t = model.thumb { Image(nsImage: t).resizable().scaledToFill() } }
                    .frame(width: 120, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duvar Kâğıdı").font(.system(size: 15, weight: .semibold))
                    Text(model.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                IslandButton(icon: "shuffle", help: "Rastgele duvar kâğıdı") { AppController.shared.shuffle() }
                IslandButton(icon: "gearshape.fill", help: "Ayarlar") {
                    AppController.shared.island.collapse()
                    SettingsWindow.shared.show()
                }
            }
            if let m = model.meeting {
                HStack(spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 15)) { ctx in
                            Text("\(m.start.formatted(date: .omitted, time: .shortened)) · \(meetingText(m, ctx.date))")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let u = m.url {
                        Button("Katıl") { NSWorkspace.shared.open(u) }
                            .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
            }
            Spacer(minLength: 0)
        }
    }
}

struct MusicPage: View {
    let model: IslandModel
    private var np: NowPlayingService { AppController.shared.nowPlaying }

    var body: some View {
        if let n = model.nowPlaying {
            HStack(spacing: 16) {
                Button { np.openSourceApp() } label: { ArtworkView(image: n.artwork, size: 100, radius: 14) }
                    .buttonStyle(.plain)
                    .help("\(n.appName ?? "Uygulama") uygulamasını aç")
                VStack(alignment: .leading, spacing: 6) {
                    Text(n.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(n.artist.isEmpty ? (n.appName ?? "") : n.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    if n.duration > 0 {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let pos = n.position(at: ctx.date)
                            HStack(spacing: 6) {
                                Text(clock(pos)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(.white.opacity(0.2))
                                        Capsule().fill(.white).frame(width: g.size.width * min(1, pos / n.duration))
                                    }
                                }
                                .frame(height: 4)
                                Text(clock(n.duration)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 14)
                    }
                    HStack(spacing: 14) {
                        IslandButton(icon: "backward.fill", help: "Önceki") { np.command(.previous) }
                        IslandButton(icon: n.isPlaying ? "pause.fill" : "play.fill", help: "Çal / Duraklat") { np.command(.playPause) }
                        IslandButton(icon: "forward.fill", help: "Sonraki") { np.command(.next) }
                        Spacer()
                        if let app = n.appName { Text(app).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Şu an çalan bir şey yok").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button("Spotify") { open("com.spotify.client") }
                    Button("Müzik") { open("com.apple.Music") }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func open(_ bundle: String) {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: u, configuration: .init())
        }
    }
}

struct TimerPage: View {
    private var timer: TimerService { AppController.shared.timer }

    var body: some View {
        if timer.isActive {
            HStack(spacing: 18) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let r = timer.remaining(at: ctx.date)
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: timer.total > 0 ? r / timer.total : 0)
                            .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(clock(r)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    .frame(width: 92, height: 92)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(label).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 10) {
                        IslandButton(icon: timer.isRunning ? "pause.fill" : "play.fill", help: timer.isRunning ? "Duraklat" : "Devam") { timer.pauseResume() }
                        IslandButton(icon: "stop.fill", help: "Durdur") { timer.stop() }
                    }
                }
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Zamanlayıcı").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 8) {
                    preset("1 dk", 1); preset("5 dk", 5); preset("10 dk", 10); preset("30 dk", 30); preset("1 sa", 60)
                }
                Button { timer.start(minutes: 25, kind: .focus, pomodoro: true) } label: {
                    Label("Pomodoro (25 dk odak + 5 dk mola)", systemImage: "brain.head.profile")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(.orange.opacity(0.25)))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tint: Color { timer.kind == .rest ? .green : .orange }
    private var label: String {
        switch timer.kind {
        case .simple: "Zamanlayıcı"
        case .focus: "Odak"
        case .rest: "Mola"
        }
    }

    private func preset(_ title: String, _ min: Double) -> some View {
        Button { timer.start(minutes: min) } label: {
            Text(title).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

struct ShelfPage: View {
    @Bindable var model: IslandModel

    var body: some View {
        if model.shelf.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 26))
                Text("Dosyaları buraya sürükleyin").font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
        } else {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.shelf, id: \.self) { u in FileChip(url: u) }
                    }
                }
                VStack(spacing: 8) {
                    IslandButton(icon: "paperplane.fill", help: "AirDrop ile gönder") {
                        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: model.shelf)
                    }
                    IslandButton(icon: "trash", help: "Rafı temizle") { model.shelf.removeAll() }
                }
            }
        }
    }
}

struct FileChip: View {
    let url: URL
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 52, height: 52)
            Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).frame(width: 76)
        }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .help(url.path)
    }
}

struct IslandButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(hover ? 0.22 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
