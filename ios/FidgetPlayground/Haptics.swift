import CoreHaptics
import UIKit
import QuartzCore

/// Core Haptics wrapper: crisp transients plus a continuous "rumble" whose strength can be changed live.
final class Haptics {
    static let shared = Haptics()

    var enabled = true {
        didSet { if !enabled { setRumble(0) } }
    }

    private var engine: CHHapticEngine?
    private var rumble: CHHapticAdvancedPatternPlayer?
    private var rumbleLevel: Float = 0
    private var lastTick: CFTimeInterval = 0
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {
        makeEngine()
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            try? self?.engine?.start()
        }
    }

    private func makeEngine() {
        guard supported else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = false
            e.playsHapticsOnly = true
            e.resetHandler = { [weak self] in
                DispatchQueue.main.async {
                    self?.rumble = nil
                    self?.rumbleLevel = 0
                    try? self?.engine?.start()
                }
            }
            e.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rumble = nil
                    self?.rumbleLevel = 0
                }
            }
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }

    // MARK: Building blocks

    private func transient(_ t: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: t
        )
    }

    private func continuous(_ t: TimeInterval, _ duration: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: t,
            duration: duration
        )
    }

    private func play(_ events: [CHHapticEvent]) {
        guard enabled, let engine else { return }
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            try? engine.start()
        }
    }

    // MARK: Vocabulary

    func tap(_ intensity: Float, _ sharpness: Float) {
        play([transient(0, intensity, sharpness)])
    }

    /// Rate-limited detent tick, safe to call every frame.
    func tick(_ intensity: Float = 0.5, _ sharpness: Float = 0.9) {
        let now = CACurrentMediaTime()
        guard now - lastTick > 0.018 else { return }
        lastTick = now
        tap(intensity, sharpness)
    }

    func light() { tap(0.45, 0.6) }
    func medium() { tap(0.75, 0.5) }
    func heavy() { tap(1, 0.25) }

    func thud() {
        play([transient(0, 1, 0.05), continuous(0, 0.06, 0.6, 0)])
    }

    func pop(_ sharpness: Float) {
        play([transient(0, 0.95, sharpness), continuous(0, 0.035, 0.45, 0.2)])
    }

    func success() {
        play([transient(0, 0.6, 0.5), transient(0.09, 0.8, 0.7), transient(0.18, 1, 1)])
    }

    func error() {
        play([continuous(0, 0.18, 1, 0.1), continuous(0.24, 0.32, 1, 0.05)])
    }

    /// Continuous vibration, 0...1. Call with 0 to stop.
    func setRumble(_ level: Float, sharpness: Float = 0.2) {
        guard let engine else { return }
        let lvl = enabled ? max(0, min(1, level)) : 0
        if lvl < 0.02 {
            if let r = rumble {
                try? r.stop(atTime: CHHapticTimeImmediate)
                rumble = nil
            }
            rumbleLevel = 0
            return
        }
        if rumble != nil && abs(lvl - rumbleLevel) < 0.02 { return }
        do {
            if rumble == nil {
                let pattern = try CHHapticPattern(events: [continuous(0, 30, 1, 0.5)], parameters: [])
                let p = try engine.makeAdvancedPlayer(with: pattern)
                p.loopEnabled = true
                try p.start(atTime: CHHapticTimeImmediate)
                rumble = p
            }
            try rumble?.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: lvl, relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness - 0.5, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
            rumbleLevel = lvl
        } catch {
            rumble = nil
        }
    }
}
