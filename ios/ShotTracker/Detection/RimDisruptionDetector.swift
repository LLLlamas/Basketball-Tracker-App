import Foundation
import CoreGraphics

struct RimScore: Hashable {
    let timestampMs: Double
    let score: Double
}

/// Port of `detectRimDisruption()` from index.html. Frame-diffs a small region
/// around the hoop to detect net / rim motion; peaks correlate with made shots.
final class RimDisruptionDetector {
    private var previous: [UInt8]?
    private(set) var scores: [RimScore] = []

    /// Process one frame. `hoop` is normalized (0...1, top-left origin).
    /// Returns the score for this frame, and appends to rolling 5s history.
    @discardableResult
    func process(
        pixelBuffer: LockedPixelBuffer,
        hoop: CGPoint,
        timestampMs: Double
    ) -> Double {
        let vw = pixelBuffer.width
        let vh = pixelBuffer.height
        let hx = hoop.x * CGFloat(vw)
        let hy = hoop.y * CGFloat(vh)
        let hr = CGFloat(DetectionConstants.hoopRadiusNormalized) * CGFloat(vw)

        let zw = hr * 3
        let zh = hr * 2.5
        let sx = max(0, hx - zw / 2)
        let sy = max(0, hy - zh * 0.4)
        let sw = min(zw, CGFloat(vw) - sx)
        let sh = min(zh, CGFloat(vh) - sy)

        let size = DetectionConstants.disruptSize
        let current = pixelBuffer.resample(
            sourceRect: CGRect(x: sx, y: sy, width: sw, height: sh),
            targetW: size,
            targetH: size
        )

        guard let prev = previous else {
            previous = current
            return 0
        }

        // Diff RGB ignoring left/right 15% margin, mirroring the JS impl.
        let margin = Int(Double(size) * 0.15)
        var totalDiff = 0
        var count = 0
        for y in 0..<size {
            let rowOffset = y * size
            for x in margin..<(size - margin) {
                let i = (rowOffset + x) * 4
                totalDiff += abs(Int(current[i])     - Int(prev[i]))
                totalDiff += abs(Int(current[i + 1]) - Int(prev[i + 1]))
                totalDiff += abs(Int(current[i + 2]) - Int(prev[i + 2]))
                count += 1
            }
        }
        let avgDiff = count > 0 ? Double(totalDiff) / Double(count * 3) : 0

        previous = current
        scores.append(RimScore(timestampMs: timestampMs, score: avgDiff))
        // Keep only last 5 seconds of history.
        let cutoff = timestampMs - 5000
        if let firstFresh = scores.firstIndex(where: { $0.timestampMs >= cutoff }) {
            if firstFresh > 0 { scores.removeFirst(firstFresh) }
        }
        return avgDiff
    }

    /// Forget state; used when the hoop is re-placed or the camera restarts.
    func reset() {
        previous = nil
        scores.removeAll()
    }
}
