import AppKit
import Carbon.HIToolbox

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let `default` = HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘D")

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
    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var installed = false

    func register(_ hk: HotKey?) {
        unregister()
        guard let hk else { return }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyManager.shared.action?() } }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x54414E31), id: 1)
        RegisterEventHotKey(hk.keyCode, hk.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
