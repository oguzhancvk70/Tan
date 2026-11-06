import SwiftUI

struct ClaudeChatView: View {
    @Bindable var chat: ClaudeChat
    @Bindable var prefs = Preferences.shared
    let topInset: CGFloat
    let notchWidth: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // çentik satırı
            HStack(spacing: 0) {
                Label("Claude", systemImage: "sparkle").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                Spacer(minLength: notchWidth + 8)
                HStack(spacing: 4) {
                    iconButton(chat.pinned ? "pin.fill" : "pin", chat.pinned ? "Sabitlemeyi kaldır" : "Açık tut") { chat.pinned.toggle() }
                    iconButton("square.and.pencil", "Yeni sohbet") { chat.newChat() }
                    iconButton("xmark", "Kapat") { ClaudePanelController.shared.hide() }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: max(topInset, 30))

            HStack(spacing: 8) {
                Menu {
                    Button("Klasör Seç…") { ClaudePanelController.shared.pickFolder() }
                    Button("Ana Klasör") { prefs.claudeFolder = NSHomeDirectory() }
                } label: {
                    Label((prefs.claudeFolder as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Toggle("Dosya düzenleyebilir", isOn: $prefs.claudeEdits).toggleStyle(.switch).controlSize(.mini)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.messages.isEmpty { emptyState }
                        ForEach(chat.messages) { ChatBubble(message: $0) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .onChange(of: chat.scrollTick) { proxy.scrollTo("end", anchor: .bottom) }
            }

            inputBar
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
        .onChange(of: chat.focusTick) { focused = true }
        .onExitCommand { ClaudePanelController.shared.hide() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merhaba! Ne yapalım?").font(.system(size: 16, weight: .semibold))
            Text("Claude bu sohbette seçili klasörde çalışır. Panodaki metni ya da Raf'taki dosyaları aşağıdaki butonlarla ekleyebilirsin. Enter gönderir, ⌥Enter yeni satır, Esc kapatır.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !chat.files.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text("\(chat.files.count) dosya eklendi")
                    Button { chat.files = [] } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Claude'a sor…", text: $chat.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.option) || press.modifiers.contains(.shift) { return .ignored }
                        chat.send()
                        return .handled
                    }
                iconButton("doc.on.clipboard", "Panodaki metni ekle") {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        chat.input += (chat.input.isEmpty ? "" : "\n") + s
                    }
                }
                iconButton("tray.and.arrow.up", "Raf'taki dosyaları ekle") { chat.files = AppController.shared.island.model.shelf }
                if chat.running {
                    iconButton("stop.fill", "Durdur") { chat.stop() }
                } else {
                    Button { chat.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(chat.input.isEmpty ? Color.white.opacity(0.15) : Color.orange))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private func iconButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

struct ChatBubble: View {
    let message: ClaudeChat.Message
    @State private var hover = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text).font(.system(size: 13)).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14)))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if !message.tools.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.tools.suffix(6), id: \.self) { t in
                            Text(t).font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.orange.opacity(0.2)))
                        }
                    }
                }
                if message.text.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Düşünüyor…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else {
                    Text(Self.markdown(message.text)).font(.system(size: 13)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hover && !message.text.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Kopyala")
                }
            }
            .onHover { hover = $0 }
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
        }
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
