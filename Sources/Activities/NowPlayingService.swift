import AppKit

struct NowPlaying: Equatable {
    enum Source { case remote, spotify, music }
    var title: String
    var artist: String
    var duration: Double
    var elapsed: Double
    var stamp: Date
    var isPlaying: Bool
    var appName: String?
    var bundleID: String?
    var artwork: NSImage?
    var source: Source

    var key: String { "\(title)|\(artist)" }

    func position(at d: Date) -> Double {
        let p = isPlaying ? elapsed + d.timeIntervalSince(stamp) : elapsed
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

enum MediaCommand: Int { case playPause = 2, next = 4, previous = 5 }

// şu an çalan: MediaRemote (perl köprüsü) + Spotify/Müzik yedeği
@MainActor final class NowPlayingService {
    var onChange: ((NowPlaying?, Bool) -> Void)?
    private(set) var current: NowPlaying?
    private var remote: NowPlaying?
    private var script: NowPlaying?
    private var remoteAlive = false
    private var process: Process?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    private var restarts = 0
    private var artCache: (key: String, length: Int, image: NSImage?)?

    private static let perl = #"use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die; my $s = DynaLoader::dl_find_symbol($h, $ARGV[1]) or die; DynaLoader::dl_install_xsub("main::r", $s); main::r();"#
    private var adapterPath: String? { Bundle.main.path(forResource: "MediaRemoteAdapter", ofType: "dylib") }

    func start() {
        startAdapter()
        observeScripts()
    }

    // MediaRemote köprüsü
    private func startAdapter() {
        guard let lib = adapterPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perl, lib, "tan_stream"]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { MainActor.assumeIsolated { AppController.shared.nowPlaying.consume(d) } }
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppController.shared.nowPlaying.adapterDied() } }
        }
        do {
            try p.run()
            process = p
            stdinPipe = inp
        } catch {
            NSLog("Tan: MediaRemote köprüsü başlamadı: \(error.localizedDescription)")
        }
    }

    private func adapterDied() {
        remoteAlive = false
        process = nil
        stdinPipe = nil
        remote = nil
        publish()
        guard restarts < 5 else { return }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { AppController.shared.nowPlaying.startAdapter() }
        }
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            remoteAlive = true
            restarts = 0
            remote = parse(obj)
            publish()
        }
    }

    private func parse(_ o: [String: Any]) -> NowPlaying? {
        let pid = o["pid"] as? Int ?? 0
        guard pid != 0, let title = o["title"] as? String, !title.isEmpty else { return nil }
        let app = NSRunningApplication(processIdentifier: pid_t(pid))
        let artist = o["artist"] as? String ?? ""
        let key = "\(title)|\(artist)"
        var art: NSImage?
        if let b64 = o["artwork"] as? String {
            if let c = artCache, c.key == key, c.length == b64.utf8.count {
                art = c.image
            } else {
                art = Data(base64Encoded: b64).flatMap(NSImage.init(data:))
                artCache = (key, b64.utf8.count, art)
            }
        } else if let c = artCache, c.key == key {
            art = c.image
        }
        let rate = o["rate"] as? Double ?? 0
        let ts = (o["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        return NowPlaying(title: title, artist: artist, duration: o["duration"] as? Double ?? 0,
                          elapsed: o["elapsed"] as? Double ?? 0, stamp: ts,
                          isPlaying: o["playing"] as? Bool ?? (rate > 0),
                          appName: app?.localizedName, bundleID: app?.bundleIdentifier, artwork: art, source: .remote)
    }

    // Spotify / Müzik bildirimleri
    private func observeScripts() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { n in
            let info = n.userInfo ?? [:]
            MainActor.assumeIsolated { AppController.shared.nowPlaying.scriptUpdate(info, source: .spotify) }
        }
        dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { n in
            let info = n.userInfo ?? [:]
            MainActor.assumeIsolated { AppController.shared.nowPlaying.scriptUpdate(info, source: .music) }
        }
    }

    private func scriptUpdate(_ info: [AnyHashable: Any], source: NowPlaying.Source) {
        let state = info["Player State"] as? String ?? ""
        guard state != "Stopped", let title = info["Name"] as? String else {
            script = nil
            publish()
            return
        }
        let spotify = source == .spotify
        let durMs = info[spotify ? "Duration" : "Total Time"] as? Double ?? 0
        var np = NowPlaying(title: title, artist: info["Artist"] as? String ?? "", duration: durMs / 1000,
                            elapsed: info["Playback Position"] as? Double ?? 0, stamp: Date(), isPlaying: state == "Playing",
                            appName: spotify ? "Spotify" : L("Müzik"), bundleID: spotify ? "com.spotify.client" : "com.apple.Music",
                            artwork: nil, source: source)
        if script?.key == np.key { np.artwork = script?.artwork }
        if !remoteAlive {
            if !spotify, let pos = Self.run("tell application \"Music\" to get player position")?.doubleValue { np.elapsed = pos }
            if np.artwork == nil { fetchArtwork(spotify: spotify, key: np.key) }
        }
        script = np
        publish()
    }

    private func fetchArtwork(spotify: Bool, key: String) {
        Task {
            var img: NSImage?
            if spotify {
                if let s = Self.run("tell application \"Spotify\" to get artwork url of current track")?.stringValue,
                   let u = URL(string: s), let d = try? await Net.get(u) {
                    img = NSImage(data: d)
                }
            } else if let d = Self.run("tell application \"Music\" to get data of artwork 1 of current track")?.data {
                img = NSImage(data: d)
            }
            guard let img, script?.key == key else { return }
            script?.artwork = img
            publish()
        }
    }

    private func publish() {
        let new = remoteAlive ? remote : script
        guard new != current else { return }
        let changed = new != nil && new?.key != current?.key
        current = new
        onChange?(new, changed)
    }

    // kontrol
    func command(_ c: MediaCommand) {
        guard var np = current else { return }
        if np.source == .remote, let pipe = stdinPipe {
            try? pipe.fileHandleForWriting.write(contentsOf: Data("\(c.rawValue)\n".utf8))
        } else if np.source == .remote, let lib = adapterPath {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = ["-e", Self.perl, lib, "tan_send"]
            p.environment = ["TAN_CMD": String(c.rawValue)]
            p.standardError = FileHandle.nullDevice
            try? p.run()
        } else {
            let app = np.source == .spotify ? "Spotify" : "Music"
            let verb = c == .playPause ? "playpause" : (c == .next ? "next track" : "previous track")
            Self.run("tell application \"\(app)\" to \(verb)")
        }
        if c == .playPause {
            np.elapsed = np.position(at: Date())
            np.stamp = Date()
            np.isPlaying.toggle()
            current = np
            onChange?(np, false)
        }
    }

    func openSourceApp() {
        guard let id = current?.bundleID, let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: u, configuration: .init())
    }

    @discardableResult private static func run(_ src: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return err == nil ? r : nil
    }
}
