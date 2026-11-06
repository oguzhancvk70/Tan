import SwiftUI

struct IslandView: View {
    let model: IslandModel

    var body: some View {
        let s = model.shapeSize
        ZStack(alignment: .top) {
            Color.black
            if model.phase == .toast { toast.transition(.opacity) }
            if model.phase == .expanded { expanded.transition(.opacity) }
        }
        .frame(width: s.width, height: s.height)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: model.radius, bottomTrailingRadius: model.radius, style: .continuous))
        .shadow(color: .black.opacity(model.phase == .expanded ? 0.35 : 0), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.phase)
        .environment(\.colorScheme, .dark)
    }

    // kısa bildirim
    private var toast: some View {
        HStack(spacing: 8) {
            Image(systemName: model.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(model.tint)
                .contentTransition(.symbolEffect(.replace))
            if model.hasNotch { Spacer(minLength: model.notch.width) }
            Text(model.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: model.barHeight)
    }

    // genişlemiş ada
    private var expanded: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.barHeight)
            HStack(spacing: 14) {
                Color.white.opacity(0.08)
                    .overlay {
                        if let t = model.thumb { Image(nsImage: t).resizable().scaledToFill() }
                    }
                    .frame(width: 128, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isDark ? "Karanlık Mod" : "Açık Mod").font(.system(size: 15, weight: .semibold))
                    Text(model.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                IslandButton(icon: model.isDark ? "sun.max.fill" : "moon.fill", help: "Modu değiştir") {
                    AppController.shared.toggle()
                }
                IslandButton(icon: "shuffle", help: "Rastgele duvar kâğıdı") {
                    AppController.shared.shuffle()
                }
                IslandButton(icon: "gearshape.fill", help: "Ayarlar") {
                    AppController.shared.island.collapse()
                    SettingsWindow.shared.show()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .foregroundStyle(.white)
    }
}

struct IslandButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(hover ? 0.22 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
