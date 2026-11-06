import AppKit
import Carbon.HIToolbox

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let `default` = HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘D")

    static let claudeDefault = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), display: "⌥Space")

    static func carbon(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        if f.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    static func symbols(_ f: NSEvent.ModifierFlags) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
    }
}

// global kısayol (Carbon, izin gerektirmez)
@MainActor final class HotKeyManager {
    static let shared = HotKeyManager()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var installed = false

    func setAction(id: UInt32, _ action: @escaping () -> Void) { actions[id] = action }

    func register(_ hk: HotKey?, id: UInt32 = 1) {
        unregister(id: id)
        guard let hk else { return }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hid = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hid)
                let id = hid.id
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyManager.shared.fire(id) } }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(hk.keyCode, hk.modifiers, EventHotKeyID(signature: OSType(0x54414E31), id: id), GetApplicationEventTarget(), 0, &ref)
        refs[id] = ref
    }

    func unregister(id: UInt32 = 1) {
        if let r = refs[id] { UnregisterEventHotKey(r) }
        refs[id] = nil
    }

    private func fire(_ id: UInt32) { actions[id]?() }
}
