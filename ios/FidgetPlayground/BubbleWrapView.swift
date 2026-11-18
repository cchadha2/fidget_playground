import SwiftUI

private struct BubbleLayout {
    let cols: Int
    let rows: Int
    let size: CGSize
    let gap: CGFloat = 10

    var cell: CGFloat {
        let w = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let h = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return max(10, min(w, h))
    }
    var originX: CGFloat { (size.width - (cell * CGFloat(cols) + gap * CGFloat(cols - 1))) / 2 }
    var originY: CGFloat { (size.height - (cell * CGFloat(rows) + gap * CGFloat(rows - 1))) / 2 }

    func center(_ i: Int) -> CGPoint {
        CGPoint(
            x: originX + CGFloat(i % cols) * (cell + gap) + cell / 2,
            y: originY + CGFloat(i / cols) * (cell + gap) + cell / 2
        )
    }

    func index(at p: CGPoint) -> Int? {
        let c = Int(floor((p.x - originX) / (cell + gap)))
        let r = Int(floor((p.y - originY) / (cell + gap)))
        guard c >= 0, r >= 0, c < cols, r < rows else { return nil }
        let i = r * cols + c
        let ctr = center(i)
        guard hypot(p.x - ctr.x, p.y - ctr.y) < cell * 0.55 else { return nil }
        return i
    }
}

struct BubbleWrapView: View {
    private let cols = 5
    private let rows = 6
    @State private var popped = Array(repeating: false, count: 30)
    @State private var refilling = false
    @AppStorage("pops") private var pops = 0
    @AppStorage("sheets") private var sheets = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 48) {
                Stat(value: "\(pops)", label: "popped")
                Stat(value: "\(sheets)", label: "sheets")
            }
            GeometryReader { geo in
                let layout = BubbleLayout(cols: cols, rows: rows, size: geo.size)
                ZStack {
                    ForEach(0..<(cols * rows), id: \.self) { i in
                        Bubble(popped: popped[i])
                            .frame(width: layout.cell, height: layout.cell)
                            .position(layout.center(i))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { v in
                        if let i = layout.index(at: v.location) { pop(i) }
                    }
                )
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 26).fill(Palette.sky.opacity(0.14)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func pop(_ i: Int) {
        guard !popped[i], !refilling else { return }
        popped[i] = true
        Sound.shared.pop()
        Haptics.shared.pop(Float.random(in: 0.3...0.8))
        pops += 1
        if popped.allSatisfy({ $0 }) {
            refilling = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { refill() }
        }
    }

    private func refill() {
        sheets += 1
        Sound.shared.whoosh()
        Haptics.shared.success()
        for i in 0..<popped.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.018) {
                popped[i] = false
                if i % 3 == 0 { Haptics.shared.tick(0.3, 0.6) }
                if i == popped.count - 1 { refilling = false }
            }
        }
    }
}

struct Bubble: View {
    let popped: Bool

    var body: some View {
        ZStack {
            Circle().fill(
                RadialGradient(colors: [Palette.sky.opacity(0.7), Palette.sky.opacity(0.25)],
                               center: UnitPoint(x: 0.6, y: 0.7), startRadius: 0, endRadius: 40)
            )
            if popped {
                Path { p in
                    p.move(to: CGPoint(x: 0.3, y: 0.35))
                    p.addLine(to: CGPoint(x: 0.7, y: 0.6))
                    p.move(to: CGPoint(x: 0.35, y: 0.7))
                    p.addLine(to: CGPoint(x: 0.6, y: 0.3))
                }
                .applying(CGAffineTransform(scaleX: 60, y: 60))
                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                .frame(width: 60, height: 60)
                .scaleEffect(0.8)
            } else {
                Circle().fill(
                    RadialGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.3), Color.clear],
                                   center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 22)
                )
            }
        }
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(popped ? 0 : 0.25), radius: 3, y: 3)
        .scaleEffect(popped ? 0.82 : 1)
        .opacity(popped ? 0.4 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.45), value: popped)
    }
}
