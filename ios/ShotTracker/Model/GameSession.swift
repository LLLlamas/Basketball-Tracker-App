import Foundation
import CoreGraphics

struct Shot: Identifiable, Hashable {
    let id = UUID()
    let made: Bool
    let timestamp: Date
    let auto: Bool
}

struct BallSample: Hashable {
    let position: CGPoint   // normalized 0...1, top-left origin
    let radius: CGFloat     // normalized
    let timestamp: TimeInterval
    let confidence: Float
}

/// Observable session state. Placeholder for Phase 0 — filled in during Phase 2 (classifier).
@Observable
final class GameSession {
    var hoop: CGPoint? = nil        // normalized 0...1
    var hoopPlacementActive = false
    var shots: [Shot] = []
    var ballTrail: [BallSample] = []

    var makes: Int { shots.filter(\.made).count }
    var misses: Int { shots.count - makes }
    var fieldGoalPct: Double {
        guard !shots.isEmpty else { return 0 }
        return Double(makes) / Double(shots.count)
    }

    var hoopPlaced: Bool { hoop != nil }

    func logMake(auto: Bool = false) {
        shots.append(Shot(made: true, timestamp: Date(), auto: auto))
    }

    func logMiss(auto: Bool = false) {
        shots.append(Shot(made: false, timestamp: Date(), auto: auto))
    }

    func undoLast() {
        _ = shots.popLast()
    }

    func reset() {
        shots.removeAll()
        ballTrail.removeAll()
    }
}
