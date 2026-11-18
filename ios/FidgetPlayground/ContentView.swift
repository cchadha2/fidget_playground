import SwiftUI

enum Toy: String, CaseIterable, Identifiable {
    case clicker, spinner, bubbles, dial, cube, marimba, switches, reflex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clicker: "Clicker"
        case .spinner: "Spinner"
        case .bubbles: "Bubble Wrap"
        case .dial: "Detent Dial"
        case .cube: "Cube"
        case .marimba: "Marimba"
        case .switches: "Switch Bank"
        case .reflex: "Reflex"
        }
    }

    var short: String {
        switch self {
        case .clicker: "Click"
        case .spinner: "Spin"
        case .bubbles: "Bubbles"
        case .dial: "Dial"
        case .cube: "Cube"
        case .marimba: "Marimba"
        case .switches: "Switches"
        case .reflex: "Reflex"
        }
    }

    var hint: String {
        switch self {
        case .clicker: "One very good button."
        case .spinner: "Flick it. Touch to catch."
        case .bubbles: "Tap or drag across to pop."
        case .dial: "30 clicks. Hard stops at each end."
        case .cube: "Drag to turn. Tap to roll."
        case .marimba: "Swipe across the bars."
        case .switches: "Flip all four."
        case .reflex: "Do what it says. Fast."
        }
    }

    var icon: String {
        switch self {
        case .clicker: "circle.circle.fill"
        case .spinner: "fan.fill"
        case .bubbles: "circle.grid.3x3.fill"
        case .dial: "dial.medium.fill"
        case .cube: "cube.fill"
        case .marimba: "pianokeys"
        case .switches: "switch.2"
        case .reflex: "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .clicker: Palette.tangerine
        case .spinner: Palette.rose
        case .bubbles: Palette.sky
        case .dial: Palette.lilac
        case .cube: Palette.sun
        case .marimba: Palette.mint
        case .switches: Palette.sky
        case .reflex: Palette.sun
        }
    }
}

struct ContentView: View {
    @State private var toy: Toy = .clicker
    @AppStorage("soundOn") private var soundOn = true
    @AppStorage("hapticsOn") private var hapticsOn = true

    var body: some View {
        VStack(spacing: 0) {
            header
            toyView(toy)
                .id(toy)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            picker
        }
        .background(Palette.bg.ignoresSafeArea())
        .foregroundStyle(Palette.text)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .onAppear {
            Sound.shared.enabled = soundOn
            Haptics.shared.enabled = hapticsOn
        }
    }

    @ViewBuilder
    private func toyView(_ t: Toy) -> some View {
        switch t {
        case .clicker: ClickerView()
        case .spinner: SpinnerView()
        case .bubbles: BubbleWrapView()
        case .dial: DialView()
        case .cube: CubeView()
        case .marimba: MarimbaView()
        case .switches: SwitchesView()
        case .reflex: ReflexView()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toy.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(toy.hint)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            iconToggle(on: soundOn, onIcon: "speaker.wave.2.fill", offIcon: "speaker.slash.fill") {
                soundOn.toggle()
                Sound.shared.enabled = soundOn
                Sound.shared.toggle(on: true)
            }
            iconToggle(on: hapticsOn, onIcon: "iphone.radiowaves.left.and.right", offIcon: "iphone.slash") {
                hapticsOn.toggle()
                Haptics.shared.enabled = hapticsOn
                Haptics.shared.medium()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func iconToggle(on: Bool, onIcon: String, offIcon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? onIcon : offIcon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(on ? Palette.trayHi : Palette.tray))
                .foregroundStyle(on ? Palette.text : Palette.muted)
        }
        .buttonStyle(.plain)
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Toy.allCases) { t in
                    pickerButton(t)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Palette.tray.opacity(0.7).ignoresSafeArea(edges: .bottom))
    }

    private func pickerButton(_ t: Toy) -> some View {
        let selected = t == toy
        return Button {
            guard t != toy else { return }
            withAnimation(.snappy(duration: 0.2)) { toy = t }
            Haptics.shared.tick(0.6, 0.7)
            Sound.shared.tick(1.2)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: t.icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(t.short)
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 74, height: 64)
            .background(RoundedRectangle(cornerRadius: 18).fill(selected ? t.color.opacity(0.22) : Palette.tray))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? t.color : Color.clear, lineWidth: 2))
            .foregroundStyle(selected ? Palette.text : Palette.muted)
        }
        .buttonStyle(.plain)
    }
}
