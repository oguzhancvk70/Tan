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
        case .meeting: Image(systemName: "calendar").foregroundStyle(.red)
        }
    }

    @ViewBuilder private var right: some View {
        switch live {
        case .music:
            EqualizerBars(playing: model.nowPlaying?.isPlaying == true).frame(width: 20, height: 14)
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
    return mins > 0 ? L("\(mins) dk") : L("Şimdi")
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
                    tab(.music, "music.note", "Müzik")
                    tab(.calendar, "calendar", "Takvim")
                    tab(.shelf, "tray.fill", "Raf")
                    tab(.clipboard, "doc.on.clipboard", "Pano")
                    tab(.system, "gauge.with.dots.needle.33percent", "Sistem")
                }
                Spacer(minLength: model.hasNotch ? model.notch.width + 8 : 8)
                HStack(spacing: 6) {
                    PrivacyDots(model: model)
                    if let b = model.battery {
                        Image(systemName: b.symbol).foregroundStyle(b.charging ? .green : (b.percent <= 20 ? .red : .white))
                        Text(pct(b.percent)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    Button { ClaudePanelController.shared.show() } label: {
                        Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Claude ile sohbet")
                    Button {
                        AppController.shared.island.collapse()
                        SettingsWindow.shared.show()
                    } label: {
                        Image(systemName: "gearshape.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Ayarlar")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: model.barHeight)

            Group {
                switch model.page {
                case .calendar: CalendarPage(model: model)
                case .music: MusicPage(model: model)
                case .shelf: ShelfPage(model: model)
                case .clipboard: ClipboardPage()
                case .system: SystemPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
    }

    private func tab(_ p: IslandPage, _ icon: String, _ help: LocalizedStringKey) -> some View {
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

struct CalendarPage: View {
    let model: IslandModel

    var body: some View {
        VStack(spacing: 10) {
            if model.meeting == nil {
                VStack(spacing: 8) {
                    Image(systemName: "calendar").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Yaklaşan toplantı yok").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .help(L("\(n.appName ?? L("Uygulama")) uygulamasını aç"))
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

struct ShelfPage: View {
    @Bindable var model: IslandModel

    var body: some View {
        VStack(spacing: 10) {
            // AirDrop cihaz kutucukları
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.devices) { DeviceBox(name: $0.name, symbol: $0.symbol, shelf: model.shelf) }
                    DeviceBox(name: model.devices.isEmpty ? "AirDrop" : L("Diğer"), symbol: "dot.radiowaves.left.and.right", shelf: model.shelf)
                }
            }
            .frame(height: 58)

            if model.shelf.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20))
                    Text("Dosyaları rafa ya da bir cihaza sürükleyin").font(.system(size: 11))
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
                    IslandButton(icon: "trash", help: "Rafı temizle") { model.shelf.removeAll() }
                }
            }
        }
        .onAppear { model.devices = AirDrop.devices() }
    }
}

struct DeviceBox: View {
    let name: String
    let symbol: String
    let shelf: [URL]
    @State private var targeted = false
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18))
            Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .frame(width: 92, height: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.blue.opacity(0.5) : .white.opacity(hover ? 0.16 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Color.blue : .white.opacity(0.12), lineWidth: 1))
        .scaleEffect(targeted ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { AirDrop.send(shelf) }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { AirDrop.receive($0); return true }
        .help(shelf.isEmpty ? L("\(name): dosyayı buraya bırak") : L("\(name): dosya bırak ya da tıkla, raftakiler gitsin"))
    }
}

struct FileChip: View {
    let url: URL
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 52, height: 52)
            Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).frame(width: 76)
        }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .help(url.path)
    }
}

struct IslandButton: View {
    let icon: String
    let help: LocalizedStringKey
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
