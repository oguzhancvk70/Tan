import SwiftUI

enum SettingsTab: Hashable { case wallpapers, gallery, general }

@MainActor @Observable final class SettingsNav {
    var tab: SettingsTab = .wallpapers
}

// ayarlar penceresi
@MainActor final class SettingsWindow {
    static let shared = SettingsWindow()
    let nav = SettingsNav()
    private var window: NSWindow?

    func show(tab: SettingsTab? = nil) {
        if let tab { nav.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Tan"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(nav: nav))
            w.setContentSize(NSSize(width: 800, height: 600))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable var nav: SettingsNav

    var body: some View {
        TabView(selection: $nav.tab) {
            WallpapersTab()
                .tabItem { Label("Duvar Kâğıtları", systemImage: "photo.on.rectangle") }
                .tag(SettingsTab.wallpapers)
            GalleryView()
                .tabItem { Label("Galeri", systemImage: "globe") }
                .tag(SettingsTab.gallery)
            GeneralTab()
                .tabItem { Label("Genel", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .padding()
        .frame(minWidth: 720, minHeight: 540)
    }
}

// genel
struct GeneralTab: View {
    @Bindable var prefs = Preferences.shared
    @State private var login = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Başlangıç") {
                Toggle("Oturum açılışında başlat", isOn: $login)
                    .onChange(of: login) { _, v in
                        do { try LoginItem.set(v); loginError = nil }
                        catch { loginError = error.localizedDescription }
                        login = LoginItem.isEnabled
                    }
                if !LoginItem.isInstalled {
                    Text("Uygulama /Applications içinde değil. Kalıcı kurulum için: make install")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Kısayol") {
                LabeledContent("Modu değiştir") { ShortcutRecorder(hotKey: $prefs.hotKey) }
            }
            Section("Dinamik Ada") {
                Toggle("Dinamik adayı göster", isOn: $prefs.islandEnabled)
                    .onChange(of: prefs.islandEnabled) { AppController.shared.island.rebuild() }
                Toggle("Şu an çalan (Spotify, Müzik, tarayıcı…)", isOn: $prefs.islandMusic)
                Toggle("Pil ve şarj bildirimleri", isOn: $prefs.islandBattery)
                Toggle("Takvim: yaklaşan toplantı", isOn: $prefs.islandCalendar)
                    .onChange(of: prefs.islandCalendar) { _, on in
                        if on { AppController.shared.calendar.start() }
                        AppController.shared.calendar.refresh()
                    }
                Toggle("Mikrofon / kamera göstergesi", isOn: $prefs.islandPrivacy)
                Toggle("Kulaklık bağlantısı", isOn: $prefs.islandAudio)
                Toggle("Pano geçmişi", isOn: $prefs.islandClipboard)
                Toggle("Yeni ekran görüntülerini Raf'a ekle", isOn: $prefs.islandScreenshots)
                Toggle("Biten indirmeleri Raf'a ekle", isOn: $prefs.islandDownloads)
                Text("İmleç çentiğe gelince açılır: Ana, Müzik, Zamanlayıcı ve Raf sayfaları. Rafa dosya sürükleyip AirDrop ile gönderebilirsiniz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude") {
                LabeledContent("Sohbeti aç") { ShortcutRecorder(hotKey: $prefs.claudeHotKey, id: 2) }
                LabeledContent("Çalışma klasörü") {
                    HStack {
                        Text((prefs.claudeFolder as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary)
                        Button("Seç…") {
                            let o = NSOpenPanel()
                            o.canChooseDirectories = true
                            o.canChooseFiles = false
                            if o.runModal() == .OK, let u = o.url { prefs.claudeFolder = u.path }
                        }
                    }
                }
                Toggle("Claude dosya düzenleyebilsin", isOn: $prefs.claudeEdits)
                Text(ClaudeChat.binary() != nil ? "Claude Code bulundu; sohbet aboneliğinle çalışır." : "Claude Code bulunamadı. VS Code'da Claude Code eklentisi kurulu olmalı.")
                    .font(.caption).foregroundStyle(ClaudeChat.binary() != nil ? Color.secondary : Color.orange)
            }
            Section("Rastgele Duvar Kâğıdı") {
                TextField("Arama terimi (boş bırakılırsa hepsi)", text: $prefs.shuffleQuery)
                Toggle("Anime görselleri de dahil", isOn: $prefs.includeAnime)
            }
            Section {
                Text("Tan \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · Kaynaklar: Wallhaven API, Bing")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// kısayol kaydedici
struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey?
    var id: UInt32 = 1
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Tuşlara basın…" : (hotKey?.display ?? "Yok")) { recording ? stop() : start() }
                .frame(minWidth: 120)
            if hotKey != nil && !recording {
                Button { hotKey = nil; HotKeyManager.shared.register(nil, id: id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister(id: id)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            let f = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !f.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            let key = e.keyCode == 49 ? "Space" : (e.charactersIgnoringModifiers?.uppercased() ?? "?")
            hotKey = HotKey(keyCode: UInt32(e.keyCode), modifiers: HotKey.carbon(f), display: HotKey.symbols(f) + key)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyManager.shared.register(hotKey, id: id)
    }
}
