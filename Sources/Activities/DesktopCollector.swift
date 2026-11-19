import AppKit
import Darwin

// masaüstüne gelenleri ~/Documents/Ada'ya taşır
@MainActor final class DesktopCollector {
    var onCollect: ((_ old: URL, _ new: URL) -> Void)?
    var onList: (([URL]) -> Void)?
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    let target = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Ada", isDirectory: true)

    private static let quiet: TimeInterval = 10
    private static let temp: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload", "icloud"]
    private var timer: Timer?
    private var source: DispatchSourceFileSystemObject?
    private var pending: [Int: (sig: FileReady.Sig, since: Date)] = [:]
    private var busy = false

    private var ignore: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: "desktopIgnore") as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "desktopIgnore") }
    }
    private var moved: [Int] {
        get { UserDefaults.standard.array(forKey: "desktopMoved") as? [Int] ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(1000)), forKey: "desktopMoved") }
    }

    func start() {
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        watchTarget()
        reload()
        guard Preferences.shared.islandDesktop, timer == nil else { return }
        if UserDefaults.standard.object(forKey: "desktopIgnore") == nil { rebaseline() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AppController.shared.desktop.tick() }
        }
    }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        pending = [:]
        if on { rebaseline(); start() }
    }

    // masaüstünde şu an duranlar dokunulmaz
    private func rebaseline() { ignore = Set(Self.entries(desktop).map(\.ino)) }

    nonisolated private static func entries(_ dir: URL) -> [(name: String, ino: Int)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { n in
            var st = stat()
            guard lstat(dir.appendingPathComponent(n).path, &st) == 0 else { return nil }
            return (n, Int(st.st_ino))
        }
    }

    private func tick() {
        guard !busy, Preferences.shared.islandDesktop else { return }
        let old = ignore
        var ign = old
        let movedSet = Set(moved)
        let all = Self.entries(desktop)
        ign.formIntersection(all.map(\.ino))
        var cands: [(name: String, ino: Int)] = []
        for e in all where !ign.contains(e.ino) {
            if e.name.hasPrefix(".") || Self.temp.contains((e.name as NSString).pathExtension.lowercased()) { continue }
            if movedSet.contains(e.ino) { ign.insert(e.ino); continue }
            cands.append(e)
        }
        if ign != old { ignore = ign }
        let live = Set(cands.map(\.ino))
        pending = pending.filter { live.contains($0.key) }
        guard !cands.isEmpty else { return }
        busy = true
        let dir = desktop, tgt = target, list = cands
        Task.detached(priority: .utility) {
            let checks = list.map { FileReady.check(dir.appendingPathComponent($0.name), ino: $0.ino, target: tgt) }
            await MainActor.run { AppController.shared.desktop.apply(checks) }
        }
    }

    private func apply(_ checks: [FileReady.Check]) {
        busy = false
        guard Preferences.shared.islandDesktop else { return }
        let now = Date()
        for c in checks {
            guard let sig = c.sig else { pending[c.ino] = nil; continue }
            if c.dupe { ignore.insert(c.ino); pending[c.ino] = nil; continue }
            guard !c.open, let p = pending[c.ino], p.sig == sig else { pending[c.ino] = (sig, now); continue }
            if now.timeIntervalSince(p.since) >= Self.quiet {
                pending[c.ino] = nil
                collect(c.url, c.ino)
            }
        }
    }

    private func collect(_ u: URL, _ ino: Int) {
        var st = stat()
        guard lstat(u.path, &st) == 0, Int(st.st_ino) == ino else { return }
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let dest = Self.unique(u.lastPathComponent, in: target)
        do {
            try FileManager.default.moveItem(at: u, to: dest)
        } catch {
            NSLog("Tan masaüstü: \(error.localizedDescription)")
            ignore.insert(ino)
            return
        }
        if lstat(dest.path, &st) == 0 { moved.append(Int(st.st_ino)) }
        reload()
        onCollect?(u, dest)
    }

    // raf işlemleri
    func putBack(_ u: URL) {
        let dest = Self.unique(u.lastPathComponent, in: desktop)
        guard (try? FileManager.default.moveItem(at: u, to: dest)) != nil else { return }
        var st = stat()
        if lstat(dest.path, &st) == 0 { ignore.insert(Int(st.st_ino)) }
        reload()
    }

    func trash(_ u: URL) {
        try? FileManager.default.trashItem(at: u, resultingItemURL: nil)
        reload()
    }

    func reload() {
        let key = URLResourceKey.addedToDirectoryDateKey
        let items = (try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: [key], options: [.skipsHiddenFiles])) ?? []
        let sorted = items
            .map { ($0, (try? $0.resourceValues(forKeys: [key]).addedToDirectoryDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        onList?(sorted)
    }

    private func watchTarget() {
        guard source == nil else { return }
        let fd = open(target.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        s.setEventHandler { MainActor.assumeIsolated { AppController.shared.desktop.reload() } }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    nonisolated static func unique(_ name: String, in dir: URL) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var u = dir.appendingPathComponent(name)
        var i = 2
        var st = stat()
        while lstat(u.path, &st) == 0 {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        return u
    }

    nonisolated static func isScreenCapture(_ u: URL) -> Bool {
        getxattr(u.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
}

// dosya yazımı bitti mi kontrolleri
enum FileReady {
    struct Sig: Equatable, Sendable { var size: Int64 = 0; var mtime: Double = 0; var count = 0 }
    struct Check: Sendable { let url: URL; let ino: Int; let sig: Sig?; let open: Bool; let dupe: Bool }

    static func check(_ u: URL, ino: Int, target: URL) -> Check {
        let sig = signature(u)
        guard let sig else { return Check(url: u, ino: ino, sig: nil, open: false, dupe: false) }
        let t = target.appendingPathComponent(u.lastPathComponent)
        let dupe = signature(t).map { $0.size == sig.size && $0.count == sig.count } ?? false
        return Check(url: u, ino: ino, sig: sig, open: dupe ? false : isOpen(u), dupe: dupe)
    }

    // boyut + son değişiklik + öğe sayısı; Finder kopyalıyorsa nil
    static func signature(_ url: URL) -> Sig? {
        var u = url
        u.removeAllCachedResourceValues()
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard !isBusy(u), let v = try? u.resourceValues(forKeys: keys) else { return nil }
        var s = Sig(size: Int64(v.fileSize ?? 0), mtime: v.contentModificationDate?.timeIntervalSince1970 ?? 0, count: 1)
        if v.isDirectory == true, let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: Array(keys)) {
            for case let c as URL in en {
                if isBusy(c) { return nil }
                let cv = try? c.resourceValues(forKeys: keys)
                s.size += Int64(cv?.fileSize ?? 0)
                s.mtime = max(s.mtime, cv?.contentModificationDate?.timeIntervalSince1970 ?? 0)
                s.count += 1
            }
        }
        return s
    }

    // Finder kopyalama işareti: 'brok'/'bzy ' tipi ya da sihirli oluşturma tarihi
    private static let busyDates = [
        Date(timeIntervalSince1970: 443_779_200 + 8 * 3600),          // 1984-01-24 08:00 UTC (APFS'te ölçüldü)
        Date(timeIntervalSinceReferenceDate: Double(0x4F3AFDB0) - 3_061_152_000)
    ]

    static func isBusy(_ u: URL) -> Bool {
        var info = [UInt8](repeating: 0, count: 32)
        if getxattr(u.path, "com.apple.FinderInfo", &info, 32, 0, XATTR_NOFOLLOW) >= 4 {
            let type = String(bytes: info[0..<4], encoding: .macOSRoman) ?? ""
            if type == "brok" || type.hasPrefix("bzy") { return true }
        }
        if let c = try? URL(fileURLWithPath: u.path).resourceValues(forKeys: [.creationDateKey]).creationDate,
           busyDates.contains(where: { abs(c.timeIntervalSince($0)) < 86_400 }) { return true }
        return false
    }

    // herhangi bir süreç dosyayı açık tutuyor mu (lsof eşdeğeri)
    private typealias ListPids = @convention(c) (UInt32, UInt32, UnsafePointer<CChar>, UInt32, UnsafeMutableRawPointer?, Int32) -> Int32
    private static let listPids: ListPids? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "proc_listpidspath").map { unsafeBitCast($0, to: ListPids.self) }

    static func isOpen(_ u: URL) -> Bool {
        guard let f = listPids else { return false }
        var paths = [u.path]
        if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
           let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let c as URL in en where paths.count < 300 {
                if (try? c.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { paths.append(c.path) }
            }
        }
        let me = getpid()
        var buf = [Int32](repeating: 0, count: 2048)
        for p in paths {
            let n = p.withCString { cs in
                buf.withUnsafeMutableBytes { f(1, 0, cs, 2, $0.baseAddress, Int32($0.count)) }
            }
            if n > 0, buf.prefix(Int(n) / 4).contains(where: { $0 > 0 && $0 != me }) { return true }
        }
        return false
    }
}
