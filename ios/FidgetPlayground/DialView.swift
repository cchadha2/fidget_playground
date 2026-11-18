import SwiftUI

struct DialView: View {
    @State private var raw: Double = -135
    @State private var step = 0
    @State private var dragging = false
    @State private var prevA: Double = 0
    @State private var atEdge = true

    private let minA = -135.0
    private let maxA = 135.0
    private let steps = 30
    private let side: CGFloat = 300
    private var stepA: Double { (maxA - minA) / Double(steps) }

    var body: some View {
        VStack(spacing: 20) {
            Stat(value: "\(step)", label: "of 30")
            Spacer(minLength: 0)
            ZStack {
                ForEach(0...steps, id: \.self) { i in
                    tickMark(i)
                }
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: side - 70, height: side - 70)
                    .offset(y: 14)
                    .blur(radius: 12)
                knob
                    .frame(width: side - 70, height: side - 70)
                    .rotationEffect(.degrees(minA + Double(step) * stepA))
                    .animation(.spring(response: 0.12, dampingFraction: 0.55), value: step)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let a = angleDeg(v.location, in: CGSize(width: side, height: side))
                        if !dragging {
                            dragging = true
                            prevA = a
                            return
                        }
                        setRaw(raw + wrapDeg(a - prevA))
                        prevA = a
                    }
                    .onEnded { _ in
                        dragging = false
                        raw = minA + Double(step) * stepA
                    }
            )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
    }

    private func tickMark(_ i: Int) -> some View {
        let major = i % 5 == 0
        let lit = step > 0 && i <= step
        return Capsule()
            .fill(lit ? Palette.lilac : Color.white.opacity(major ? 0.22 : 0.1))
            .frame(width: major ? 4 : 3, height: major ? 16 : 10)
            .offset(y: -side / 2 + 14)
            .rotationEffect(.degrees(minA + Double(i) * stepA))
    }

    private var knob: some View {
        ZStack {
            Circle().fill(
                RadialGradient(colors: [Color(hex: 0x4A4380), Color(hex: 0x2A2550)],
                               center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 150)
            )
            Circle()
                .strokeBorder(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 10, dash: [3, 5]))
            Circle()
                .fill(
                    RadialGradient(colors: [Color(hex: 0x3A3468), Color(hex: 0x221E42)],
                                   center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 80)
                )
                .padding(52)
            VStack {
                Capsule()
                    .fill(Palette.lilac)
                    .frame(width: 8, height: 28)
                    .shadow(color: Palette.lilac, radius: 6)
                Spacer()
            }
            .padding(.top, 12)
        }
    }

    private func setRaw(_ v: Double) {
        raw = min(maxA, max(minA, v))
        let edge = raw == minA || raw == maxA
        let s = Int(((raw - minA) / stepA).rounded())
        if s != step {
            step = s
            Haptics.shared.tick(0.55 + Float(s) / 70, 1)
            Sound.shared.tick(0.6 + Double(s) / Double(steps) * 0.9)
        }
        if edge && !atEdge {
            Haptics.shared.thud()
            Sound.shared.thunk(raw == maxA ? 1.3 : 0.9)
        }
        atEdge = edge
    }
}
