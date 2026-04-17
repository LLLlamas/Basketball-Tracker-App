import Foundation

/// Ported verbatim from `index.html`'s top-of-file constants. These values are
/// experimentally tuned — changing them will shift detection sensitivity.
enum DetectionConstants {
    // Rim disruption
    static let disruptSize = 64
    static let disruptMakeThreshold: Double = 8
    static let disruptCooldownMs: Double = 3500
    static let staticThreshold = 5
    static let staticMoveFrac = 0.04

    // Shot zone / classifier
    static let hoopRadiusNormalized = 0.09
    static let shotZoneAbove = 0.18
    static let shotZoneSide: Double = 1.4
    static let missTimeoutMs: Double = 3000
    static let ballLostMissMs: Double = 3500
    static let cooldownMs: Double = 4000

    // Ball-gating for rim-disruption makes: a disruption-only "make" is only
    // accepted if a ball sample was seen within this window and within this
    // multiple of the hoop radius from the hoop center.
    static let disruptBallRecencyMs: Double = 1500
    static let disruptBallRadiusMult: Double = 2.5

    // Attempt entry: ball must be moving downward (and toward the hoop) before
    // a shot attempt is opened. Held/dribbled balls near the hoop no longer
    // trigger false attempts.
    static let attemptMinDownwardDy: Double = 0.006  // normalized y per sample step

    // Color detector
    static let colorW = 360
    static let colorH = 320
    static let bgFramesNeeded = 8
    static let bgStaticFractionThreshold = 0.4
    // Motion gating: sum of |dR|+|dG|+|dB| for a pixel vs the previous downsampled
    // frame must exceed this to count as "moving". Rejects static orange/tan
    // objects (skin, court lines, cones, drawn UI) that the color rules alone
    // would false-positive on. Low enough that ball-at-arc-peak still passes.
    static let colorMotionDiffThreshold = 12
}
