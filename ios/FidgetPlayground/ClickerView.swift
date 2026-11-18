import SwiftUI

struct ClickerView: View {
    @AppStorage("clicks") private var count = 0
    @AppStorage("keyType") private var typeRaw = KeyType.clicky.rawValue
    @State private var down = false

    private var type: KeyType { KeyType(rawValue: typeRaw) ?? .clicky }

    private func color(_ t: KeyType) -> Color {
        switch t {
        case .clicky: Palette.sky
        case .tactile: Palette.tangerine
        case .thocky: Palette.lilac
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Stat(value: "\(count)", label: "presses")
            Spacer(minLength: 0)
            key
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(KeyType.allCases, id: \.self) { t in
                    Chip(title: t.rawValue.capitalized, selected: t == type, color: color(t)) {
                        typeRaw = t.rawValue
                        Sound.shared.key(t, down: true)
                        Haptics.shared.light()
                    }
                }
            }
        }
        .padding(.vertical, 24)
    }

    private var key: some View {
        let c = color(type)
        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 236, height: 236)
                .offset(y: 20)
                .blur(radius: 8)
            Circle()
                .fill(c)
                .overlay(Circle().fill(Color.black.opacity(0.45)))
                .frame(width: 200, height: 200)
                .offset(y: 14)
            ZStack {
                Circle().fill(c)
                Circle().fill(
                    RadialGradient(colors: [Color.white.opacity(0.45), Color.clear],
                                   center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 100)
                )
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 2))
                    .frame(width: 100, height: 100)
            }
            .frame(width: 200, height: 200)
            .offset(y: down ? 12 : 0)
            .animation(down ? nil : .spring(response: 0.18, dampingFraction: 0.5), value: down)
        }
        .frame(width: 260, height: 260)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { press() } }
                .onEnded { _ in release() }
        )
    }

    private func press() {
        down = true
        Sound.shared.key(type, down: true)
        switch type {
        case .clicky: Haptics.shared.tap(1, 1)
        case .tactile: Haptics.shared.tap(0.85, 0.35)
        case .thocky: Haptics.shared.thud()
        }
    }

    private func release() {
        guard down else { return }
        down = false
        Sound.shared.key(type, down: false)
        switch type {
        case .clicky: Haptics.shared.tap(0.5, 0.9)
        case .tactile: Haptics.shared.tap(0.35, 0.3)
        case .thocky: Haptics.shared.tap(0.4, 0.1)
        }
        withAnimation(.snappy(duration: 0.15)) { count += 1 }
    }
}
