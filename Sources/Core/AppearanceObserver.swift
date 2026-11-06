import AppKit

// görünüm + ekran/Space/uyanma olayları
@MainActor final class AppearanceObserver {
    private var kvo: NSKeyValueObservation?
    private var tokens: [NSObjectProtocol] = []

    init(onAppearance: @escaping @MainActor () -> Void, onEnvironment: @escaping @MainActor () -> Void) {
        kvo = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in onAppearance() }
        }

        tokens.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                onAppearance()
            }
        })

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in onAppearance(); onEnvironment() }
            })
        }

        tokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in onEnvironment() }
        })
    }
}
