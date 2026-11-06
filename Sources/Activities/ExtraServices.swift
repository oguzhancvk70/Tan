import AppKit
import Darwin

// pano geçmişi
@MainActor @Observable final class ClipboardService {
    struct Item: Identifiable {
        let id = UUID()
        var text: String?
        var image: NSImage?
        var files: [URL] = []
        var date = Date()

        var preview: String {
            if let text { return text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ") }
            if image != nil { return "Görsel" }
            return files.map(\.lastPathComponent).joined(separator: ", ")
        }

        func same(as o: Item) -> Bool {
            if let text, let t = o.text { return text == t }
            if !files.isEmpty { return files == o.files }
            return false
        }
    }

    var items: [Item] = []
    @ObservationIgnored private var lastCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var ownCount = -1
    @ObservationIgnored private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            MainActor.assumeIsolated { AppController.shared.clipboard.poll() }
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard Preferences.shared.islandClipboard, pb.changeCount != ownCount else { return }
        let types = pb.types ?? []
        let secret: [NSPasteboard.PasteboardType] = [.init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType"), .init("com.agilebits.onepassword")]
        if types.contains(where: secret.contains) { return }

        var item: Item?
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            item = Item(files: urls)
        } else if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item = Item(text: s)
        } else if types.contains(.png) || types.contains(.tiff), let img = NSImage(pasteboard: pb) {
            item = Item(image: img)
        }
        guard let item else { return }
        items.removeAll { $0.same(as: item) }
        items.insert(item, at: 0)
        if items.count > 20 { items.removeLast(items.count - 20) }
    }

    func copy(_ i: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let t = i.text { pb.setString(t, forType: .string) }
        else if let img = i.image { pb.writeObjects([img]) }
        else { pb.writeObjects(i.files as [NSURL]) }
        ownCount = pb.changeCount
        if let idx = items.firstIndex(where: { $0.id == i.id }) {
            var moved = items.remove(at: idx)
            moved.date = Date()
            items.insert(moved, at: 0)
        }
    }

    func clear() { items.removeAll() }
}

// yeni ekran görüntüleri
@MainActor final class ScreenshotWatcher {
    var onNew: ((URL) -> Void)?
    private let query = NSMetadataQuery()
    private var seen: Set<String> = []
    private let startDate = Date()

    func start() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { n in
            let added = n.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            MainActor.assumeIsolated { AppController.shared.screenshots.handle(paths) }
        }
        query.start()
    }

    private func handle(_ paths: [String]) {
        for p in paths where !seen.contains(p) {
            seen.insert(p)
            let u = URL(fileURLWithPath: p)
            let created = (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            if created >= startDate { onNew?(u) }
        }
    }
}

// İndirilenler klasörü
@MainActor final class DownloadsWatcher {
    var onNew: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private static let temp: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload"]

    func start() {
        known = Set(list())
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { MainActor.assumeIsolated { AppController.shared.downloads.scan() } }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    private func list() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] }

    private func scan() {
        let now = Set(list())
        let new = now.subtracting(known)
        known = now
        for name in new where !name.hasPrefix(".") && !Self.temp.contains((name as NSString).pathExtension.lowercased()) {
            let u = dir.appendingPathComponent(name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    if FileManager.default.fileExists(atPath: u.path) { AppController.shared.downloads.onNew?(u) }
                }
            }
        }
    }
}

// CPU, RAM, ağ, disk
@MainActor @Observable final class SystemStats {
    var cpu: Double = 0
    var memUsed: Double = 0
    var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    var down: Double = 0
    var up: Double = 0
    var diskFree: Double = 0
    var diskTotal: Double = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var prevCPU: host_cpu_load_info?
    @ObservationIgnored private var prevNet: (UInt64, UInt64, Date)?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { AppController.shared.stats.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        // cpu
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if r == KERN_SUCCESS {
            if let p = prevCPU {
                let t = info.cpu_ticks, q = p.cpu_ticks
                let user = Double(t.0 &- q.0), sys = Double(t.1 &- q.1), idle = Double(t.2 &- q.2), nice = Double(t.3 &- q.3)
                let total = user + sys + idle + nice
                if total > 0 { cpu = (user + sys + nice) / total }
            }
            prevCPU = info
        }

        // ram
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r2 = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if r2 == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let app = Double(vm.internal_page_count) - Double(vm.purgeable_count)
            memUsed = (app + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        }

        // ağ
        var ib: UInt64 = 0, ob: UInt64 = 0
        var ifa: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifa) == 0 {
            var p = ifa
            while let cur = p {
                let f = cur.pointee
                if f.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), !String(cString: f.ifa_name).hasPrefix("lo"),
                   let data = f.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    ib += UInt64(data.pointee.ifi_ibytes)
                    ob += UInt64(data.pointee.ifi_obytes)
                }
                p = f.ifa_next
            }
            freeifaddrs(ifa)
        }
        let now = Date()
        if let (pi, po, pd) = prevNet {
            let dt = now.timeIntervalSince(pd)
            if dt > 0, ib >= pi, ob >= po {
                down = Double(ib - pi) / dt
                up = Double(ob - po) / dt
            }
        }
        prevNet = (ib, ob, now)

        // disk
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Double(v.volumeTotalCapacity ?? 0)
        }
    }
}
