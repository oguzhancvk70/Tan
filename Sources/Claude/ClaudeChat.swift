import AppKit
import SwiftUI

// Claude Code CLI ile sohbet (kullanıcının aboneliği)
@MainActor @Observable final class ClaudeChat {
    enum Role { case user, assistant, error }
    struct Message: Identifiable {
        let id = UUID()
        var role: Role
        var text: String
        var tools: [String] = []
    }

    var messages: [Message] = []
    var input = ""
    var running = false
    var files: [URL] = []
    var pinned = false
    var scrollTick = 0
    var focusTick = 0

    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var errText = ""
    @ObservationIgnored private var current: UUID?

    var folder: URL { URL(fileURLWithPath: Preferences.shared.claudeFolder) }

    static func binary() -> URL? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        for p in ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.local/bin/claude", "\(home)/.claude/local/claude"]
            where fm.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        let ext = "\(home)/.vscode/extensions"
        let dirs = ((try? fm.contentsOfDirectory(atPath: ext)) ?? [])
            .filter { $0.hasPrefix("anthropic.claude-code-") }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for d in dirs {
            let p = "\(ext)/\(d)/resources/native-binary/claude"
            if fm.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }
        guard let bin = Self.binary() else {
            messages.append(Message(role: .error, text: "Claude Code bulunamadı. VS Code'da Claude Code eklentisi kurulu olmalı."))
            return
        }
        input = ""

        var prompt = text
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        if !files.isEmpty {
            prompt += "\n\nEkli dosyalar:\n" + files.map { "- \($0.path)" }.joined(separator: "\n")
            for d in Set(files.map { $0.deletingLastPathComponent().path }) { args += ["--add-dir", d] }
        }
        if let sessionID { args += ["--resume", sessionID] }
        if Preferences.shared.claudeEdits { args += ["--permission-mode", "acceptEdits"] }

        messages.append(Message(role: .user, text: files.isEmpty ? text : "\(text)\n📎 \(files.count) dosya"))
        files = []
        let reply = Message(role: .assistant, text: "")
        messages.append(reply)
        current = reply.id
        running = true
        errText = ""
        buffer = Data()
        scrollTick += 1

        let p = Process()
        p.executableURL = bin
        p.arguments = args
        p.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { MainActor.assumeIsolated { ClaudePanelController.shared.chat.consume(d) } }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            let s = String(decoding: d, as: UTF8.self)
            DispatchQueue.main.async { MainActor.assumeIsolated { ClaudePanelController.shared.chat.errText += s } }
        }
        p.terminationHandler = { p in
            let code = p.terminationStatus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { ClaudePanelController.shared.chat.finished(code) }
            }
        }
        do {
            try p.run()
            process = p
            inp.fileHandleForWriting.write(Data(prompt.utf8))
            try? inp.fileHandleForWriting.close()
        } catch {
            running = false
            setError("Claude başlatılamadı: \(error.localizedDescription)")
        }
    }

    func stop() { process?.terminate() }

    func newChat() {
        stop()
        messages = []
        sessionID = nil
        files = []
        focusTick += 1
    }

    // akış
    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            if let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { handle(o) }
        }
    }

    private func handle(_ o: [String: Any]) {
        if let sid = o["session_id"] as? String { sessionID = sid }
        switch o["type"] as? String {
        case "stream_event":
            guard let e = o["event"] as? [String: Any] else { return }
            switch e["type"] as? String {
            case "message_start":
                if let i = index(), !messages[i].text.isEmpty, !messages[i].text.hasSuffix("\n\n") { append("\n\n") }
            case "content_block_start":
                if let b = e["content_block"] as? [String: Any], b["type"] as? String == "tool_use",
                   let n = b["name"] as? String, let i = index(), !messages[i].tools.contains(n) {
                    messages[i].tools.append(n)
                }
            case "content_block_delta":
                if let d = e["delta"] as? [String: Any], d["type"] as? String == "text_delta", let t = d["text"] as? String { append(t) }
            default: break
            }
        case "result":
            if o["is_error"] as? Bool == true {
                setError(o["result"] as? String ?? "Claude bir hata döndürdü.")
            } else if let i = index(), messages[i].text.isEmpty, let r = o["result"] as? String {
                messages[i].text = r
            }
        default: break
        }
    }

    private func finished(_ code: Int32) {
        process = nil
        running = false
        if let i = index(), messages[i].text.isEmpty {
            if code == 15 {
                setError("Durduruldu.")
            } else {
                let tail = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                setError(tail.isEmpty ? "Claude yanıt vermedi (kod \(code))." : String(tail.suffix(400)))
            }
        }
        current = nil
        scrollTick += 1
    }

    private func index() -> Int? { messages.firstIndex { $0.id == current } }

    private func append(_ t: String) {
        guard let i = index() else { return }
        messages[i].text += t
        scrollTick += 1
    }

    private func setError(_ s: String) {
        if let i = index() {
            messages[i].role = .error
            messages[i].text = s
        } else {
            messages.append(Message(role: .error, text: s))
        }
    }
}

// çentikten açılan sohbet paneli
@MainActor final class ClaudePanelController: NSObject, NSWindowDelegate {
    static let shared = ClaudePanelController()
    let chat = ClaudeChat()
    private var panel: NSPanel?
    private var picking = false

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let island = AppController.shared.island
        guard let s = island.currentScreen ?? NSScreen.main else { return }
        let size = CGSize(width: 600, height: 560)
        let frame = NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
        if panel == nil {
            let p = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.delegate = self
            let host = NSHostingView(rootView: ClaudeChatView(chat: chat, topInset: island.model.topInset, notchWidth: island.model.notchWidth))
            host.sizingOptions = []
            p.contentView = host
            panel = p
        }
        panel?.setFrame(frame, display: true)
        island.collapse()
        panel?.makeKeyAndOrderFront(nil)
        chat.focusTick += 1
    }

    func hide() { panel?.orderOut(nil) }

    func windowDidResignKey(_ notification: Notification) {
        if !chat.pinned && !picking { hide() }
    }

    func pickFolder() {
        picking = true
        defer { picking = false }
        NSApp.activate()
        let o = NSOpenPanel()
        o.canChooseDirectories = true
        o.canChooseFiles = false
        o.directoryURL = chat.folder
        if o.runModal() == .OK, let u = o.url { Preferences.shared.claudeFolder = u.path }
        panel?.makeKeyAndOrderFront(nil)
    }
}
