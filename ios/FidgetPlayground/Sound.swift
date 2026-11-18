import AVFoundation
import UIKit
import QuartzCore

enum KeyType: String, CaseIterable {
    case clicky, tactile, thocky
}

enum FilterType { case lowpass, highpass, bandpass }

/// RBJ biquad filter.
struct Biquad {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(_ type: FilterType, f: Double, q: Double, sr: Double) {
        configure(type, f: f, q: q, sr: sr)
    }

    mutating func configure(_ type: FilterType, f: Double, q: Double, sr: Double) {
        let w = 2 * Double.pi * min(f, sr * 0.45) / sr
        let cw = cos(w)
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        var nb0 = 0.0, nb1 = 0.0, nb2 = 0.0
        switch type {
        case .lowpass:
            nb0 = (1 - cw) / 2; nb1 = 1 - cw; nb2 = nb0
        case .highpass:
            nb0 = (1 + cw) / 2; nb1 = -(1 + cw); nb2 = nb0
        case .bandpass:
            nb0 = alpha; nb1 = 0; nb2 = -alpha
        }
        b0 = nb0 / a0; b1 = nb1 / a0; b2 = nb2 / a0
        a1 = -2 * cw / a0; a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// All sounds are synthesized into buffers once, then fired through a pool of player nodes.
final class Sound {
    static let shared = Sound()

    var enabled = true {
        didSet { if !enabled { setWhir(0) } }
    }

    private enum Wave { case sine, triangle, square, saw }

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sr: Double = 44100
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var lastTick: CFTimeInterval = 0

    // Spinner whir, rendered live. Written on main, read on the audio thread.
    private var whirTarget: Float = 0
    private var whirSpeedTarget: Float = 0
    private var whirGain: Float = 0
    private var whirSpeed: Float = 0
    private var whirPhase: Float = 0
    private var rng: UInt32 = 0x9E3779B9
    private var whirFilter = Biquad(.bandpass, f: 300, q: 1.6, sr: 44100)

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        #if targetEnvironment(simulator)
        // AVAudioEngine.mainMixerNode reliably times out its RPC to the Simulator's
        // CoreAudio bridge and aborts the process. Skip engine setup here so the app
        // is still usable for visual testing; sounds just stay silent. Real devices
        // don't go through this bridge and are unaffected.
        #else
        let session = AVAudioSession.sharedInstance()
        // Plays with the silent switch on, and mixes with your music instead of stopping it.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)

        for _ in 0..<12 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        let whir = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, abl in
            self.renderWhir(frameCount, abl)
        }
        engine.attach(whir)
        engine.connect(whir, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9

        start()
        prewarm()

        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.start()
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.start()
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.start()
        }
        #endif
    }

    private func start() {
        guard !players.isEmpty, !engine.isRunning else { return }
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {}
    }

    private func prewarm() {
        for t in KeyType.allCases {
            for v in 0..<3 {
                _ = keyBuf(t, true, v)
                _ = keyBuf(t, false, v)
            }
        }
        for v in 0..<8 { _ = popBuf(v) }
        for i in 10...32 { _ = tickBuf(Double(i) / 20) }
    }

    // MARK: Synthesis

    private func env(_ i: Int, _ n: Int, _ a: Int, _ peak: Float) -> Float {
        if i < a { return peak * Float(i) / Float(max(a, 1)) }
        let x = Float(i - a) / Float(max(n - a, 1))
        return peak * powf(0.0001, x)
    }

    private func noise(_ dur: Double, _ type: FilterType, _ freq: Double, q: Double = 1, gain: Float, attack: Double = 0.001) -> [Float] {
        let n = max(1, Int(dur * sr))
        let a = Int(attack * sr)
        var f = Biquad(type, f: freq, q: q, sr: sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let x = Double.random(in: -1...1)
            out[i] = Float(f.process(x)) * env(i, n, a, gain)
        }
        return out
    }

    private func tone(_ dur: Double, _ f0: Double, _ f1: Double, _ wave: Wave = .sine, gain: Float, attack: Double = 0.002) -> [Float] {
        let n = max(1, Int(dur * sr))
        let a = Int(attack * sr)
        var out = [Float](repeating: 0, count: n)
        var ph = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let f = f0 * pow(f1 / f0, t)
            ph += f / sr
            ph -= floor(ph)
            let s: Double
            switch wave {
            case .sine: s = sin(2 * Double.pi * ph)
            case .triangle: s = 4 * abs(ph - 0.5) - 1
            case .square: s = ph < 0.5 ? 1 : -1
            case .saw: s = 2 * ph - 1
            }
            out[i] = Float(s) * env(i, n, a, gain)
        }
        return out
    }

    private func mix(_ parts: [(Double, [Float])]) -> [Float] {
        var len = 0
        for (off, s) in parts { len = max(len, Int(off * sr) + s.count) }
        var out = [Float](repeating: 0, count: len + Int(0.005 * sr))
        for (off, s) in parts {
            let o = Int(off * sr)
            for i in 0..<s.count { out[o + i] += s[i] }
        }
        return out
    }

    private func makeBuffer(_ s: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(s.count))!
        b.frameLength = AVAudioFrameCount(s.count)
        let d = b.floatChannelData![0]
        for i in 0..<s.count { d[i] = tanhf(s[i] * 1.2) }
        return b
    }

    private func cached(_ key: String, _ make: () -> [Float]) -> AVAudioPCMBuffer {
        if let b = cache[key] { return b }
        let b = makeBuffer(make())
        cache[key] = b
        return b
    }

    private func play(_ buf: AVAudioPCMBuffer) {
        guard enabled, !players.isEmpty else { return }
        if !engine.isRunning { start() }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    // MARK: Buffers

    private func keyBuf(_ type: KeyType, _ down: Bool, _ v: Int) -> AVAudioPCMBuffer {
        let p = [0.96, 1.0, 1.04][v]
        return cached("key-\(type.rawValue)-\(down)-\(v)") {
            switch (type, down) {
            case (.clicky, true):
                return mix([
                    (0, noise(0.02, .bandpass, 5200 * p, q: 3, gain: 0.9)),
                    (0, tone(0.015, 2400 * p, 1400 * p, .square, gain: 0.07)),
                    (0.012, noise(0.035, .bandpass, 1800 * p, q: 1.5, gain: 0.35))
                ])
            case (.clicky, false):
                return noise(0.018, .bandpass, 4300 * p, q: 3, gain: 0.55)
            case (.tactile, true):
                return mix([
                    (0, tone(0.05, 420 * p, 220 * p, gain: 0.45)),
                    (0, noise(0.03, .bandpass, 2000 * p, q: 1.2, gain: 0.45))
                ])
            case (.tactile, false):
                return mix([
                    (0, tone(0.03, 520 * p, 300 * p, gain: 0.2)),
                    (0, noise(0.025, .bandpass, 1600 * p, q: 1.2, gain: 0.25))
                ])
            case (.thocky, true):
                return mix([
                    (0, tone(0.11, 190 * p, 85 * p, gain: 0.85)),
                    (0, noise(0.05, .lowpass, 900 * p, q: 0.7, gain: 0.6))
                ])
            case (.thocky, false):
                return mix([
                    (0, tone(0.05, 260 * p, 150 * p, gain: 0.35)),
                    (0, noise(0.02, .lowpass, 1400, q: 0.7, gain: 0.25))
                ])
            }
        }
    }

    private func tickBuf(_ pitch: Double) -> AVAudioPCMBuffer {
        cached("tick-\(pitch)") {
            mix([
                (0, noise(0.014, .highpass, 4200 * pitch, q: 0.7, gain: 0.5)),
                (0, tone(0.012, 2200 * pitch, 1800 * pitch, .triangle, gain: 0.12))
            ])
        }
    }

    private func popBuf(_ v: Int) -> AVAudioPCMBuffer {
        let p = 0.8 + Double(v) * 0.07
        return cached("pop-\(v)") {
            mix([
                (0, noise(0.035, .bandpass, 1600 * p, q: 0.9, gain: 0.8)),
                (0, tone(0.08, 950 * p, 160 * p, gain: 0.45)),
                (0.004, noise(0.06, .lowpass, 600 * p, q: 0.5, gain: 0.35))
            ])
        }
    }

    // MARK: Public sounds

    func key(_ type: KeyType, down: Bool) {
        play(keyBuf(type, down, Int.random(in: 0..<3)))
    }

    func tick(_ pitch: Double = 1) {
        let now = CACurrentMediaTime()
        guard now - lastTick > 0.018 else { return }
        lastTick = now
        let q = (max(0.5, min(1.6, pitch)) * 20).rounded() / 20
        play(tickBuf(q))
    }

    func pop() {
        play(popBuf(Int.random(in: 0..<8)))
    }

    func thunk(_ pitch: Double = 1) {
        let q = (pitch * 10).rounded() / 10
        play(cached("thunk-\(q)") {
            mix([
                (0, tone(0.14, 170 * q, 60 * q, gain: 0.8)),
                (0, noise(0.04, .lowpass, 1000 * q, q: 0.7, gain: 0.5))
            ])
        })
    }

    func toggle(on: Bool) {
        play(cached("toggle-\(on)") {
            mix([
                (0, noise(0.02, .bandpass, on ? 3600 : 2600, q: 2, gain: 0.7)),
                (0, tone(0.08, on ? 320 : 220, on ? 160 : 100, gain: 0.5))
            ])
        })
    }

    func pluck(_ freq: Double) {
        play(cached("pluck-\(Int(freq))") {
            mix([
                (0, tone(0.5, freq, freq, .sine, gain: 0.45, attack: 0.003)),
                (0, tone(0.08, freq * 4, freq * 4, .sine, gain: 0.08)),
                (0, noise(0.012, .bandpass, freq * 3, q: 2, gain: 0.25))
            ])
        })
    }

    func whoosh() {
        play(cached("whoosh") { noise(0.4, .bandpass, 700, q: 0.8, gain: 0.35, attack: 0.15) })
    }

    func chime(_ notes: [Double], gap: Double = 0.07, dur: Double = 0.3) {
        play(cached("chime-\(notes)-\(gap)-\(dur)") {
            var parts: [(Double, [Float])] = []
            for (i, n) in notes.enumerated() {
                parts.append((Double(i) * gap, tone(dur, n, n, .triangle, gain: 0.28)))
                parts.append((Double(i) * gap, tone(dur * 0.5, n * 2, n * 2, .sine, gain: 0.06)))
            }
            return mix(parts)
        })
    }

    func glide(_ f0: Double, _ f1: Double, dur: Double = 0.18) {
        play(cached("glide-\(f0)-\(f1)-\(dur)") { tone(dur, f0, f1, .triangle, gain: 0.3) })
    }

    func buzz() {
        play(cached("buzz") {
            mix([
                (0, tone(0.5, 150, 80, .saw, gain: 0.22)),
                (0, tone(0.5, 155, 82, .square, gain: 0.08))
            ])
        })
    }

    /// Spinner whir; speed is roughly revolutions-per-second / 3.
    func setWhir(_ speed: Float) {
        whirTarget = enabled ? min(0.25, speed * 0.06) : 0
        whirSpeedTarget = speed
    }

    private func renderWhir(_ frameCount: AVAudioFrameCount, _ abl: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let n = Int(frameCount)
        let target = whirTarget
        whirSpeed += (whirSpeedTarget - whirSpeed) * 0.15
        whirFilter.configure(.bandpass, f: Double(180 + whirSpeed * 380), q: 1.6, sr: sr)
        let inc = (30 + whirSpeed * 22) / Float(sr)
        for i in 0..<n {
            whirGain += (target - whirGain) * 0.0015
            rng ^= rng << 13
            rng ^= rng >> 17
            rng ^= rng << 5
            let white = Float(rng) / Float(UInt32.max) * 2 - 1
            let bp = Float(whirFilter.process(Double(white)))
            whirPhase += inc
            if whirPhase >= 1 { whirPhase -= 1 }
            let tri = 4 * abs(whirPhase - 0.5) - 1
            let v = (bp + tri * 0.35) * whirGain
            for buf in buffers {
                buf.mData?.assumingMemoryBound(to: Float.self)[i] = v
            }
        }
        return noErr
    }
}
