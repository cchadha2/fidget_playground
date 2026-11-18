import SwiftUI
import UIKit
import QuartzCore

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Palette {
    static let bg = Color(hex: 0x17142E)
    static let tray = Color(hex: 0x221E42)
    static let trayHi = Color(hex: 0x2D2856)
    static let edge = Color.white.opacity(0.08)
    static let text = Color(hex: 0xF4F0FF)
    static let muted = Color(hex: 0xA59FCB)
    static let tangerine = Color(hex: 0xFF7B3A)
    static let mint = Color(hex: 0x35DFB0)
    static let lilac = Color(hex: 0xA88CFF)
    static let sun = Color(hex: 0xFFCF3F)
    static let rose = Color(hex: 0xFF5C8D)
    static let sky = Color(hex: 0x4CB3FF)

    static func metal(_ radius: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [Color(hex: 0xF6F4FF), Color(hex: 0xB3AECB), Color(hex: 0x6E6990)],
            center: UnitPoint(x: 0.35, y: 0.3),
            startRadius: 0,
            endRadius: radius * 1.4
        )
    }
}

/// Calls `tick(dt)` every screen refresh (up to 120Hz on ProMotion).
final class DisplayLink: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private let tick: (Double) -> Void

    init(_ tick: @escaping (Double) -> Void) {
        self.tick = tick
    }

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        last = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ l: CADisplayLink) {
        let now = l.targetTimestamp
        let dt = last == 0 ? 1.0 / 60.0 : min(0.05, now - last)
        last = now
        tick(dt)
    }
}

func wrapDeg(_ d: Double) -> Double {
    var d = d
    while d > 180 { d -= 360 }
    while d < -180 { d += 360 }
    return d
}

/// Angle in degrees of `p` around the centre of a box of `size`.
func angleDeg(_ p: CGPoint, in size: CGSize) -> Double {
    atan2(Double(p.y - size.height / 2), Double(p.x - size.width / 2)) * 180 / .pi
}

struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.muted)
        }
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    var color: Color = Palette.tangerine
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(selected ? Palette.trayHi : Color.clear))
                .overlay(Capsule().stroke(selected ? color : Palette.edge, lineWidth: 1.5))
                .foregroundStyle(selected ? Palette.text : Palette.muted)
        }
        .buttonStyle(.plain)
    }
}

struct BigButtonStyle: ButtonStyle {
    var color: Color = Palette.sun

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hex: 0x2A1D00))
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(color))
            .offset(y: configuration.isPressed ? 5 : 0)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(color)
                    .brightness(-0.3)
                    .offset(y: 6)
            )
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}
