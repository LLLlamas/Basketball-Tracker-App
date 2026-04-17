import Foundation
import CoreGraphics

/// Shot decision (made or missed) with timestamp.
struct ShotOutcome {
    enum Kind { case make, miss }
    let kind: Kind
    let reason: String       // debug tag: "net", "zone", "lost"
    let timestampMs: Double
}

/// State-machine port of `checkMake`, `classifyShotAttempt`, `checkDisruptionMake`,
/// `checkBallLostMiss` from index.html. Given rim disruption scores + ball trail +
/// placed hoop, produces `ShotOutcome`s.
final class ShotClassifier {
    /// Rolling ball trail, normalized coordinates.
    private(set) var trail: [BallSample] = []

    private var shotAttempt: Attempt?
    private var lastAutoTsMs: Double = 0
    private var lastDisruptMakeTsMs: Double = 0

    private struct Attempt {
        var startTsMs: Double
        var resolved: Bool = false
        var ballBelowCenter: Bool = false
        var ballGone: Bool = false
        var goneTsMs: Double = 0
        var peakRim: Double = 0
    }

    /// Feed a ball observation. Nil means the ball wasn't seen this tick.
    func noteBall(_ ball: DetectedBall?) {
        guard let ball else { return }
        let sample = BallSample(
            position: ball.positionNormalized,
            radius: ball.radiusNormalized,
            timestamp: ball.timestampMs / 1000.0,
            confidence: Float(ball.confidence)
        )
        trail.append(sample)
        // Keep last 2.5s, max 60 samples.
        let cutoff = (ball.timestampMs - 2500) / 1000.0
        if let firstFresh = trail.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstFresh > 0 { trail.removeFirst(firstFresh) }
        }
        if trail.count > 60 { trail.removeFirst(trail.count - 60) }
    }

    /// Run the classifier given the current time, hoop, and recent rim scores.
    /// Returns an outcome if one was reached this tick.
    func tick(nowMs: Double, hoop: CGPoint?, rimScores: [RimScore]) -> ShotOutcome? {
        guard let hoop else { return nil }

        if let outcome = checkDisruptionMake(nowMs: nowMs, rimScores: rimScores) {
            return outcome
        }
        if let outcome = checkMake(nowMs: nowMs, hoop: hoop, rimScores: rimScores) {
            return outcome
        }
        if let outcome = checkBallLostMiss(nowMs: nowMs, rimScores: rimScores) {
            return outcome
        }
        return nil
    }

    func reset() {
        trail.removeAll()
        shotAttempt = nil
        lastAutoTsMs = 0
        lastDisruptMakeTsMs = 0
    }

    // MARK: - Make: direct rim disruption

    private func checkDisruptionMake(nowMs: Double, rimScores: [RimScore]) -> ShotOutcome? {
        if nowMs - lastAutoTsMs < DetectionConstants.cooldownMs { return nil }
        if nowMs - lastDisruptMakeTsMs < DetectionConstants.disruptCooldownMs { return nil }
        if rimScores.count < 5 { return nil }

        let recent = rimScores.filter { nowMs - $0.timestampMs < 600 }
        if recent.count < 2 { return nil }
        let peak = recent.map(\.score).max() ?? 0
        if peak > 20 { return nil }  // person near hoop, not a shot

        let baseline = rimScores.filter { nowMs - $0.timestampMs > 1500 && nowMs - $0.timestampMs < 4500 }
        let baseAvg: Double = baseline.count > 2
            ? baseline.map(\.score).reduce(0, +) / Double(baseline.count)
            : 2

        let dynThreshold = max(3.8, baseAvg * 2.5)
        guard peak > dynThreshold else { return nil }

        // Reject sustained camera shake.
        let last10 = rimScores.suffix(10)
        let highCount = last10.filter { $0.score > dynThreshold * 0.6 }.count
        if highCount > 6 { return nil }

        lastDisruptMakeTsMs = nowMs
        lastAutoTsMs = nowMs
        shotAttempt = nil
        return ShotOutcome(kind: .make, reason: "net", timestampMs: nowMs)
    }

    // MARK: - Shot attempt tracking

    private func checkMake(nowMs: Double, hoop: CGPoint, rimScores: [RimScore]) -> ShotOutcome? {
        if nowMs - lastAutoTsMs < DetectionConstants.cooldownMs { return nil }
        guard trail.count >= 2 else { return nil }

        let hr = CGFloat(DetectionConstants.hoopRadiusNormalized)
        let recent = trail.filter { (nowMs / 1000.0) - $0.timestamp < 2.0 }
        guard let lastPt = recent.last else { return nil }

        let dx = abs(lastPt.position.x - hoop.x)
        let dy = lastPt.position.y - hoop.y
        // In-zone check (all in normalized units: canvas width == 1, height == 1).
        let inShotZone =
            dx < hr * CGFloat(DetectionConstants.shotZoneSide) &&
            dy < hr * 3 &&
            dy > -CGFloat(DetectionConstants.shotZoneAbove)

        if inShotZone && shotAttempt == nil {
            shotAttempt = Attempt(startTsMs: nowMs)
        }

        guard var attempt = shotAttempt, !attempt.resolved else { return nil }
        let elapsed = nowMs - attempt.startTsMs

        // Peak rim score during attempt.
        let shotRim = rimScores.filter { $0.timestampMs >= attempt.startTsMs && $0.timestampMs <= nowMs }
        let peakDuringShot = shotRim.map(\.score).max() ?? 0
        if peakDuringShot > attempt.peakRim { attempt.peakRim = peakDuringShot }

        // Ball positionally below-center of hoop?
        let ballJustBelow = lastPt.position.y > hoop.y - hr * 0.5 && lastPt.position.y < hoop.y + hr * 2.5
        let ballCentered = abs(lastPt.position.x - hoop.x) < hr * 1.2
        let prevPt = recent.count >= 2 ? recent[recent.count - 2] : nil
        let prevNearHoop = prevPt.map { $0.position.y > hoop.y - hr * 0.5 } ?? true
        if ballJustBelow && ballCentered && prevNearHoop && elapsed > 150 {
            attempt.ballBelowCenter = true
        }

        // Ball has clearly left the zone.
        let ballFarBelow = lastPt.position.y > hoop.y + hr * 4
        let ballFarSide = dx > hr * CGFloat(DetectionConstants.shotZoneSide) * 1.8
        if (ballFarBelow || ballFarSide) && elapsed > 300 && !attempt.ballGone {
            attempt.ballGone = true
            attempt.goneTsMs = nowMs
        }

        shotAttempt = attempt

        let goneWaited = attempt.ballGone && (nowMs - attempt.goneTsMs) > 1500
        if goneWaited || elapsed > DetectionConstants.missTimeoutMs {
            let isMake = classify(attempt: attempt, nowMs: nowMs, rimScores: rimScores)
            lastAutoTsMs = nowMs
            shotAttempt = nil
            return ShotOutcome(
                kind: isMake ? .make : .miss,
                reason: isMake ? "zone" : "miss",
                timestampMs: nowMs
            )
        }
        return nil
    }

    // MARK: - Miss: ball lost

    private func checkBallLostMiss(nowMs: Double, rimScores: [RimScore]) -> ShotOutcome? {
        guard var attempt = shotAttempt, !attempt.resolved else { return nil }
        if nowMs - lastAutoTsMs < DetectionConstants.cooldownMs { return nil }
        guard let lastTrailPt = trail.last else { return nil }
        let ballLastSeenMs = lastTrailPt.timestamp * 1000.0
        if nowMs - ballLastSeenMs > DetectionConstants.ballLostMissMs {
            let isMake = classify(attempt: attempt, nowMs: nowMs, rimScores: rimScores)
            attempt.resolved = true
            shotAttempt = nil
            lastAutoTsMs = nowMs
            return ShotOutcome(
                kind: isMake ? .make : .miss,
                reason: isMake ? "zone" : "lost",
                timestampMs: nowMs
            )
        }
        return nil
    }

    // MARK: - Classifier

    private func classify(attempt: Attempt, nowMs: Double, rimScores: [RimScore]) -> Bool {
        let windowStart = attempt.startTsMs - 500
        let windowEnd = nowMs + 2000
        let shotRim = rimScores.filter { $0.timestampMs >= windowStart && $0.timestampMs <= windowEnd }
        let peakDuringShot = shotRim.map(\.score).max() ?? 0

        let baselineStart = windowStart - 5000
        let baselineEnd = windowStart - 500
        let baselineRim = rimScores.filter { $0.timestampMs > baselineStart && $0.timestampMs < baselineEnd }
        let baseAvg: Double = baselineRim.count > 2
            ? baselineRim.map(\.score).reduce(0, +) / Double(baselineRim.count)
            : 1.5

        let highFramesThreshold = max(3.5, baseAvg * 2)
        let highFrames = shotRim.filter { $0.score > highFramesThreshold }
        let isBrief = highFrames.count <= 6
        let isReasonable = peakDuringShot < 20

        let dynThreshold = max(3.8, baseAvg * 2.5)
        if peakDuringShot > dynThreshold && isBrief && isReasonable { return true }
        if attempt.ballBelowCenter { return true }
        return false
    }
}
