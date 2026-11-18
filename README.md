# Fidget Playground

A haptic fidget-toy web app for phones. No build step, no dependencies: one `index.html`.

**Toys:** Reflex game (tap / double tap / hold / swipe / spin on command), Clicker (clicky, tactile, thocky switches), Spinner (flick physics, tick per arm, whir), Bubble Wrap (drag to pop), Detent Dial (30 clicks + hard stops), Cube (drag, snap, tap to roll), Marimba Slider, Switch Bank.

## Haptics
- **iPhone (Safari, iOS 18+):** uses the hidden `<input type="checkbox" switch>` trick, which fires the system haptic tick. Requires System Haptics enabled.
- **Android:** Vibration API.

Sounds are synthesized live with Web Audio.

## Run
- Locally: `python3 -m http.server` then open `http://<your-ip>:8000` on your phone.
- Hosted: enable GitHub Pages (Settings › Pages › Deploy from branch › `main` / root).
- Install: Safari › Share › Add to Home Screen (works offline via `sw.js`).

## Native iPhone app (real haptics)
Safari can only fire a faint single tick, so there's a native SwiftUI version in `ios/` using Core Haptics (crisp clicks, continuous rumble on the spinner), a low-latency synth audio engine and 120Hz touch handling.

1. Open `ios/FidgetPlayground.xcodeproj` in Xcode 16+.
2. Target › Signing & Capabilities: pick your Team (a free Apple ID works). Change the bundle ID if Xcode says it's taken.
3. Plug in your iPhone, select it as the run destination, press Run.
4. First time: on the phone, Settings › General › VPN & Device Management › trust your developer certificate. Also enable Developer Mode if prompted.

With a free Apple ID the install expires after 7 days; just hit Run again.
