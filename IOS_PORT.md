# iOS Port Plan — AI Shot Tracker

A practical, opinionated guide for porting this PWA to a native iOS app. This is written so that whoever picks up the iOS work can read top-to-bottom and start building, without having to also reverse-engineer the web app.

## 0. Prerequisites & Constraints

- **You need a Mac.** Xcode only runs on macOS. The current dev environment is Windows — budget for a Mac (M-series Mac mini is the cheapest viable option, ~$600 refurb) or a cloud Mac (MacStadium, MacInCloud).
- **Apple Developer Program membership:** $99/year. Required for TestFlight and App Store distribution. You can build + run on a personal device without it for ~7 days at a time via a free Apple ID, but that's not viable long-term.
- **Minimum iOS target:** iOS 17.0 is the sweet spot. It gives you:
  - `@Observable` macro (cleaner than ObservableObject)
  - `ShareLink` (native share sheet)
  - Mature Vision framework
  - ≈93% of active iPhones as of early 2026
- **Xcode version:** 15.3 or later.
- **Hardware for testing:** A physical iPhone. The simulator has no rear camera, so most of what you're building cannot be meaningfully tested in it.

## 1. Why port at all?

Re-stating the tradeoff from the initial discussion so it's captured here:

| Dimension | PWA (current) | Native iOS |
|---|---|---|
| Camera quality | Video element with `object-fit: cover`; browser-mediated pipeline | Direct `AVCaptureSession` at device-native resolution and framerate |
| Detection accuracy | COCO-SSD via TF.js in a WebView-adjacent JS context | Vision framework + CoreML, GPU-accelerated, 3–5× faster |
| Latency (frame→classification) | ~80–150ms on mid-tier iPhones | ~20–40ms |
| Distribution | Share a URL | App Store / TestFlight |
| Offline | Service worker caches shell | Native by default |
| Install friction | "Add to Home Screen" (most users don't know this exists) | App Store — one tap |
| Background audio/haptics | Limited | Full `AVAudioEngine` + `CoreHaptics` |
| Dev iteration speed | Edit → reload | Build → install → launch (~15s) |
| Cost | Free | $99/yr + Mac |

**The honest bar for "is it worth it":** if the PWA's detection accuracy is ≥85% and latency feels responsive (≤150ms), don't port. If you hit a ceiling because COCO-SSD can't reliably see the ball in your conditions, native is the move — the ceiling moves up significantly.

## 2. Tech stack

**Recommended:**
- **Swift 5.9+** with **SwiftUI** for the UI layer
- **AVFoundation** for the camera session
- **Vision + CoreML** for detection (with a custom-trained model — see §6)
- **Accelerate / vImage** for the rim-disruption frame-differencing
- **AVAudioEngine** for the swish/buzz sounds (same synthesis logic as today)
- **CoreHaptics** for tactile feedback on make/miss
- **No third-party dependencies** for the MVP. Everything above is first-party Apple.

**Avoid for v1:**
- React Native / Flutter — re-introduces the same WebView/JS overhead you're trying to escape.
- Capacitor / Cordova wrapping the current HTML — same reason.
- UIKit — SwiftUI is sufficient and faster to write.

## 3. Feature parity matrix

Every behavior currently in `index.html`, mapped to an iOS equivalent.

| Web feature | File/location today | iOS equivalent |
|---|---|---|
| Fullscreen camera preview | `<video>` + `object-fit: cover` | `AVCaptureVideoPreviewLayer` with `.resizeAspectFill` |
| Enable camera button + permission prompt | `getUserMedia` in `startCamera()` | `AVCaptureDevice.requestAccess(for: .video)` |
| Ball detection (COCO-SSD) | `runDetect()` in `index.html` | `VNCoreMLRequest` with custom object-detection model |
| Ball color fallback (HSV) | `detectBallByColor()` | Port 1:1; use `CVPixelBuffer` + manual loop or `vImage` |
| Background-subtraction static mask | `buildBackgroundFrame()` / `bgMask` | Port 1:1 to `UInt8` array |
| Rim disruption (frame diff) | `detectRimDisruption()` | Port to `vImageBuffer_Sub_Planar8` from Accelerate |
| Ball trajectory history | `ballHistory[]` | `[BallSample]` array in `ViewModel` |
| Shot attempt state machine | `checkMake()` + `classifyShotAttempt()` | Port 1:1 — it's pure logic |
| Hoop placement tap | canvas click → `hoop = {nx, ny}` | `SpatialTapGesture` on camera view; store normalized coords |
| Stats bar (FG%, makes, misses, total) | `#stats-bar` | SwiftUI `HStack` with glass background |
| Tap zones (✓/✕ manual) | `.tap-zone` divs | SwiftUI `Button` with `.background(.ultraThinMaterial)` |
| Swish sound | `playSwish()` | `AVAudioEngine` + `AVAudioPlayerNode` with generated buffer |
| Buzz sound | `playBuzz()` | Same |
| Sound toggle | `$('btn-sound')` | `@AppStorage("soundOn")` Bool + toolbar button |
| Undo last shot | `$('btn-undo')` | `shots.removeLast()` on ViewModel |
| Reset session | `$('btn-reset')` | Confirmation dialog + clear state |
| Session summary panel | `openSummary()` + `.summary-panel` | `.sheet` modal with SwiftUI `Chart` |
| Share as image | `shareSummary()` — renders to `<canvas>` | Render SwiftUI view to `UIImage` via `ImageRenderer`; pass to `ShareLink` |
| Rolling FG% chart | `drawChart()` on canvas | Swift Charts `LineMark` |
| Shot history dots | `#shot-dots` | `ForEach` of colored `Circle()` |
| Streak counter | `#streak-bar` | Computed property on ViewModel |
| Install prompt (PWA) | `beforeinstallprompt` | **Remove** — App Store replaces this |
| Service worker / offline | `sw.js` | **Remove** — native app is offline by default |
| Manifest / icons | `manifest.json` | App icon set in Xcode asset catalog |
| Status "AI loading / ready / off" | `#model-status` | Small SwiftUI pill bound to `@Published var modelState` |

Anything missing from that list should be noted as "explicitly cut" before implementation starts.

## 4. Project structure

A lean suggestion — adjust to taste:

```
ShotTracker/
├── ShotTrackerApp.swift                 // @main App entry
├── Views/
│   ├── CameraView.swift                 // Camera preview + overlays
│   ├── StatsBarView.swift
│   ├── HoopOverlayView.swift            // Draws hoop ring + trail
│   ├── TapZonesView.swift
│   ├── SummarySheet.swift
│   ├── OnboardingView.swift             // "Enable camera" screen
│   └── Components/
│       ├── GlassBar.swift               // Reusable glass container
│       └── StatCell.swift
├── Camera/
│   ├── CameraManager.swift              // Owns AVCaptureSession
│   ├── FrameProcessor.swift             // AVCaptureVideoDataOutput delegate
│   └── PreviewLayerView.swift           // UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
├── Detection/
│   ├── BallDetector.swift               // VNCoreMLRequest wrapper
│   ├── ColorBallDetector.swift          // HSV fallback port
│   ├── RimDisruptionDetector.swift      // Frame-diff port
│   ├── BackgroundSubtractor.swift       // bgMask port
│   └── ShotClassifier.swift             // checkMake / classifyShotAttempt port
├── Model/
│   ├── GameSession.swift                // @Observable — shots, hoop, session time
│   ├── Shot.swift                       // struct Shot { made: Bool, ts: Date, auto: Bool }
│   └── BallSample.swift
├── Audio/
│   └── SoundPlayer.swift                // Swish / buzz synthesis
├── Haptics/
│   └── HapticsEngine.swift              // CoreHaptics wrapper
├── Share/
│   └── ShareImageRenderer.swift         // SwiftUI view → UIImage
├── Resources/
│   ├── Assets.xcassets
│   └── BallDetector.mlmodel             // CoreML model file
└── Supporting/
    └── Info.plist
```

## 5. Camera pipeline

The single most important piece to get right.

### 5.1 Setting up `AVCaptureSession`

```swift
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "camera.frames", qos: .userInitiated)
    weak var frameDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?

    func configure() async throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080      // Match what the PWA was asking for

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back) else {
            throw CameraError.noDevice
        }
        // Lock to 30fps; bump to 60 later if perf allows
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(frameDelegate, queue: frameQueue)
        session.addOutput(videoOutput)

        if let conn = videoOutput.connection(with: .video) {
            conn.videoRotationAngle = 90   // portrait
        }
        session.commitConfiguration()
    }

    func start() { Task.detached { self.session.startRunning() } }
    func stop()  { session.stopRunning() }
}
```

### 5.2 Preview layer wrapped for SwiftUI

```swift
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView(session: session) }
    func updateUIView(_ v: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill   // equivalent of object-fit: cover
    }
    required init?(coder: NSCoder) { fatalError() }
}
```

### 5.3 Coordinate systems — the thing that bit us on web

On the web, the bug was that video pixel coords, canvas coords, and screen coords were all slightly different, and click events landed in the wrong space. iOS gives you a first-class helper that kills this class of bug:

```swift
// Screen point (from a SpatialTapGesture) → video pixel point
let videoPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: screenPoint)
// Video pixel point → screen point (for drawing overlays)
let screenPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: videoPoint)
```

**Use these for every coordinate conversion.** Do not roll your own scale math. `videoPoint` is normalized 0–1 in the capture device's sensor space, which is exactly the format the current `hoop = {nx, ny}` already uses — so the web→iOS translation is trivial.

## 6. Detection pipeline

This is where the accuracy gain comes from, and also the most open-ended work.

### 6.1 Model choice — three options in order of effort

**Option A: Off-the-shelf YOLOv8n CoreML**
- Convert a pretrained YOLOv8n (Ultralytics) to CoreML via `ultralytics` Python package: `model.export(format='coreml', nms=True)`.
- 80 COCO classes; "sports ball" is class 32 — same as COCO-SSD today.
- **Pros:** Ships in a day.
- **Cons:** Same fundamental accuracy as COCO-SSD. Uses a better model (YOLOv8 > SSD) but same training data, so some improvement but not transformative.

**Option B: Fine-tune YOLOv8 on basketball-specific data**
- Collect 500–2000 frames from real games (extract from the videos in `media/` + scrape YouTube).
- Label with [Roboflow](https://roboflow.com) or [Label Studio]: two classes — `basketball` and `hoop`.
- Fine-tune YOLOv8n on the labeled set (one evening on a Colab GPU).
- Export to CoreML.
- **Pros:** Dramatically better in your actual use conditions (outdoor, indoor, various ball colors, actual distances).
- **Cons:** 1–2 days of labeling work. Need a labeling pipeline you'll want again for v2.

**Option C: Use Apple's Vision `VNDetectHumanBodyPoseRequest` + ball tracker**
- Skip ball detection entirely. Track the shooter's wrist, classify "shot released" when wrist goes up + ball exits frame, then watch for rim disruption.
- **Pros:** Apple's pose model is world-class and free.
- **Cons:** Only works when the shooter is in frame. Current app supports mounting the phone near the hoop looking at incoming shots, which would break.

**Recommendation: Option A first (validate the pipeline works), then Option B once you have the pipeline plumbed in.** Do not start with Option B cold — you'll spend two days labeling before you know if your Vision pipeline even runs.

### 6.2 Running the model

```swift
final class BallDetector {
    private let request: VNCoreMLRequest
    private let model: VNCoreMLModel

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all        // GPU + Neural Engine
        let mlModel = try BallDetectorModel(configuration: config).model
        self.model = try VNCoreMLModel(for: mlModel)
        self.request = VNCoreMLRequest(model: model)
        self.request.imageCropAndScaleOption = .scaleFill
    }

    func detect(in pixelBuffer: CVPixelBuffer) -> [BallObservation] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return [] }
        return results.compactMap { obs in
            guard let label = obs.labels.first,
                  label.identifier == "basketball",   // or "sports ball" for Option A
                  label.confidence > 0.15
            else { return nil }
            return BallObservation(boundingBox: obs.boundingBox, confidence: label.confidence)
        }
    }
}
```

Note: `obs.boundingBox` is in Vision's normalized coordinate system (0,0 = bottom-left, not top-left — bless them). Convert to your app's top-left normalized space or to screen coords via the preview layer's conversion helpers.

### 6.3 Frame throttling

On web, detection runs every 2nd frame when the ball is visible, every 6th when not (`detectInterval`). Port this directly:

```swift
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var frameCount = 0
    private var detectInterval = 5

    func captureOutput(_ out: AVCaptureOutput,
                       didOutput sb: CMSampleBuffer,
                       from conn: AVCaptureConnection) {
        frameCount += 1
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }

        // Rim disruption — every 2 frames, lightweight
        if frameCount % 2 == 0 { rimDetector.process(pb) }

        // ML detection — adaptive
        if frameCount % detectInterval == 0 { ballDetector.schedule(pb) }
    }
}
```

### 6.4 Rim disruption — port the frame-diff approach

The JS uses `getImageData` + a manual diff loop. Native equivalent using Accelerate:

```swift
import Accelerate

func frameDiff(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Float {
    // Lock both, create vImage_Buffers for the rim ROI, call
    // vImageBuffer_Sub_Planar8 (or do it in Metal). Return average |diff|.
}
```

Frame-differencing is small enough (64×64 region) that a plain Swift loop over the raw bytes is also fine and avoids the Accelerate ceremony. Profile first, optimize later.

### 6.5 HSV color fallback

The web's `isBallColor()` and `detectBallByColor()` are pure arithmetic — port them line-for-line to Swift operating on a `UInt8` byte buffer from the CVPixelBuffer. No performance surprises.

### 6.6 Shot classifier state machine

`checkMake()`, `classifyShotAttempt()`, `checkBallLostMiss()`, `checkDisruptionMake()` in the JS are pure state-machine logic driven by timestamps and positions. These port *unchanged* in structure to Swift; they just happen to be reading from `[BallSample]` and `[RimScore]` arrays instead of the equivalent JS arrays.

**Budget a morning to port the classifier** and write unit tests for it against synthetic ball trajectories — this is the first thing you can unit-test in the iOS port, since it's pure logic with no camera dependency.

## 7. UI layer

### 7.1 Overall shape

```swift
struct ContentView: View {
    @State private var session = GameSession()
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            HoopOverlayView(session: session)   // draws hoop ring + ball trail

            VStack(spacing: 8) {
                HeaderBar(session: session)
                StatsBar(session: session)
                Spacer()
                if session.hoopPlaced {
                    TapZonesView(onMake: session.logMake, onMiss: session.logMiss)
                }
                ControlBar(camera: camera, session: session)
            }
            .padding(.horizontal)

            if session.hoopPlacementActive {
                HoopPlacementHint()
            }
        }
        .task { try? await camera.configure(); camera.start() }
    }
}
```

### 7.2 Glass overlays

SwiftUI ships glassmorphism primitives that are better than what you can do in CSS:

```swift
StatsBar(...)
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1)))
```

### 7.3 Drawing the hoop ring + ball trail

Use SwiftUI's `Canvas` view — it hands you a `GraphicsContext` that matches what you had with the 2D web canvas:

```swift
struct HoopOverlayView: View {
    let session: GameSession
    var body: some View {
        Canvas { ctx, size in
            if let hoop = session.hoop {
                let hx = hoop.x * size.width
                let hy = hoop.y * size.height
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: hx - 40, y: hy - 40, width: 80, height: 80)),
                    with: .color(.orange),
                    lineWidth: 3
                )
            }
            for sample in session.ballTrail {
                // draw trail dot
            }
        }
        .allowsHitTesting(false)
    }
}
```

Because this is a native `Canvas`, there's no DPR trap — SwiftUI handles the scale factor for you.

### 7.4 Hoop placement tap

```swift
CameraPreview(session: camera.session)
    .gesture(
        SpatialTapGesture()
            .onEnded { event in
                guard session.hoopPlacementActive else { return }
                let normalized = previewLayer.captureDevicePointConverted(
                    fromLayerPoint: event.location
                )
                session.hoop = normalized
                session.hoopPlacementActive = false
            }
    )
```

## 8. Audio — port the swish/buzz synthesis

The web code generates a filtered noise burst for swish and a square-wave blip for miss. Port to `AVAudioEngine`:

```swift
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        try? engine.start()
    }

    func playSwish() {
        let sr: Double = 44100, dur: Double = 0.3
        let frameCount = AVAudioFrameCount(sr * dur)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buf.frameLength = frameCount
        let ptr = buf.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sr
            let env = exp(-t * 12)
            ptr[i] = Float((Double.random(in: -1...1)) * env * 0.35)
        }
        // Bandpass filter if you want fidelity with the web version — use AVAudioUnitEQ
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
```

## 9. Haptics — net-new vs. the web app

The web app can't do this. Native can, and it sells the experience:

```swift
import CoreHaptics

final class HapticsEngine {
    private var engine: CHHapticEngine?
    init() { try? engine = CHHapticEngine() ; try? engine?.start() }

    func make() {
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
        ], relativeTime: 0)
        play([event])
    }
    func miss() {
        // two duller taps
    }
    private func play(_ events: [CHHapticEvent]) {
        guard let engine else { return }
        let pattern = try? CHHapticPattern(events: events, parameters: [])
        try? engine.makePlayer(with: pattern!).start(atTime: 0)
    }
}
```

Budget: ~2 hours. High ROI for perceived quality.

## 10. Sharing the session summary

On web, `shareSummary()` draws a PNG on a `<canvas>` and uses `navigator.share`. On iOS:

```swift
struct SummaryShareCard: View {
    let session: GameSession
    var body: some View {
        // Same layout as the current web share image, in SwiftUI
    }
}

// Rendering to UIImage:
@MainActor func renderShareImage(for session: GameSession) -> UIImage? {
    let renderer = ImageRenderer(content: SummaryShareCard(session: session))
    renderer.scale = 3
    return renderer.uiImage
}

// Sharing:
ShareLink(item: Image(uiImage: image), preview: SharePreview("Shot Tracker Session", image: image))
```

Reuse the visual layout — don't rebuild the share card from scratch; the one in `shareSummary()` is already thought-through.

## 11. Persistence

The web app has no persistence — sessions live in memory and are lost on reload. Carry this forward to v1 on iOS too. Do not sink time into CoreData until a user asks for session history.

If/when you do add history:
- **SwiftData** (iOS 17+) — tiny schema, zero ceremony. Use this over CoreData for a project this size.
- Persist `Shot` records with a `sessionId: UUID`.

## 12. Info.plist entries you'll need

```xml
<key>NSCameraUsageDescription</key>
<string>Shot Tracker uses the camera to automatically track your makes and misses.</string>
```

That is the only mandatory one. You do *not* need microphone (`NSMicrophoneUsageDescription`) since `getUserMedia({audio: false})` on web translates to not requesting audio on iOS either.

Other good-practice entries:
```xml
<key>UIRequiresFullScreen</key><true/>
<key>UIStatusBarStyle</key><string>UIStatusBarStyleLightContent</string>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
```

Lock portrait for v1. Landscape mode adds complexity (rotating the preview + re-running cover math) for no user benefit in a phone-mounted-on-tripod use case.

## 13. Things that simply don't port

Cut these explicitly so no one re-implements them by accident:

- **`sw.js` service worker** — native apps are offline-capable by default.
- **`manifest.json`** — replaced by Xcode's asset catalog + Info.plist.
- **`beforeinstallprompt` handling** — replaced by the App Store listing.
- **`#install-bar`** — same.
- **`apple-mobile-web-app-capable` meta tags** — same.
- **Web Audio `AudioContext` resume-on-gesture dance** — iOS native audio "just works" after you call `engine.start()`.

## 14. Performance targets

Hard numbers to aim for, measured on an iPhone 13 or newer:

- **Camera preview latency:** <40ms (glass-to-screen)
- **Detection tick latency:** <30ms per frame
- **End-to-end make/miss recognition:** <500ms from ball passing rim to popup
- **Sustained framerate:** 30fps for preview, 15fps for detection (every other frame)
- **Memory:** <150MB in steady state
- **Battery:** <8% per 10min session

Instrument with Xcode's Time Profiler and Energy Log early, not at the end.

## 15. Testing strategy

**Unit tests (XCTest) — the big wins:**
- Shot classifier: feed synthetic `[BallSample]` + `[RimScore]` sequences representing make / miss / swat / rimout, assert correct output. This catches >80% of regressions.
- `isBallColor(r,g,b)`: table-driven test of known-basketball vs known-not colors.
- Background subtractor: feed it N frames with a known static pattern, assert the mask is correct.

**UI tests:** skip for v1. The app is ~4 screens and UI test maintenance outweighs the value at this scale.

**Manual testing checklist (one-pager):**
1. Enable camera cold — permission dialog appears
2. Deny permission — graceful "open Settings" message
3. Enable camera — preview fills screen, no distortion
4. Place hoop — ring appears at tapped point
5. Shoot 10 makes — ≥8 auto-detected
6. Shoot 10 misses — ≥7 auto-detected, 0 false makes
7. Backgrounded → foregrounded — camera resumes cleanly
8. Phone call mid-session — audio duck + resume
9. Low battery mode — still usable
10. Direct sunlight / gym lighting / evening — no crashes

TestFlight a private build to 3–5 friends with hoops after the first end-to-end version works. Their feedback is the actual ground truth.

## 16. Migration roadmap

A phased plan that keeps you always-shippable.

**Phase 0 — scaffolding (1 day)**
- New Xcode project, SwiftUI App lifecycle, iOS 17 target.
- Commit the model file (Option A YOLOv8n CoreML) to the repo.
- `CameraManager` + `CameraPreview` rendering the feed fullscreen.
- No detection, no overlays. Just a working camera.

**Phase 1 — detection pipeline, no classifier (1–2 days)**
- `BallDetector` running against live frames; draw ball bounding box as a debug overlay.
- `ColorBallDetector` port as the fallback.
- `RimDisruptionDetector` port, visualized as a debug number in the corner.
- Hoop placement tap working.

**Phase 2 — classifier port (1 day)**
- Port `checkMake`, `classifyShotAttempt`, etc. line-for-line to `ShotClassifier.swift`.
- Unit tests for it with synthetic trajectories.
- Make/miss popups appear on screen.
- At this point you have feature parity with the PWA minus summary/share.

**Phase 3 — UI polish (2–3 days)**
- Glass bars, stat cells, tap zones, streak indicator.
- Summary sheet + Swift Charts rolling FG%.
- Share card renderer + `ShareLink`.
- Sound + haptics.

**Phase 4 — custom model (Option B, optional, 2–3 days)**
- Label ~1000 frames from your `media/` collection + YouTube pulls.
- Fine-tune YOLOv8n with `basketball` and `hoop` classes.
- Swap the `.mlmodel` file, verify accuracy lift on a validation set.

**Phase 5 — TestFlight (0.5 day)**
- Icon, screenshots, App Store Connect listing.
- Internal TestFlight to 3–5 testers.

**Total budget for v1 in the App Store: ~2 weeks of focused work.** Add 50% buffer for Apple review back-and-forth.

## 17. Open questions — answer before coding

These shape the architecture; don't skip them.

1. **Mount orientation.** Is the phone always mounted near the hoop looking out, or also mounted behind the shooter looking at the hoop? The current app supports both implicitly; picking one lets you train a much better detection model.
2. **Indoor only, or outdoor too?** Ball color ranges differ wildly. If outdoor, you need training data that includes it.
3. **One hoop at a time, or multi-hoop?** Current app is one-hoop; multi-hoop adds tracker state and UI. Out of scope for v1.
4. **Offline-only, or cloud sync?** If cloud, you're adding auth + a backend. Out of scope for v1.
5. **Free vs. paid?** Affects App Store positioning, screenshots, review process. Recommend free for v1 to gather usage data.
6. **iPad support?** iPad back cameras are bad; probably not worth the layout work. Phone-only for v1.

## 18. Risks

- **Apple rejection on the first review.** Common causes: vague camera usage string, no "what to do if permission denied" UX. Write the usage string as if explaining to a grandparent.
- **Custom model accuracy regresses vs. pretrained.** Always keep the pretrained YOLO model in the repo as a fallback you can ship if the fine-tune doesn't land.
- **Thermals on older iPhones.** 1080p @ 30fps + CoreML inference will warm an iPhone 11 in ~10 minutes. Add a throttle path that drops to 720p / 15fps detection if thermal state hits `.serious`.
- **Battery complaints.** See above — same mitigation.

## 19. Appendix — where current web logic lives

Quick index into [index.html](index.html) for the iOS developer:

- Camera start/stop: `startCamera()` / `stopCamera()` (~line 410)
- Render loop: `startLoop()` / `tick()` (~line 490)
- Ball detection (ML): `runDetect()` (~line 515)
- Ball detection (color fallback): `detectBallByColor()` (~line 655)
- HSV color classifier: `isBallColor()` (~line 880)
- Background subtraction: `buildBackgroundFrame()` / `resetBackground()` (~line 620)
- Rim disruption: `detectRimDisruption()` / `checkDisruptionMake()` (~line 780)
- Shot attempt state machine: `checkMake()` / `classifyShotAttempt()` (~line 950)
- Ball-lost miss detection: `checkBallLostMiss()` (~line 1025)
- Drawing: `drawHoop()` / `drawTrail()` / `drawBallCircle()` (~line 1060)
- Shot logging: `logShot()` (~line 1110)
- Summary panel: `openSummary()` (~line 1180)
- Share image renderer: `shareSummary()` (~line 1280)
- Sound synthesis: `playSwish()` / `playBuzz()` (~line 310)

For every function above, read it top-to-bottom before porting — the comments in the JS explain *why*, which is the part that won't survive a mechanical translation.
