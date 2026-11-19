//
//  BoundedCacheTests.swift
//  PandoraCoreTests
//
//  The lyrics cache's bound. These vectors pin the eviction order:
//  least recently used falls off first, and a read or an update counts
//  as a use — the songs the user revisits survive, the once-heard ones
//  go.
//

import XCTest
@testable import PandoraCore

final class BoundedCacheTests: XCTestCase {

    func testStoresAndReturnsValues() {
        var cache = BoundedCache<String, Int>(capacity: 3)
        cache["a"] = 1
        XCTAssertEqual(cache["a"], 1)
        XCTAssertEqual(cache.count, 1)
        XCTAssertFalse(cache.isEmpty)
    }

    func testReadingAMissingKeyReturnsNil() {
        var cache = BoundedCache<String, Int>(capacity: 3)
        XCTAssertNil(cache["missing"])
        XCTAssertTrue(cache.isEmpty)
    }

    func testTheLeastRecentlyUsedEntryIsEvictedFirst() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache["a"] = 1
        cache["b"] = 2
        cache["c"] = 3
        XCTAssertNil(cache["a"], "the oldest entry should have been evicted")
        XCTAssertEqual(cache["b"], 2)
        XCTAssertEqual(cache["c"], 3)
        XCTAssertEqual(cache.count, 2)
    }

    func testAReadRefreshesRecency() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache["a"] = 1
        cache["b"] = 2
        _ = cache["a"] // a use: a is the most recently used now
        cache["c"] = 3
        XCTAssertEqual(cache["a"], 1, "a read entry should survive the eviction")
        XCTAssertNil(cache["b"])
        XCTAssertEqual(cache["c"], 3)
    }

    func testAnUpdateRefreshesRecencyAndKeepsTheNewValue() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache["a"] = 1
        cache["b"] = 2
        cache["a"] = 10
        cache["c"] = 3
        XCTAssertEqual(cache["a"], 10)
        XCTAssertNil(cache["b"])
    }

    func testOverwritingDoesNotGrowTheCache() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache["a"] = 1
        cache["a"] = 2
        cache["a"] = 3
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache["a"], 3)
    }

    func testAssigningNilRemovesTheEntry() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache["a"] = 1
        cache["a"] = nil
        XCTAssertNil(cache["a"])
        XCTAssertTrue(cache.isEmpty)
    }

    func testACapacityBelowOneIsClampedToOne() {
        var cache = BoundedCache<String, Int>(capacity: 0)
        cache["a"] = 1
        cache["b"] = 2
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache["b"], 2, "only the most recent entry survives")
        XCTAssertNil(cache["a"])
    }

    func testRemoveAllEmptiesTheCache() {
        var cache = BoundedCache<String, Int>(capacity: 3)
        cache["a"] = 1
        cache["b"] = 2
        cache.removeAll()
        XCTAssertTrue(cache.isEmpty)
        XCTAssertNil(cache["a"])
        // ...and the cache still works afterwards.
        cache["c"] = 3
        XCTAssertEqual(cache["c"], 3)
        XCTAssertEqual(cache.count, 1)
    }

    func testEvictionKeepsWorkingAcrossManyInsertions() {
        var cache = BoundedCache<String, Int>(capacity: 3)
        for index in 0..<100 {
            cache["key\(index)"] = index
        }
        XCTAssertEqual(cache.count, 3)
        XCTAssertNil(cache["key0"])
        XCTAssertNil(cache["key96"])
        XCTAssertEqual(cache["key97"], 97)
        XCTAssertEqual(cache["key98"], 98)
        XCTAssertEqual(cache["key99"], 99)
    }
}
