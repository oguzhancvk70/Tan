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
                Text("İmleç çentiğe (ya da ekranın üst ortasına) gelince açılır. Mod değişince kısa bir bildirim gösterir.")
                    .font(.caption).foregroundStyle(.secondary)
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
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Tuşlara basın…" : (hotKey?.display ?? "Yok")) { recording ? stop() : start() }
                .frame(minWidth: 120)
            if hotKey != nil && !recording {
                Button { hotKey = nil; HotKeyManager.shared.register(nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
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
        HotKeyManager.shared.register(hotKey)
    }
}
