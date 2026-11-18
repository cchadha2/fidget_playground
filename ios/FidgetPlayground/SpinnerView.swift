import SwiftUI
import QuartzCore

final class SpinnerModel: ObservableObject {
    @Published var angle: Double = 0
    @Published var rpm = 0
    @Published var best = UserDefaults.standard.integer(forKey: "bestRpm")
    @Published var showHint = true

    private var vel: Double = 0          // degrees per second
    private var dragging = false
    private var prevA: Double = 0
    private var prevT: CFTimeInterval = 0
    private var sector = 0
    private var link: DisplayLink?

    func appear() {
        link = DisplayLink { [weak self] dt in self?.step(dt) }
        link?.start()
    }

    func disappear() {
        link?.stop()
        link = nil
        Haptics.shared.setRumble(0)
        Sound.shared.setWhir(0)
    }

    private func step(_ dt: Double) {
        if !dragging && vel != 0 {
            angle += vel * dt
            let k = 0.42 * (1 + 2 / (1 + abs(vel) / 250))
            vel *= exp(-k * dt)
            if abs(vel) < 3 { vel = 0 }
        }
        // One click each time an arm passes the top.
        let s = Int(floor(angle / 120))
        if s != sector {
            sector = s
            Haptics.shared.tick(Float(min(1, 0.4 + abs(vel) / 3000)), 0.85)
            Sound.shared.tick(1 + min(abs(vel) / 6000, 0.5))
        }
        let r = Int((abs(vel) / 360 * 60).rounded())
        if r != rpm { rpm = r }
        if !dragging && r > best {
            best = r
            UserDefaults.standard.set(r, forKey: "bestRpm")
        }
        let speed = dragging ? 0 : abs(vel) / 1000
        Haptics.shared.setRumble(Float(min(1, speed / 5)) * 0.55)
        Sound.shared.setWhir(Float(speed))
    }

    func drag(to p: CGPoint, in size: CGSize) {
        let a = angleDeg(p, in: size)
        let now = CACurrentMediaTime()
        if !dragging {
            dragging = true
            if abs(vel) > 150 {
                Haptics.shared.thud()
                Sound.shared.thunk(1.8)
            }
            vel = 0
            prevA = a
            prevT = now
            if showHint { showHint = false }
            return
        }
        let d = wrapDeg(a - prevA)
        let dt = max(0.001, now - prevT)
        angle += d
        vel = vel * 0.4 + (d / dt) * 0.6
        prevA = a
        prevT = now
    }

    func release() {
        dragging = false
        if CACurrentMediaTime() - prevT > 0.09 { vel = 0 }
        vel = max(-9000, min(9000, vel))
    }
}

struct SpinnerView: View {
    @StateObject private var m = SpinnerModel()
    private let box: CGFloat = 320

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 48) {
                Stat(value: "\(m.rpm)", label: "rpm")
                Stat(value: "\(m.best)", label: "best")
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 250, height: 250)
                    .offset(y: 16)
                    .blur(radius: 14)
                SpinnerArt()
                    .frame(width: 280, height: 280)
                    .rotationEffect(.degrees(m.angle))
            }
            .frame(width: box, height: box)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in m.drag(to: v.location, in: CGSize(width: box, height: box)) }
                    .onEnded { _ in m.release() }
            )
            Spacer(minLength: 0)
            Text("Drag in a circle and let go")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .opacity(m.showHint ? 1 : 0)
        }
        .padding(.vertical, 24)
        .onAppear { m.appear() }
        .onDisappear { m.disappear() }
    }
}

struct SpinnerArt: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 220
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func pt(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: c.x + x * s, y: c.y + y * s)
            }
            func circle(_ p: CGPoint, _ r: Double) -> Path {
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
            func metal(_ p: CGPoint, _ r: Double) -> GraphicsContext.Shading {
                .radialGradient(
                    Gradient(colors: [Color(hex: 0xF6F4FF), Color(hex: 0xB3AECB), Color(hex: 0x6E6990)]),
                    center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.4),
                    startRadius: 0,
                    endRadius: r * 1.5
                )
            }
            let lobes = [pt(0, -66), pt(57.2, 33), pt(-57.2, 33)]
            let body = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(hex: 0xFF9AB8), Color(hex: 0xE2386C)]),
                startPoint: pt(-60, -100),
                endPoint: pt(60, 100)
            )
            var tri = Path()
            tri.move(to: lobes[0])
            tri.addLine(to: lobes[1])
            tri.addLine(to: lobes[2])
            tri.closeSubpath()
            ctx.fill(tri, with: body)
            ctx.stroke(tri, with: body, style: StrokeStyle(lineWidth: 56 * s, lineJoin: .round))
            for p in lobes { ctx.fill(circle(p, 38 * s), with: body) }
            for p in lobes {
                ctx.fill(circle(p, 25 * s), with: metal(p, 25 * s))
                ctx.fill(circle(p, 9 * s), with: .color(Color(hex: 0x5A557A)))
            }
            ctx.fill(circle(c, 30 * s), with: metal(c, 30 * s))
            ctx.fill(circle(c, 18 * s), with: .color(Palette.sun))
            ctx.fill(circle(pt(-5, -6), 5 * s), with: .color(Color(hex: 0xFFF6CC)))
        }
        .drawingGroup()
    }
}
