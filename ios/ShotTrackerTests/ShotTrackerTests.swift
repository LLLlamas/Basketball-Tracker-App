import XCTest
@testable import ShotTracker

final class ShotTrackerTests: XCTestCase {
    @MainActor
    func testLogMakeIncrementsMakes() {
        let session = GameSession()
        session.logMake()
        XCTAssertEqual(session.makes, 1)
        XCTAssertEqual(session.misses, 0)
    }

    @MainActor
    func testFieldGoalPctEmptyIsZero() {
        let session = GameSession()
        XCTAssertEqual(session.fieldGoalPct, 0)
    }

    @MainActor
    func testUndoRemovesLastShot() {
        let session = GameSession()
        session.logMake()
        session.logMiss()
        session.undoLast()
        XCTAssertEqual(session.shots.count, 1)
        XCTAssertEqual(session.makes, 1)
    }
}
