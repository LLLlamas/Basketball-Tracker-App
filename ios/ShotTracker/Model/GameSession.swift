import Foundation
import CoreGraphics

struct Shot: Identifiable, Hashable {
    let id = UUID()
    let made: Bool
    let timestamp: Date
    let auto: Bool
}

struct BallSample: Hashable {
    let position: CGPoint    // normalized 0...1, top-left origin
    let radius: CGFloat      // normalized
    let timestamp: TimeInterval
    let confidence: Float
}

/// Main shared state. `@MainActor` because all reads happen from SwiftUI.
/// Detection writes via `logAutoShot` are dispatched here from the background
/// frame-processing queue.
@MainActor
final class GameSession: ObservableObject {
    @Published var hoop: CGPoint? = nil          // normalized 0...1
    @Published var hoopPlacementActive = true
    @Published private(set) var shots: [Shot] = []
    @Published var ballTrail: [BallSample] = []
    @Published var lastEvent: ShotEvent? = nil

    var makes: Int { shots.filter(\.made).count }
    var misses: Int { shots.count - makes }
    var totalAttempts: Int { shots.count }
    var fieldGoalPct: Double {
        guard !shots.isEmpty else { return 0 }
        return Double(makes) / Double(shots.count)
    }

    /// Current streak (made in a row if positive, missed in a row if negative).
    var streak: Int {
        guard let last = shots.last else { return 0 }
        var n = 0
        for shot in shots.reversed() {
            if shot.made == last.made {
                n += 1
            } else { break }
        }
        return last.made ? n : -n
    }

    var hoopPlaced: Bool { hoop != nil }

    /// Transient banner/toast shown after a shot is logged; auto-clears.
    struct ShotEvent: Equatable, Identifiable {
        let id = UUID()
        let made: Bool
        let message: String
        let timestamp: Date
    }

    func placeHoop(_ point: CGPoint) {
        hoop = point
        hoopPlacementActive = false
    }

    func startHoopPlacement() {
        hoop = nil
        hoopPlacementActive = true
    }

    func logAutoMake(reason: String) {
        let msg = reason == "net" ? "Swish!" : "Make!"
        append(Shot(made: true, timestamp: Date(), auto: true),
               event: ShotEvent(made: true, message: msg, timestamp: Date()))
    }

    func logAutoMiss(reason: String) {
        let msg = reason == "lost" ? "Miss" : "Miss"
        append(Shot(made: false, timestamp: Date(), auto: true),
               event: ShotEvent(made: false, message: msg, timestamp: Date()))
    }

    func undoLast() {
        _ = shots.popLast()
    }

    func reset() {
        shots.removeAll()
        ballTrail.removeAll()
        lastEvent = nil
    }

    private func append(_ shot: Shot, event: ShotEvent) {
        shots.append(shot)
        lastEvent = event
    }
}
