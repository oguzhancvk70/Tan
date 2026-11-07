import SwiftUI

// çevrimiçi galeri (Wallhaven + Bing)
struct GalleryView: View {
    enum Src: String, CaseIterable { case wallhaven = "Wallhaven", bing = "Bing Günün Görseli" }

    @State private var src: Src = .wallhaven
    @State private var query = ""
    @State private var sort: WallhavenSort = .toplist
    @State private var items: [OnlineWallpaper] = []
    @State private var page = 1
    @State private var lastPage = 1
    @State private var loading = false
    @State private var error: String?
    @State private var busyID: String?
    @State private var doneID: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("", selection: $src) { ForEach(Src.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                Spacer()
                if src == .wallhaven {
                    TextField("Ara (ör. mountain, city, minimal)", text: $query)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                        .onSubmit { Task { await load(reset: true) } }
                    Picker("", selection: $sort) { ForEach(WallhavenSort.allCases) { Text($0.title).tag($0) } }
                        .labelsHidden().frame(width: 150)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    ForEach(items) { w in
                        OnlineCell(w: w, busy: busyID == w.id, done: doneID == w.id) { modes in set(w, modes) }
                    }
                }
                if loading {
                    ProgressView().padding()
                } else if src == .wallhaven && page < lastPage && !items.isEmpty {
                    Button("Daha Fazla") { Task { await load(reset: false) } }.padding()
                }
            }
            Text("Üzerine gelince: ☀︎ açık mod · ☾ koyu mod · ◐ ikisi. Görseller kişisel kullanım içindir.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: src) { await load(reset: true) }
        .onChange(of: sort) { Task { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        if reset { page = 1; items = [] } else { page += 1 }
        loading = true
        error = nil
        defer { loading = false }
        do {
            switch src {
            case .wallhaven:
                let r = try await Wallhaven.search(query: query, sort: sort, page: page, anime: Preferences.shared.includeAnime)
                items += r.items
                lastPage = r.lastPage
            case .bing:
                items = try await Bing.latest(count: 8)
                lastPage = 1
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func set(_ w: OnlineWallpaper, _ modes: [Mode]) {
        busyID = w.id
        Task {
            do {
                try await AppController.shared.setOnline(w, for: modes)
                doneID = w.id
            } catch {
                self.error = error.localizedDescription
            }
            busyID = nil
        }
    }
}

struct OnlineCell: View {
    let w: OnlineWallpaper
    let busy: Bool
    let done: Bool
    let onSet: ([Mode]) -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(.quaternary)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    AsyncImage(url: w.thumb) { $0.resizable().scaledToFill() } placeholder: { ProgressView().controlSize(.small) }
                }
                .overlay(alignment: .bottom) {
                    if busy || hover {
                        HStack(spacing: 4) {
                            if busy {
                                ProgressView().controlSize(.small).padding(.horizontal, 20)
                            } else {
                                btn("sun.max.fill", [.light], "Açık mod için ayarla")
                                btn("moon.fill", [.dark], "Koyu mod için ayarla")
                                btn("circle.lefthalf.filled", [.light, .dark], "İkisi için ayarla")
                            }
                        }
                        .padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(6) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onHover { hover = $0 }
            HStack {
                Text(w.source == .bing ? w.title : "\(w.title) · \(w.credit)").font(.caption).lineLimit(1)
                Spacer()
                if let p = w.page {
                    Link(destination: p) { Image(systemName: "arrow.up.right.square") }.font(.caption).help("Kaynağı aç")
                }
            }
        }
    }

    private func btn(_ icon: String, _ modes: [Mode], _ help: LocalizedStringKey) -> some View {
        Button { onSet(modes) } label: { Image(systemName: icon).frame(width: 28, height: 22) }
            .buttonStyle(.borderless)
            .help(help)
    }
}
