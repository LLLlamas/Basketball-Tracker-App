import XCTest
import CoreGraphics
@testable import ShotTracker

final class ShotTrackerTests: XCTestCase {
    @MainActor
    func testLogAutoMakeIncrementsMakes() {
        let session = GameSession()
        session.logAutoMake(reason: "net")
        XCTAssertEqual(session.makes, 1)
        XCTAssertEqual(session.misses, 0)
        XCTAssertEqual(session.streak, 1)
    }

    @MainActor
    func testFieldGoalPctEmptyIsZero() {
        let session = GameSession()
        XCTAssertEqual(session.fieldGoalPct, 0)
    }

    @MainActor
    func testUndoRemovesLastShot() {
        let session = GameSession()
        session.logAutoMake(reason: "net")
        session.logAutoMiss(reason: "lost")
        session.undoLast()
        XCTAssertEqual(session.shots.count, 1)
        XCTAssertEqual(session.makes, 1)
    }

    @MainActor
    func testStreakGoesNegativeOnMisses() {
        let session = GameSession()
        session.logAutoMiss(reason: "lost")
        session.logAutoMiss(reason: "lost")
        XCTAssertEqual(session.streak, -2)
    }
}

final class IsBallColorTests: XCTestCase {
    func testBrightOrangeIsBall() {
        // Classic basketball orange
        XCTAssertTrue(ColorBallDetector.isBallColor(r: 220, g: 110, b: 50))
    }

    func testPureWhiteIsNot() {
        XCTAssertFalse(ColorBallDetector.isBallColor(r: 255, g: 255, b: 255))
    }

    func testPureBlueIsNot() {
        XCTAssertFalse(ColorBallDetector.isBallColor(r: 20, g: 40, b: 220))
    }

    func testGrassGreenIsNot() {
        XCTAssertFalse(ColorBallDetector.isBallColor(r: 60, g: 130, b: 40))
    }
}
