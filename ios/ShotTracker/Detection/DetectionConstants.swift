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
    static let shotZoneAbove = 0.25
    static let shotZoneSide: Double = 2.0
    static let missTimeoutMs: Double = 3000
    static let ballLostMissMs: Double = 3500
    static let cooldownMs: Double = 4000

    // Color detector
    static let colorW = 360
    static let colorH = 320
    static let bgFramesNeeded = 8
    static let bgStaticFractionThreshold = 0.4
}
