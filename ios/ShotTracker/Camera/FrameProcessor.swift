import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics

/// Owns the detection pipeline and bridges background camera frames to the
/// @MainActor GameSession. Runs on `AVCaptureVideoDataOutput`'s delegate queue.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // Injected on the main actor at construction time.
    private weak var session: GameSession?
    private let haptics: HapticsEngine?

    // Detectors are not Sendable-safe; they are only touched on the frame queue.
    private let rim = RimDisruptionDetector()
    private let ballDetector = ColorBallDetector()
    private let classifier = ShotClassifier()

    // Frame throttling knobs (ported from the web app's detectInterval).
    private var frameCount: UInt64 = 0
    private let ballDetectInterval = 3   // every 3rd frame

    // Cached hoop value read from main on each frame; updated via `updateHoop`.
    private var hoopCache: CGPoint?

    init(session: GameSession, haptics: HapticsEngine?) {
        self.session = session
        self.haptics = haptics
    }

    /// Call when the hoop placement changes; kept atomic via simple property set
    /// on the frame queue.
    func updateHoop(_ hoop: CGPoint?) {
        // Dispatched onto the frame processor's synchronization boundary when
        // the frame callback runs; for placement we expect infrequent updates
        // so a direct assignment is fine (no queue hop).
        hoopCache = hoop
        if hoop == nil {
            rim.reset()
            ballDetector.reset()
            classifier.reset()
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCount &+= 1
        guard let hoop = hoopCache else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let locked = LockedPixelBuffer(pixelBuffer) else { return }

        let nowMs = Date().timeIntervalSince1970 * 1000

        // Rim disruption every 2nd frame — cheap (64x64).
        if frameCount % 2 == 0 {
            _ = rim.process(pixelBuffer: locked, hoop: hoop, timestampMs: nowMs)
        }

        // Ball detection every Nth frame.
        var detected: DetectedBall?
        if frameCount % UInt64(ballDetectInterval) == 0 {
            detected = ballDetector.process(pixelBuffer: locked, hoop: hoop, timestampMs: nowMs)
            classifier.noteBall(detected)
        }

        // Classifier tick every frame.
        let outcome = classifier.tick(nowMs: nowMs, hoop: hoop, rimScores: rim.scores)
        let ballCopy = detected
        let trailSnapshot = classifier.trail

        guard let session else { return }
        Task { @MainActor [weak session, haptics] in
            guard let session else { return }
            if !trailSnapshot.isEmpty { session.ballTrail = trailSnapshot }
            _ = ballCopy
            if let outcome {
                switch outcome.kind {
                case .make:
                    session.logAutoMake(reason: outcome.reason)
                    haptics?.make()
                case .miss:
                    session.logAutoMiss(reason: outcome.reason)
                    haptics?.miss()
                }
            }
        }
    }
}
