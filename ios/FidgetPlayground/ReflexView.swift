import SwiftUI
import AVFoundation
import QuartzCore

final class ReflexModel: ObservableObject {
    enum Cmd: CaseIterable {
        case tap, double, hold, up, down, left, right, spin

        var word: String {
            switch self {
            case .tap: "Tap it"
            case .double: "Double tap"
            case .hold: "Hold it"
            case .up: "Swipe up"
            case .down: "Swipe down"
            case .left: "Swipe left"
            case .right: "Swipe right"
            case .spin: "Spin it"
            }
        }

        var symbol: String {
            switch self {
            case .tap: "hand.tap.fill"
            case .double: "circle.circle.fill"
            case .hold: "hand.raised.fill"
            case .up: "arrow.up"
            case .down: "arrow.down"
            case .left: "arrow.left"
            case .right: "arrow.right"
            case .spin: "arrow.clockwise"
            }
        }

        var color: Color {
            switch self {
            case .tap: Palette.sun
            case .double: Palette.mint
            case .hold: Palette.lilac
            case .up, .down: Palette.sky
            case .left, .right: Palette.tangerine
            case .spin: Palette.rose
            }
        }

        func cue() {
            switch self {
            case .tap: Sound.shared.chime([784], gap: 0, dur: 0.15)
            case .double: Sound.shared.chime([784, 784], gap: 0.1, dur: 0.12)
            case .hold: Sound.shared.chime([392], gap: 0, dur: 0.5)
            case .up: Sound.shared.glide(500, 1000)
            case .down: Sound.shared.glide(1000, 500)
            case .left: Sound.shared.chime([659, 523], gap: 0.08, dur: 0.12)
            case .right: Sound.shared.chime([523, 659], gap: 0.08, dur: 0.12)
            case .spin: Sound.shared.chime([523, 659, 784, 659], gap: 0.05, dur: 0.1)
            }
        }
    }

    enum Phase { case idle, countdown, play, gap, over }

    @Published var phase = Phase.idle
    @Published var cmd: Cmd?
    @Published var progress: Double = 1
    @Published var score = 0
    @Published var best = UserDefaults.standard.integer(forKey: "reflexBest")
    @Published var countdown = 3
    @Published var headline = "Ready?"
    @Published var detail = "Press Start, then tap, swipe, hold or spin on this pad."
    @Published var shake: CGFloat = 0
    @Published var voice = UserDefaults.standard.object(forKey: "voice") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voice, forKey: "voice") }
    }

    var tint: Color {
        switch phase {
        case .over: Palette.rose
        case .countdown: Palette.sun
        default: cmd?.color ?? Palette.trayHi
        }
    }

    private let holdTime = 0.5
    private var deadline: CFTimeInterval = 0
    private var limit: CFTimeInterval = 1
    private var generation = 0
    private let speech = AVSpeechSynthesizer()
    private var link: DisplayLink?

    // Gesture tracking
    private var touching = false
    private var ignoreTouch = false
    private var gStart: CGPoint?
    private var gDist: CGFloat = 0
    private var gAcc: Double = 0
    private var gPrevA: Double = 0
    private var gDone = false
    private var holdItem: DispatchWorkItem?
    private var pendingTap: DispatchWorkItem?

    func start() {
        generation += 1
        let gen = generation
        clearTimers()
        score = 0
        cmd = nil
        phase = .countdown
        countdown = 3
        progress = 1
        Haptics.shared.light()
        Sound.shared.chime([440], gap: 0, dur: 0.12)
        if link == nil {
            link = DisplayLink { [weak self] _ in self?.step() }
            link?.start()
        }
        for k in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 * Double(k)) { [weak self] in
                guard let self, self.generation == gen else { return }
                if k < 3 {
                    self.countdown = 3 - k
                    Sound.shared.chime([440], gap: 0, dur: 0.12)
                    Haptics.shared.light()
                } else {
                    self.next()
                }
            }
        }
    }

    func stop() {
        generation += 1
        clearTimers()
        link?.stop()
        link = nil
        speech.stopSpeaking(at: .immediate)
        if phase != .over { phase = .idle }
    }

    private func next() {
        clearTimers()
        var c: Cmd
        repeat {
            c = Cmd.allCases.randomElement()!
        } while c == cmd && Double.random(in: 0...1) < 0.7
        cmd = c
        let base = max(0.85, 2.6 * pow(0.95, Double(score)))
        limit = base + (c == .spin ? 0.9 : 0) + (c == .hold ? holdTime : 0) + (c == .double ? 0.25 : 0)
        deadline = CACurrentMediaTime() + limit
        progress = 1
        phase = .play
        c.cue()
        say(c.word)
        Haptics.shared.light()
    }

    private func step() {
        guard phase == .play else { return }
        progress = max(0, (deadline - CACurrentMediaTime()) / limit)
        if progress <= 0 { fail("Too slow") }
    }

    private func say(_ text: String) {
        guard voice else { return }
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.58
        u.pitchMultiplier = 1.15
        speech.speak(u)
    }

    private func clearTimers() {
        holdItem?.cancel()
        holdItem = nil
        pendingTap?.cancel()
        pendingTap = nil
        gStart = nil
        gDone = false
        if touching { ignoreTouch = true }
    }

    private func success() {
        phase = .gap
        clearTimers()
        score += 1
        let base = 523.25 * pow(2, Double(score % 12) / 12)
        Sound.shared.chime([base, base * 1.5], gap: 0.06, dur: 0.2)
        Haptics.shared.medium()
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, self.generation == gen, self.phase == .gap else { return }
            self.next()
        }
    }

    private func fail(_ reason: String) {
        phase = .over
        clearTimers()
        progress = 0
        Sound.shared.buzz()
        Haptics.shared.error()
        withAnimation(.linear(duration: 0.4)) { shake += 1 }
        let newBest = score > best
        if newBest {
            best = score
            UserDefaults.standard.set(best, forKey: "reflexBest")
        }
        headline = newBest ? "New best!" : "Game over"
        detail = "\(reason). You scored \(score)."
        say(headline)
    }

    private func judge(_ kind: Cmd) {
        guard phase == .play, let cmd else { return }
        if kind == cmd {
            success()
        } else {
            fail("That was \(kind.word.lowercased())")
        }
    }

    // MARK: Gestures

    func touch(_ v: DragGesture.Value, size: CGSize) {
        if !touching {
            touching = true
            ignoreTouch = phase != .play
            if !ignoreTouch { begin(v, size: size) }
        }
        guard !ignoreTouch, !gDone, let s = gStart else { return }
        gDist = max(gDist, hypot(v.location.x - s.x, v.location.y - s.y))
        let a = angleDeg(v.location, in: size)
        gAcc += wrapDeg(a - gPrevA)
        gPrevA = a
        if abs(gAcc) >= 300 {
            gDone = true
            holdItem?.cancel()
            judge(.spin)
        }
    }

    private func begin(_ v: DragGesture.Value, size: CGSize) {
        gStart = v.startLocation
        gDist = 0
        gAcc = 0
        gDone = false
        gPrevA = angleDeg(v.startLocation, in: size)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.gStart != nil, !self.gDone, self.gDist < 24 else { return }
            self.gDone = true
            self.judge(.hold)
        }
        holdItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime, execute: item)
    }

    func touchEnded(_ v: DragGesture.Value) {
        touching = false
        holdItem?.cancel()
        if ignoreTouch {
            ignoreTouch = false
            return
        }
        guard let s = gStart else { return }
        gStart = nil
        if gDone || phase != .play { return }
        let dx = v.location.x - s.x
        let dy = v.location.y - s.y
        if hypot(dx, dy) >= 40 {
            if abs(dx) > abs(dy) {
                judge(dx > 0 ? .right : .left)
            } else {
                judge(dy > 0 ? .down : .up)
            }
            return
        }
        if gDist >= 40 { return }
        if cmd == .double {
            if let p = pendingTap {
                p.cancel()
                pendingTap = nil
                judge(.double)
            } else {
                Haptics.shared.tick(0.6, 0.8)
                Sound.shared.tick(1.2)
                let item = DispatchWorkItem { [weak self] in
                    self?.pendingTap = nil
                    self?.judge(.tap)
                }
                pendingTap = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.33, execute: item)
            }
        } else {
            judge(.tap)
        }
    }
}

struct ReflexView: View {
    @StateObject private var m = ReflexModel()

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 48) {
                Stat(value: "\(m.score)", label: "score")
                Stat(value: "\(m.best)", label: "best")
            }
            pad
            HStack(spacing: 12) {
                Button {
                    m.voice.toggle()
                    Haptics.shared.light()
                } label: {
                    Image(systemName: m.voice ? "waveform" : "waveform.slash")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 58, height: 56)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.tray))
                        .foregroundStyle(m.voice ? Palette.text : Palette.muted)
                }
                .buttonStyle(.plain)
                Button(startTitle) {
                    m.start()
                }
                .buttonStyle(BigButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onDisappear { m.stop() }
    }

    private var startTitle: String {
        switch m.phase {
        case .idle: "Start"
        case .over: "Play again"
        default: "Restart"
        }
    }

    private var pad: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        RadialGradient(colors: [m.tint.opacity(0.35), Palette.trayHi],
                                       center: .center, startRadius: 10, endRadius: 280)
                    )
                padContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                GeometryReader { g in
                    Rectangle()
                        .fill(m.tint)
                        .frame(width: g.size.width * m.progress)
                }
                .frame(height: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { m.touch($0, size: geo.size) }
                    .onEnded { m.touchEnded($0) }
            )
        }
        .modifier(Shake(amount: m.shake))
    }

    @ViewBuilder
    private var padContent: some View {
        switch m.phase {
        case .countdown:
            Text("\(m.countdown)")
                .font(.system(size: 110, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.sun)
                .contentTransition(.numericText())
        case .play, .gap:
            if let c = m.cmd {
                VStack(spacing: 12) {
                    Image(systemName: c.symbol)
                        .font(.system(size: 70, weight: .bold))
                        .foregroundStyle(c.color)
                    Text(c.word.uppercased())
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                }
            }
        case .over:
            VStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Palette.rose)
                Text(m.headline)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                Text(m.detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        case .idle:
            VStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Palette.sun)
                Text(m.headline)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                Text(m.detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }
}
