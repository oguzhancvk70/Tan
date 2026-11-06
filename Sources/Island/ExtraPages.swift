import SwiftUI

// pano geçmişi sayfası
struct ClipboardPage: View {
    private var cb: ClipboardService { AppController.shared.clipboard }

    var body: some View {
        if cb.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Kopyaladıkların burada birikir").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(cb.items) { ClipRow(item: $0) }
                    }
                }
                IslandButton(icon: "trash", help: "Geçmişi temizle") { cb.clear() }
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipboardService.Item
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        Button {
            AppController.shared.clipboard.copy(item)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let img = item.image {
                        Image(nsImage: img).resizable().scaledToFill()
                    } else if let f = item.files.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: f.path)).resizable()
                    } else {
                        Image(systemName: "text.alignleft").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(item.preview).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Text(copied ? "Kopyalandı" : item.date.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 10)).foregroundStyle(copied ? .green : .secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hover ? 0.12 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// sistem durumu sayfası
struct SystemPage: View {
    private var s: SystemStats { AppController.shared.stats }

    var body: some View {
        HStack(spacing: 14) {
            Gauge(title: "CPU", value: s.cpu, label: "%\(Int(s.cpu * 100))", tint: .blue)
            Gauge(title: "RAM", value: s.memTotal > 0 ? s.memUsed / s.memTotal : 0,
                  label: bytes(s.memUsed, .memory), tint: .purple)
            Gauge(title: "Disk", value: s.diskTotal > 0 ? 1 - s.diskFree / s.diskTotal : 0,
                  label: "\(bytes(s.diskFree, .file)) boş", tint: .orange)
            VStack(alignment: .leading, spacing: 8) {
                Text("Ağ").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Label(bytes(s.down, .file) + "/s", systemImage: "arrow.down").font(.system(size: 12, weight: .medium)).monospacedDigit()
                Label(bytes(s.up, .file) + "/s", systemImage: "arrow.up").font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
            .frame(width: 110, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { AppController.shared.stats.start() }
        .onDisappear { AppController.shared.stats.stop() }
    }

    private func bytes(_ v: Double, _ style: ByteCountFormatter.CountStyle) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: style)
    }
}

private struct Gauge: View {
    let title: String
    let value: Double
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: value)
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 62, height: 62)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .frame(width: 84)
    }
}
