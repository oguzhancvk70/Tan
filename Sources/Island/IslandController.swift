import AppKit
import SwiftUI

enum IslandPage: Hashable { case music, calendar, shelf, clipboard, system }
enum LiveKind: Equatable { case meeting, music }

struct IslandToast: Equatable {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String?
    var image: NSImage?
    var rich: Bool { subtitle != nil || image != nil }
}

@MainActor @Observable final class IslandModel {
    enum Phase { case idle, toast, expanded }
    var phase: Phase = .idle
    var page: IslandPage = .music
    var notch: CGSize = .zero
    var toast = IslandToast(icon: "music.note", tint: .white, title: "")
    var nowPlaying: NowPlaying?
    var meeting: Meeting?
    var mic = false
    var cam = false
    var battery: BatteryState?
    var shelf: [URL] = []
    var devices: [AirDevice] = []
    var systemDetails = UserDefaults.standard.bool(forKey: "islandSystemDetails") {
        didSet { UserDefaults.standard.set(systemDetails, forKey: "islandSystemDetails") }
    }

    static let wing: CGFloat = 78
    var hasNotch: Bool { notch.width > 0 }
    var notchWidth: CGFloat { hasNotch ? notch.width : 0 }
    var barHeight: CGFloat { hasNotch ? notch.height : 30 }
    var topInset: CGFloat { hasNotch ? notch.height : 6 }
    var panelSize: CGSize { CGSize(width: max(notchWidth + 440, 620), height: barHeight + 250) }
    var expandedSize: CGSize {
        let h: CGFloat = switch page {
        case .system: systemDetails ? 250 : 160
        case .shelf: 200
        default: 160
        }
        return CGSize(width: panelSize.width, height: barHeight + h)
    }

    func addToShelf(_ u: URL) {
        if !shelf.contains(u) { shelf.append(u) }
    }

    var live: LiveKind? {
        let p = Preferences.shared
        if p.islandCalendar, meeting != nil { return .meeting }
        if p.islandMusic, nowPlaying?.isPlaying == true { return .music }
        return nil
    }

    var showDots: Bool { mic || cam }

    var shapeSize: CGSize {
        switch phase {
        case .idle:
            if live != nil { return CGSize(width: hasNotch ? notchWidth + 2 * Self.wing : 230, height: barHeight) }
            if showDots { return CGSize(width: hasNotch ? notchWidth + 52 : 70, height: barHeight) }
            return hasNotch ? CGSize(width: notch.width - 6, height: notch.height - 2) : CGSize(width: 160, height: 0)
        case .toast:
            return toast.rich ? CGSize(width: max(notchWidth + 280, 380), height: topInset + 64)
                              : CGSize(width: notchWidth + 260, height: barHeight)
        case .expanded:
            return expandedSize
        }
    }

    var radius: CGFloat {
        switch phase {
        case .idle: (live != nil || showDots) ? barHeight / 2 : 8
        case .toast: toast.rich ? 22 : barHeight / 2
        case .expanded: 26
        }
    }

    var animKey: String { "\(phase)-\(String(describing: live))-\(showDots)-\(toast.rich)-\(page)-\(systemDetails)" }

    func drop(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let m = AppController.shared.island.model
                        if !m.shelf.contains(url) { m.shelf.append(url) }
                        m.page = .shelf
                    }
                }
            }
        }
    }
}

// çentik üstündeki panel (sadece ana ekran)
@MainActor final class IslandController {
    let model = IslandModel()
    private var panel: NSPanel?
    private var screen: NSScreen?
    private var hideTask: Task<Void, Never>?
    private var monitorsInstalled = false

    var isActive: Bool { panel != nil }
    var currentScreen: NSScreen? { screen }

    func setup() {
        rebuild()
        guard !monitorsInstalled else { return }
        monitorsInstalled = true
        _ = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            MainActor.assumeIsolated { AppController.shared.island.track() }
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { e in
            MainActor.assumeIsolated { AppController.shared.island.track() }
            return e
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.island.rebuild() }
        }
    }

    func rebuild() {
        panel?.orderOut(nil)
        panel = nil
        model.phase = .idle
        guard Preferences.shared.islandEnabled,
              let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else { return }
        screen = s

        var notch = CGSize.zero
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            notch = CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        model.notch = notch

        let size = model.panelSize
        let frame = NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
        let p = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.acceptsMouseMovedEvents = true
        let host = IslandHostingView(rootView: IslandView(model: model))
        host.sizingOptions = []
        p.contentView = host
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        panel = p
    }

    func track() {
        guard let s = screen, panel != nil, !ClaudePanelController.shared.isVisible else { return }
        let p = NSEvent.mouseLocation
        if model.phase == .expanded {
            let sz = model.shapeSize
            let r = NSRect(x: s.frame.midX - sz.width / 2, y: s.frame.maxY - sz.height, width: sz.width, height: sz.height)
            if !r.insetBy(dx: -12, dy: -12).contains(p) { collapse() }
            return
        }
        let w = max(model.phase == .idle ? model.shapeSize.width : 0, model.hasNotch ? model.notch.width : 200)
        let h = model.hasNotch ? model.notch.height : 4
        if NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h + 1).contains(p) {
            expand(dragging: NSEvent.pressedMouseButtons & 1 != 0)
        }
    }

    func expand(dragging: Bool = false) {
        hideTask?.cancel()
        if dragging {
            model.page = .shelf
        } else if model.phase != .expanded {
            switch model.live {
            case .meeting: model.page = .calendar
            case .music: model.page = .music
            case nil: model.page = .music
            }
        }
        model.phase = .expanded
        panel?.ignoresMouseEvents = false
    }

    func collapse() {
        model.phase = .idle
        panel?.ignoresMouseEvents = true
    }

    func show(_ t: IslandToast, seconds: Double? = nil) {
        guard panel != nil else { return }
        model.toast = t
        guard model.phase != .expanded else { return }
        model.phase = .toast
        hideTask?.cancel()
        let dur = seconds ?? (t.rich ? 3.5 : 2.4)
        hideTask = Task {
            try? await Task.sleep(for: .seconds(dur))
            if !Task.isCancelled, model.phase == .toast { model.phase = .idle }
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
