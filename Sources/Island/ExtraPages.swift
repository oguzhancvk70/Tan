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
                Text(copied ? L("Kopyalandı") : item.date.formatted(.relative(presentation: .numeric)))
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
    @Bindable var model: IslandModel
    private var s: SystemStats { AppController.shared.stats }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Gauge(title: "CPU", value: s.cpu, label: pct(Int(s.cpu * 100)), tint: .blue)
                Gauge(title: "RAM", value: s.memTotal > 0 ? s.memUsed / s.memTotal : 0,
                      label: bytes(s.memUsed, .memory), tint: .purple)
                Gauge(title: "Disk", value: s.diskTotal > 0 ? 1 - s.diskFree / s.diskTotal : 0,
                      label: L("\(bytes(s.diskFree, .file)) boş"), tint: .orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ağ").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Label(bytes(s.down, .file) + "/s", systemImage: "arrow.down").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Label(bytes(s.up, .file) + "/s", systemImage: "arrow.up").font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
                .frame(width: 110, alignment: .leading)
                Button { model.systemDetails.toggle() } label: {
                    Image(systemName: model.systemDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(model.systemDetails ? L("Detayları gizle") : L("Detayları göster"))
            }

            // detaylar: süreçler + hatalar
            if model.systemDetails {
                HStack(alignment: .top, spacing: 16) {
                    ProcList(title: "İşlemci", items: s.procCPU) { ($0.cpu / 100).formatted(.percent.precision(.fractionLength(1))) }
                    ProcList(title: "Bellek", items: s.procMem) { bytes($0.mem, .memory) }
                    IssueList(items: s.issues)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.systemDetails ? .top : .center)
        .onAppear {
            s.setDetailed(model.systemDetails)
            s.start()
        }
        .onDisappear {
            s.setDetailed(false)
            s.stop()
        }
        .onChange(of: model.systemDetails) { _, v in s.setDetailed(v) }
    }

    private func bytes(_ v: Double, _ style: ByteCountFormatter.CountStyle) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: style)
    }
}

private struct ProcList: View {
    let title: LocalizedStringKey
    let items: [ProcUsage]
    let value: (ProcUsage) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(items) { p in
                HStack(spacing: 6) {
                    Text(p.name).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(value(p)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IssueList: View {
    let items: [SysIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Hatalar").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(items.prefix(5)) { i in
                Button {
                    if let u = i.url { NSWorkspace.shared.open(u) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange)
                        Text(i.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(i.date.map { "\(i.detail) · \($0.formatted(.relative(presentation: .numeric)))" } ?? i.detail)
                            .lineLimit(1).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(i.url?.path ?? i.detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
