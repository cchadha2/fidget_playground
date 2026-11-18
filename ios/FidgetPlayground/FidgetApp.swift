import SwiftUI

@main
struct FidgetApp: App {
    init() {
        // Warm up the haptic and audio engines so the first touch has no lag.
        _ = Haptics.shared
        _ = Sound.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
