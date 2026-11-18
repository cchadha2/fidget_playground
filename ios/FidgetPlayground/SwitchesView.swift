import SwiftUI

struct SwitchesView: View {
    @State private var on = [false, false, false, false]
    @State private var party = false
    private let colors = [Palette.mint, Palette.sun, Palette.rose, Palette.sky]

    var body: some View {
        VStack(spacing: 24) {
            Stat(value: "\(on.filter { $0 }.count)", label: "of 4 on")
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                ForEach(0..<4, id: \.self) { i in
                    VStack(spacing: 22) {
                        toggle(i)
                        Capsule()
                            .fill(on[i] ? colors[i] : Color.black.opacity(0.35))
                            .frame(width: 64, height: 10)
                            .shadow(color: on[i] ? colors[i] : Color.clear, radius: 8)
                            .scaleEffect(x: 1, y: party ? 1.8 : 1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
    }

    private func toggle(_ i: Int) -> some View {
        ZStack(alignment: on[i] ? .top : .bottom) {
            Capsule()
                .fill(on[i] ? colors[i].opacity(0.75) : Color.black.opacity(0.32))
                .frame(width: 64, height: 124)
            Capsule()
                .fill(Palette.metal(30))
                .frame(width: 52, height: 56)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                .padding(6)
        }
        .frame(width: 64, height: 124)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0).onEnded { v in
                if abs(v.translation.height) > 12 {
                    let want = v.translation.height < 0
                    if want != on[i] { flip(i) }
                } else {
                    flip(i)
                }
            }
        )
    }

    private func flip(_ i: Int) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { on[i].toggle() }
        Sound.shared.toggle(on: on[i])
        Haptics.shared.tap(on[i] ? 0.95 : 0.7, on[i] ? 0.6 : 0.3)
        guard on.allSatisfy({ $0 }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            Sound.shared.chime([523.25, 659.25, 783.99, 1046.5])
            Haptics.shared.success()
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) { party = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { party = false }
            }
        }
    }
}
