import SwiftUI

struct MarimbaView: View {
    @State private var current: Int?
    @State private var lastHit = -1
    @State private var hits = 0

    private static let scale = [0, 2, 4, 7, 9]
    private static let names = ["C", "D", "E", "G", "A"]
    private let count = 15

    private func freq(_ i: Int) -> Double {
        let oct = i / 5
        return 261.63 * pow(2, Double(oct * 12 + Self.scale[i % 5]) / 12)
    }

    private func name(_ i: Int) -> String {
        Self.names[i % 5] + "\(4 + i / 5)"
    }

    var body: some View {
        VStack(spacing: 20) {
            Stat(value: lastHit >= 0 ? name(lastHit) : "–", label: "note")
            GeometryReader { geo in
                let gap: CGFloat = 5
                let w = (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<count, id: \.self) { i in
                        bar(i, height: geo.size.height * (1 - CGFloat(i) / CGFloat(count) * 0.45))
                            .frame(width: w)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let i = max(0, min(count - 1, Int(v.location.x / (w + gap))))
                            strike(i)
                        }
                        .onEnded { _ in current = nil }
                )
            }
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func bar(_ i: Int, height: CGFloat) -> some View {
        let hue = 0.95 - Double(i) / Double(count) * 0.75
        let active = current == i
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 1))
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: 8, height: 8)
                .padding(.top, 14)
        }
        .frame(height: height)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 4)
        .scaleEffect(active ? 0.94 : 1)
        .brightness(active ? 0.15 : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.45), value: active)
    }

    private func strike(_ i: Int) {
        guard i != current else { return }
        if let c = current {
            // Play every bar we passed so fast swipes don't skip notes.
            let dir = i > c ? 1 : -1
            var k = c + dir
            while k != i {
                Sound.shared.pluck(freq(k))
                k += dir
            }
        }
        current = i
        lastHit = i
        Sound.shared.pluck(freq(i))
        Haptics.shared.tap(0.6, 0.75)
    }
}
