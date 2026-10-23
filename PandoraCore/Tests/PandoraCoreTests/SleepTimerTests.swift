//
//  SleepTimerTests.swift
//  PandoraCoreTests
//
//  The sleep timer's deadline math and labels.
//

import XCTest
@testable import PandoraCore

final class SleepTimerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    func testDurationTimerExpiresAtDeadline() {
        let timer = SleepTimer(minutes: 15, now: now)
        XCTAssertFalse(timer.isOff)
        XCTAssertFalse(timer.hasExpired(now: now))
        XCTAssertFalse(timer.hasExpired(now: now.addingTimeInterval(14 * 60)))
        XCTAssertTrue(timer.hasExpired(now: now.addingTimeInterval(15 * 60)))
    }

    func testRemainingCountsDown() {
        let timer = SleepTimer(minutes: 10, now: now)
        XCTAssertEqual(timer.remaining(now: now), 600, accuracy: 0.001)
        XCTAssertEqual(timer.remaining(now: now.addingTimeInterval(240)), 360, accuracy: 0.001)
        XCTAssertEqual(timer.remaining(now: now.addingTimeInterval(9_000)), 0, accuracy: 0.001)
    }

    func testMinutesBelowOneAreClamped() {
        let timer = SleepTimer(minutes: 0, now: now)
        XCTAssertEqual(timer.minutes, 1)
        XCTAssertEqual(timer.remaining(now: now), 60, accuracy: 0.001)
    }

    func testEndOfTrackTimerHasNoDeadline() {
        let timer = SleepTimer(endOfTrack: true)
        XCTAssertEqual(timer.mode, .endOfTrack)
        XCTAssertFalse(timer.hasExpired(now: now))
        XCTAssertEqual(timer.remaining(now: now), 0)
    }

    func testFiredClearsTheTimer() {
        let timer = SleepTimer(minutes: 5, now: now)
        XCTAssertTrue(timer.fired().isOff)
    }

    func testOffTimerIsOff() {
        XCTAssertTrue(SleepTimer.off.isOff)
        XCTAssertFalse(SleepTimer.off.hasExpired(now: now))
        XCTAssertEqual(SleepTimer.off.label(now: now), "Off")
    }

    func testLabelRoundsUpRemainingMinutes() {
        let timer = SleepTimer(minutes: 15, now: now)
        XCTAssertEqual(timer.label(now: now), "15 min left")
        XCTAssertEqual(timer.label(now: now.addingTimeInterval(60)), "14 min left")
        XCTAssertEqual(timer.label(now: now.addingTimeInterval(15 * 60)), "Off")
    }

    func testEndOfTrackLabel() {
        XCTAssertEqual(SleepTimer(endOfTrack: true).label(now: now), "End of track")
    }

    func testCodableRoundTrip() throws {
        let timer = SleepTimer(minutes: 20, now: now)
        let data = try JSONEncoder().encode(timer)
        let restored = try JSONDecoder().decode(SleepTimer.self, from: data)
        XCTAssertEqual(restored.mode, timer.mode)
        XCTAssertEqual(restored.minutes, timer.minutes)
        XCTAssertEqual(restored.deadline, timer.deadline)
    }
}
