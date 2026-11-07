import AppKit
import CoreAudio
import CoreMediaIO
import EventKit
import IOBluetooth
import IOKit.ps

// pil
struct BatteryState: Equatable {
    var percent: Int
    var charging: Bool
    var onAC: Bool

    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

@MainActor final class BatteryService {
    var onChange: ((BatteryState, BatteryState?) -> Void)?
    private(set) var state: BatteryState?
    private var source: CFRunLoopSource?

    func start() {
        source = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { AppController.shared.battery.update() }
        }, nil)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        update()
    }

    private func update() {
        guard let new = Self.read(), new != state else { return }
        let old = state
        state = new
        onChange?(new, old)
    }

    private static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryState(percent: max > 0 ? cur * 100 / max : cur,
                                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

// takvim
struct Meeting: Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var url: URL?
}

@MainActor final class CalendarService {
    var onChange: ((Meeting?) -> Void)?
    var onAlert: ((Meeting, Int) -> Void)?
    private(set) var meeting: Meeting?
    private let store = EKEventStore()
    private var timer: Timer?
    private var alerted: Set<String> = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            guard (try? await store.requestFullAccessToEvents()) == true else { started = false; return }
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                MainActor.assumeIsolated { AppController.shared.calendar.refresh() }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                MainActor.assumeIsolated { AppController.shared.calendar.refresh() }
            }
            refresh()
        }
    }

    func refresh() {
        guard Preferences.shared.islandCalendar, EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            if meeting != nil { meeting = nil; onChange?(nil) }
            return
        }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(12 * 3600), calendars: nil)
        let next = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .first { $0.startDate.timeIntervalSince(now) <= 600 && now.timeIntervalSince($0.startDate) < 600 }
        let m = next.map { e in
            Meeting(id: e.eventIdentifier ?? e.title ?? "", title: e.title ?? L("Etkinlik"), start: e.startDate, end: e.endDate, url: Self.link(e))
        }
        if m != meeting {
            meeting = m
            onChange?(m)
        }
        guard let m else { return }
        let mins = Int(ceil(m.start.timeIntervalSince(now) / 60))
        let stage = mins <= 1 ? 1 : 10
        let key = "\(m.id)-\(stage)"
        if !alerted.contains(key) {
            alerted.insert(key)
            alerted.insert("\(m.id)-10")
            onAlert?(m, max(mins, 0))
        }
    }

    private static func link(_ e: EKEvent) -> URL? {
        if let u = e.url, u.scheme?.hasPrefix("http") == true { return u }
        let text = [e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        let pattern = #"https?://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|facetime\.apple\.com)[^\s<>"]*"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(text[r]))
    }
}

// mikrofon / kamera kullanımı
@MainActor final class PrivacyService {
    var onChange: ((Bool, Bool) -> Void)?
    private(set) var mic = false
    private(set) var cam = false
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AppController.shared.privacy.poll() }
        }
        poll()
    }

    private func poll() {
        let on = Preferences.shared.islandPrivacy
        let m = on && Self.micInUse()
        let c = on && Self.camInUse()
        guard m != mic || c != cam else { return }
        mic = m
        cam = c
        onChange?(m, c)
    }

    private static let ignoredMic = ["com.apple.corespeech", "com.apple.siri", "com.apple.assistant", "com.apple.voicetrigger", "com.apple.SpeechRecognition"]

    private static func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func micInUse() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var a = addr(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return false }
        let me = getpid()
        for id in ids {
            var ra = addr(kAudioProcessPropertyIsRunningInput)
            var running: UInt32 = 0
            var rs = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &ra, 0, nil, &rs, &running) == noErr, running != 0 else { continue }
            var pa = addr(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var ps = UInt32(MemoryLayout<pid_t>.size)
            AudioObjectGetPropertyData(id, &pa, 0, nil, &ps, &pid)
            if pid == me { continue }
            var ba = addr(kAudioProcessPropertyBundleID)
            var bundle: Unmanaged<CFString>?
            var bs = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &ba, 0, nil, &bs, &bundle)
            let bid = bundle?.takeRetainedValue() as String? ?? ""
            if ignoredMic.contains(where: { bid.hasPrefix($0) }) { continue }
            return true
        }
        return false
    }

    private static func camInUse() -> Bool {
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                          mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                          mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &a, 0, nil, size, &used, &ids) == noErr else { return false }
        for id in ids {
            var ra = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                               mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                               mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var u: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &ra, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}

// kulaklık / bluetooth ses çıkışı
@MainActor final class AudioDeviceService {
    var onConnect: ((String, Int?) -> Void)?
    private var lastID: AudioDeviceID = 0

    func start() {
        lastID = Self.defaultOutput()
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main) { _, _ in
            MainActor.assumeIsolated { AppController.shared.audio.changed() }
        }
    }

    private func changed() {
        let id = Self.defaultOutput()
        guard id != lastID else { return }
        lastID = id
        let t = Self.uint(id, kAudioDevicePropertyTransportType)
        guard t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE, let name = Self.name(id) else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            onConnect?(name, Self.bluetoothBattery(name))
        }
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    private static func defaultOutput() -> AudioDeviceID {
        AudioDeviceID(uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice))
    }

    private static func uint(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var s = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v)
        return v
    }

    private static func name(_ id: AudioDeviceID) -> String? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var n: Unmanaged<CFString>?
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &n) == noErr else { return nil }
        return n?.takeRetainedValue() as String?
    }

    private static func bluetoothBattery(_ name: String) -> Int? {
        guard let devs = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let d = devs.first(where: { $0.isConnected() && $0.name == name }) else { return nil }
        func val(_ k: String) -> Int? {
            guard d.responds(to: NSSelectorFromString(k)), let v = d.value(forKey: k) as? Int, v > 0 else { return nil }
            return v
        }
        if let v = val("batteryPercentSingle") ?? val("batteryPercentCombined") { return v }
        let lr = [val("batteryPercentLeft"), val("batteryPercentRight")].compactMap { $0 }
        return lr.min()
    }
}
