import SwiftUI
import UniformTypeIdentifiers

// duvar kâğıtları sekmesi
struct WallpapersTab: View {
    @Bindable var prefs = Preferences.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                WallpaperCard(mode: .light)
                WallpaperCard(mode: .dark)
            }
            Form {
                Toggle("Koyu modda duvar kâğıdını karart", isOn: $prefs.dimDark)
                    .onChange(of: prefs.dimDark) { AppController.shared.reapply() }
                if prefs.dimDark {
                    Slider(value: $prefs.dimAmount, in: 0.05...0.6) { editing in
                        if !editing { AppController.shared.reapply() }
                    } label: {
                        Text("Karartma: %\(Int(prefs.dimAmount * 100))")
                    }
                }
                Picker("Klasör döngüsü", selection: $prefs.rotation) {
                    ForEach(RotationInterval.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: prefs.rotation) { AppController.shared.scheduleRotation() }
                Picker("Bing günün görseli", selection: $prefs.bingTarget) {
                    ForEach(BingTarget.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: prefs.bingTarget) { Task { await AppController.shared.checkBing() } }
            }
            .formStyle(.grouped)
        }
    }
}

struct WallpaperCard: View {
    let mode: Mode
    private let app = AppController.shared
    @State private var showSystem = false

    var body: some View {
        let _ = app.revision
        let choice = Preferences.shared.choice(for: mode)
        VStack(alignment: .leading, spacing: 8) {
            Label(mode == .light ? "Açık Mod" : "Koyu Mod", systemImage: mode == .light ? "sun.max.fill" : "moon.fill")
                .font(.headline)
            LocalThumb(url: app.wallpaper.preview(mode))
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if mode == app.mode {
                        Text("Etkin").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green, in: Capsule()).foregroundStyle(.white).padding(8)
                    }
                }
            HStack {
                Text(choice.map { ($0.isFolder ? "Klasör: " : "") + $0.caption } ?? "Seçilmedi")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let link = choice?.link.flatMap(URL.init(string:)) {
                    Link(choice?.credit ?? "Kaynak", destination: link).font(.caption).lineLimit(1)
                } else if let credit = choice?.credit {
                    Text(credit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Menu("Değiştir") {
                Button("Sistem Duvar Kâğıtları…") { showSystem = true }
                Button("Dosya Seç…") { pick(folder: false) }
                Button("Klasör Seç (döngü)…") { pick(folder: true) }
                Button("Galeriden…") { SettingsWindow.shared.nav.tab = .gallery }
                if choice != nil {
                    Divider()
                    Button("Kaldır", role: .destructive) { app.choose(nil, for: mode) }
                }
            }
            .frame(maxWidth: 140)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showSystem) {
            SystemPicker { url in
                app.choose(WallpaperChoice(path: url.path, title: url.deletingPathExtension().lastPathComponent), for: mode)
            }
        }
    }

    private func pick(folder: Bool) {
        let p = NSOpenPanel()
        p.canChooseFiles = !folder
        p.canChooseDirectories = folder
        p.allowsMultipleSelection = false
        if !folder { p.allowedContentTypes = [.image] }
        p.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let u = p.url else { return }
        app.choose(WallpaperChoice(path: u.path, isFolder: folder, title: u.lastPathComponent), for: mode)
    }
}

// sistem duvar kâğıtları
struct SystemPicker: View {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urls: [URL] = []

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sistem Duvar Kâğıtları").font(.headline)
                Spacer()
                Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(urls, id: \.self) { u in
                        Button { onPick(u); dismiss() } label: {
                            VStack(spacing: 4) {
                                LocalThumb(url: u, maxPixel: 320)
                                    .frame(height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(u.deletingPathExtension().lastPathComponent).font(.caption).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(width: 720, height: 520)
        .task { urls = await Task.detached { SystemWallpaperSource.all() }.value }
    }
}

// yerel önizleme
struct LocalThumb: View {
    let url: URL?
    var maxPixel = 480
    @State private var image: NSImage?

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if url == nil {
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipped()
            .task(id: url) {
                image = nil
                guard let url else { return }
                let mp = maxPixel
                image = await Task.detached { Thumbnail.make(url, maxPixel: mp) }.value
            }
    }
}
