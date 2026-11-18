import SwiftUI
import SceneKit
import simd
import QuartzCore

final class CubeModel: ObservableObject {
    @Published var face = 1
    @Published var rolls = UserDefaults.standard.integer(forKey: "rolls")

    let scene = SCNScene()
    private let cube: SCNNode
    private let tiltQ: simd_quatf

    private enum Mode { case idle, drag, spin, settle }
    private var mode = Mode.idle
    private var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var target = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var omega = SIMD3<Float>(repeating: 0)   // rad/s, screen axes
    private var snap = 0
    private var last = CGPoint.zero
    private var lastT: CFTimeInterval = 0
    private var startT: CFTimeInterval = 0
    private var maxDist: CGFloat = 0
    private var link: DisplayLink?

    /// The 24 orientations where the cube sits square.
    private static let snaps: [simd_quatf] = {
        var out: [simd_quatf] = []
        let perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        let signs: [Float] = [1, -1]
        for p in perms {
            for sx in signs {
                for sy in signs {
                    for sz in signs {
                        let sg = [sx, sy, sz]
                        var cols: [SIMD3<Float>] = []
                        for i in 0..<3 {
                            var c = SIMD3<Float>(repeating: 0)
                            c[p[i]] = sg[i]
                            cols.append(c)
                        }
                        let m = simd_float3x3(cols[0], cols[1], cols[2])
                        if simd_determinant(m) > 0 { out.append(simd_quatf(m)) }
                    }
                }
            }
        }
        return out
    }()

    init() {
        let box = SCNBox(width: 1.4, height: 1.4, length: 1.4, chamferRadius: 0.16)
        // SCNBox material order: front, right, back, left, top, bottom. Opposite faces sum to 7.
        let faces: [(Int, UIColor)] = [
            (1, UIColor(hex: 0xFFCF3F)), (3, UIColor(hex: 0x35DFB0)), (6, UIColor(hex: 0xA88CFF)),
            (4, UIColor(hex: 0xFF5C8D)), (2, UIColor(hex: 0x4CB3FF)), (5, UIColor(hex: 0xFF7B3A))
        ]
        box.materials = faces.map { f in
            let m = SCNMaterial()
            m.diffuse.contents = CubeModel.faceImage(f.0, f.1)
            m.lightingModel = .blinn
            m.specular.contents = UIColor(white: 0.35, alpha: 1)
            m.shininess = 0.4
            return m
        }
        cube = SCNNode(geometry: box)

        let tilt = SCNNode()
        tilt.eulerAngles = SCNVector3(-0.38, 0.55, 0)
        tilt.addChildNode(cube)
        tiltQ = tilt.simdOrientation
        scene.rootNode.addChildNode(tilt)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 32
        cam.position = SCNVector3(0, 0, 6.5)
        scene.rootNode.addChildNode(cam)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 800
        key.eulerAngles = SCNVector3(-0.7, -0.5, 0)
        scene.rootNode.addChildNode(key)

        scene.background.contents = UIColor.clear
    }

    func appear() {
        link = DisplayLink { [weak self] dt in self?.step(dt) }
        link?.start()
    }

    func disappear() {
        link?.stop()
        link = nil
    }

    func drag(_ v: DragGesture.Value) {
        let now = CACurrentMediaTime()
        if mode != .drag {
            mode = .drag
            last = v.location
            lastT = now
            startT = now
            maxDist = 0
            omega = .zero
            return
        }
        let dx = Float(v.location.x - last.x)
        let dy = Float(v.location.y - last.y)
        let dt = Float(max(0.001, now - lastT))
        maxDist = max(maxDist, hypot(v.translation.width, v.translation.height))
        let k: Float = 0.011
        let r = SIMD3<Float>(dy * k, dx * k, 0)
        rotate(by: r)
        omega = omega * 0.4 + (r / dt) * 0.6
        last = v.location
        lastT = now
        checkSnap()
    }

    func end(_ v: DragGesture.Value) {
        guard mode == .drag else { return }
        let now = CACurrentMediaTime()
        if maxDist < 8 && now - startT < 0.35 {
            roll()
            return
        }
        if now - lastT > 0.08 { omega = .zero }
        let speed = simd_length(omega)
        if speed > 30 { omega *= 30 / speed }
        mode = .spin
    }

    private func roll() {
        rolls += 1
        UserDefaults.standard.set(rolls, forKey: "rolls")
        var axis = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -0.3...0.3))
        if simd_length(axis) < 0.1 { axis = SIMD3<Float>(1, 0.6, 0) }
        omega = simd_normalize(axis) * Float.random(in: 16...24)
        mode = .spin
        Sound.shared.whoosh()
        Haptics.shared.light()
    }

    /// Rotate by a screen-space rotation vector (radians).
    private func rotate(by r: SIMD3<Float>) {
        let a = simd_length(r)
        guard a > 1e-6 else { return }
        let dq = simd_quatf(angle: a, axis: r / a)
        q = simd_normalize(tiltQ.inverse * dq * tiltQ * q)
    }

    private func step(_ dt: Double) {
        let dtf = Float(dt)
        switch mode {
        case .idle, .drag:
            break
        case .spin:
            rotate(by: omega * dtf)
            omega *= expf(-2.6 * dtf)
            checkSnap()
            if simd_length(omega) < 2 {
                target = Self.snaps[nearest()]
                mode = .settle
            }
        case .settle:
            q = simd_slerp(q, target, 1 - expf(-16 * dtf))
            if angleBetween(q, target) < 0.004 {
                q = target
                mode = .idle
                Sound.shared.thunk(1.1)
                Haptics.shared.thud()
                face = facing()
            }
        }
        cube.simdOrientation = q
    }

    private func nearest() -> Int {
        var best = 0
        var bd: Float = -1
        for (i, s) in Self.snaps.enumerated() {
            let d = abs(simd_dot(q.vector, s.vector))
            if d > bd { bd = d; best = i }
        }
        return best
    }

    private func checkSnap() {
        let n = nearest()
        if n != snap {
            snap = n
            Haptics.shared.tick(0.6, 0.8)
            Sound.shared.tick(0.75)
        }
    }

    private func angleBetween(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acosf(min(1, abs(simd_dot(a.vector, b.vector))))
    }

    private func facing() -> Int {
        let normals: [(Int, SIMD3<Float>)] = [
            (1, SIMD3(0, 0, 1)), (6, SIMD3(0, 0, -1)), (3, SIMD3(1, 0, 0)),
            (4, SIMD3(-1, 0, 0)), (2, SIMD3(0, 1, 0)), (5, SIMD3(0, -1, 0))
        ]
        let full = tiltQ * q
        var best = 1
        var bz: Float = -2
        for (n, v) in normals {
            let z = full.act(v).z
            if z > bz { bz = z; best = n }
        }
        return best
    }

    static func faceImage(_ n: Int, _ color: UIColor) -> UIImage {
        let s: CGFloat = 256
        let a: CGFloat = 0.27, b: CGFloat = 0.5, c: CGFloat = 0.73
        let layout: [Int: [CGPoint]] = [
            1: [CGPoint(x: b, y: b)],
            2: [CGPoint(x: a, y: a), CGPoint(x: c, y: c)],
            3: [CGPoint(x: a, y: a), CGPoint(x: b, y: b), CGPoint(x: c, y: c)],
            4: [CGPoint(x: a, y: a), CGPoint(x: c, y: a), CGPoint(x: a, y: c), CGPoint(x: c, y: c)],
            5: [CGPoint(x: a, y: a), CGPoint(x: c, y: a), CGPoint(x: b, y: b), CGPoint(x: a, y: c), CGPoint(x: c, y: c)],
            6: [CGPoint(x: a, y: a), CGPoint(x: c, y: a), CGPoint(x: a, y: b), CGPoint(x: c, y: b), CGPoint(x: a, y: c), CGPoint(x: c, y: c)]
        ]
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            UIColor(red: 0.09, green: 0.06, blue: 0.2, alpha: 0.9).setFill()
            let r: CGFloat = 22
            for p in layout[n] ?? [] {
                UIBezierPath(ovalIn: CGRect(x: p.x * s - r, y: p.y * s - r, width: 2 * r, height: 2 * r)).fill()
            }
        }
    }
}

struct SceneContainer: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = scene
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 120
        v.rendersContinuously = true
        v.isPlaying = true
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct CubeView: View {
    @StateObject private var m = CubeModel()

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 48) {
                Stat(value: "\(m.face)", label: "facing")
                Stat(value: "\(m.rolls)", label: "rolls")
            }
            SceneContainer(scene: m.scene)
                .overlay(
                    Color.white.opacity(0.001)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { m.drag($0) }
                                .onEnded { m.end($0) }
                        )
                )
        }
        .padding(.vertical, 16)
        .onAppear { m.appear() }
        .onDisappear { m.disappear() }
    }
}
