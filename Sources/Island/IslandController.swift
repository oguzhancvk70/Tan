import AppKit
import SwiftUI

@MainActor @Observable final class IslandModel {
    enum Phase { case idle, toast, expanded }
    var phase: Phase = .idle
    var notch: CGSize = .zero
    var icon = "moon.fill"
    var text = ""
    var tint: Color = .white
    var thumb: NSImage?
    var subtitle = ""
    var isDark = false

    var hasNotch: Bool { notch.width > 0 }
    var barHeight: CGFloat { hasNotch ? notch.height : 30 }
    var panelSize: CGSize { CGSize(width: max(notch.width + 300, 460), height: barHeight + 120) }

    var shapeSize: CGSize {
        switch phase {
        case .idle: hasNotch ? CGSize(width: notch.width - 6, height: notch.height - 2) : CGSize(width: 160, height: 0)
        case .toast: CGSize(width: (hasNotch ? notch.width : 0) + 260, height: barHeight)
        case .expanded: panelSize
        }
    }

    var radius: CGFloat {
        switch phase {
        case .idle: 8
        case .toast: barHeight / 2
        case .expanded: 24
        }
    }
}

// çentik üstündeki panel
@MainActor final class IslandController {
    let model = IslandModel()
    private var panel: NSPanel?
    private var screen: NSScreen?
    private var hideTask: Task<Void, Never>?
    private var monitorsInstalled = false

    func setup() {
        rebuild()
        guard !monitorsInstalled else { return }
        monitorsInstalled = true
        _ = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            MainActor.assumeIsolated { AppController.shared.island.track() }
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in
            MainActor.assumeIsolated { AppController.shared.island.track() }
            return e
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppController.shared.island.rebuild() }
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
        guard let s = screen, let panel else { return }
        let p = NSEvent.mouseLocation
        if model.phase == .expanded {
            if !panel.frame.insetBy(dx: -12, dy: -12).contains(p) { collapse() }
        } else {
            let w = model.hasNotch ? model.notch.width : 200
            let h = model.hasNotch ? model.notch.height : 4
            if NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h + 1).contains(p) { expand() }
        }
    }

    func expand() {
        hideTask?.cancel()
        model.phase = .expanded
        panel?.ignoresMouseEvents = false
    }

    func collapse() {
        model.phase = .idle
        panel?.ignoresMouseEvents = true
    }

    func toast(icon: String, text: String, tint: Color) {
        guard panel != nil else { return }
        model.icon = icon
        model.text = text
        model.tint = tint
        guard model.phase != .expanded else { return }
        model.phase = .toast
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
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
