//
//  DiskCacheBoundsTests.swift
//  PandoraCoreTests
//
//  The eviction rule for the disk tier. These vectors pin the two
//  decisions that matter: what gets removed (oldest first) and what
//  survives (everything under the ceiling).
//

import XCTest
@testable import PandoraCore

final class DiskCacheBoundsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(
        _ name: String,
        bytes: Int,
        age: TimeInterval
    ) -> DiskCacheBounds.Entry {
        DiskCacheBounds.Entry(
            name: name,
            byteCount: bytes,
            modifiedAt: now.addingTimeInterval(-age)
        )
    }

    // MARK: - The size ceiling

    func testUnderTheCeilingNothingIsRemoved() {
        let bounds = DiskCacheBounds(byteLimit: 1000)
        let entries = [
            entry("a", bytes: 300, age: 10),
            entry("b", bytes: 300, age: 20)
        ]
        XCTAssertTrue(bounds.evictionPlan(entries: entries, now: now).isEmpty)
    }

    func testExactlyAtTheCeilingNothingIsRemoved() {
        let bounds = DiskCacheBounds(byteLimit: 600)
        let entries = [
            entry("a", bytes: 300, age: 10),
            entry("b", bytes: 300, age: 20)
        ]
        XCTAssertTrue(bounds.evictionPlan(entries: entries, now: now).isEmpty)
    }

    func testOverTheCeilingTheOldestGoesFirst() {
        let bounds = DiskCacheBounds(byteLimit: 600)
        let entries = [
            entry("new", bytes: 300, age: 10),
            entry("middle", bytes: 300, age: 100),
            entry("old", bytes: 300, age: 200)
        ]
        let plan = bounds.evictionPlan(entries: entries, now: now)
        XCTAssertEqual(plan.map(\.name), ["old"])
    }

    func testEvictionContinuesUntilTheCacheIsUnderTheCeiling() {
        let bounds = DiskCacheBounds(byteLimit: 500)
        let entries = [
            entry("newest", bytes: 200, age: 10),
            entry("middle", bytes: 200, age: 100),
            entry("oldest", bytes: 200, age: 200),
            entry("oldest2", bytes: 200, age: 300)
        ]
        let plan = bounds.evictionPlan(entries: entries, now: now)
        // 800 bytes over a 500-byte ceiling: the two oldest go (400
        // bytes), leaving 400 — under the ceiling.
        XCTAssertEqual(plan.map(\.name), ["oldest2", "oldest"])
    }

    func testEqualDatesAreBrokenByName() {
        let bounds = DiskCacheBounds(byteLimit: 100)
        let sameDate = now.addingTimeInterval(-50)
        let entries = [
            DiskCacheBounds.Entry(name: "zebra", byteCount: 100, modifiedAt: sameDate),
            DiskCacheBounds.Entry(name: "alpha", byteCount: 100, modifiedAt: sameDate)
        ]
        let plan = bounds.evictionPlan(entries: entries, now: now)
        XCTAssertEqual(plan.map(\.name), ["alpha"])
    }

    func testAZeroCeilingDoesNotBoundTheCacheBySize() {
        let bounds = DiskCacheBounds(byteLimit: 0)
        let entries = [entry("a", bytes: 10_000_000, age: 10)]
        XCTAssertTrue(bounds.evictionPlan(entries: entries, now: now).isEmpty)
    }

    // MARK: - The age ceiling

    func testExpiredFilesGoWhateverTheirSize() {
        let bounds = DiskCacheBounds(byteLimit: 10_000_000, maxAge: 100)
        let entries = [
            entry("fresh", bytes: 10, age: 50),
            entry("stale", bytes: 10, age: 500)
        ]
        let plan = bounds.evictionPlan(entries: entries, now: now)
        XCTAssertEqual(plan.map(\.name), ["stale"])
    }

    func testAFileExactlyAtTheAgeCeilingIsStillInDate() {
        let bounds = DiskCacheBounds(byteLimit: 10_000_000, maxAge: 100)
        let entries = [entry("edge", bytes: 10, age: 100)]
        XCTAssertTrue(bounds.evictionPlan(entries: entries, now: now).isEmpty)
        XCTAssertFalse(bounds.isExpired(entries[0], now: now))
    }

    func testTheAgeRuleAlsoAppliesWithoutASizeCeiling() {
        let bounds = DiskCacheBounds(byteLimit: 0, maxAge: 100)
        let entries = [entry("stale", bytes: 10, age: 500)]
        XCTAssertEqual(bounds.evictionPlan(entries: entries, now: now).map(\.name), ["stale"])
    }

    func testAnExpiredFileDoesNotForceAnExtraRemoval() {
        // 600 bytes, a 500-byte ceiling, and one expired file: removing
        // the expired 100 bytes already brings the cache under the
        // ceiling, so the fresh files stay.
        let bounds = DiskCacheBounds(byteLimit: 500, maxAge: 100)
        let entries = [
            entry("fresh", bytes: 250, age: 10),
            entry("alsoFresh", bytes: 250, age: 20),
            entry("stale", bytes: 100, age: 500)
        ]
        let plan = bounds.evictionPlan(entries: entries, now: now)
        XCTAssertEqual(plan.map(\.name), ["stale"])
    }

    // MARK: - The totals and the trigger

    func testTotalBytesAddsUpTheCache() {
        let entries = [
            entry("a", bytes: 120, age: 10),
            entry("b", bytes: 80, age: 20)
        ]
        XCTAssertEqual(DiskCacheBounds.totalBytes(of: entries), 200)
    }

    func testANegativeByteCountCountsAsZero() {
        let entries = [entry("a", bytes: -50, age: 10)]
        XCTAssertEqual(DiskCacheBounds.totalBytes(of: entries), 0)
    }

    func testNeedsSweepIsFalseForACacheInsideItsBounds() {
        let bounds = DiskCacheBounds(byteLimit: 1000, maxAge: 100)
        XCTAssertFalse(
            bounds.needsSweep(
                totalBytes: 500,
                oldestModifiedAt: now.addingTimeInterval(-50),
                now: now
            )
        )
    }

    func testNeedsSweepIsTrueOverTheSizeCeiling() {
        let bounds = DiskCacheBounds(byteLimit: 1000, maxAge: 100)
        XCTAssertTrue(
            bounds.needsSweep(
                totalBytes: 1001,
                oldestModifiedAt: now.addingTimeInterval(-50),
                now: now
            )
        )
    }

    func testNeedsSweepIsTrueWhenTheOldestFileHasExpired() {
        let bounds = DiskCacheBounds(byteLimit: 1000, maxAge: 100)
        XCTAssertTrue(
            bounds.needsSweep(
                totalBytes: 500,
                oldestModifiedAt: now.addingTimeInterval(-500),
                now: now
            )
        )
    }

    func testNeedsSweepIsFalseForAnEmptyCache() {
        let bounds = DiskCacheBounds(byteLimit: 1000, maxAge: 100)
        XCTAssertFalse(bounds.needsSweep(totalBytes: 0, oldestModifiedAt: nil, now: now))
    }
}
