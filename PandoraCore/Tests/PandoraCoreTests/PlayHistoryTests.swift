//
//  PlayHistoryTests.swift
//  PandoraCoreTests
//
//  The bounded, newest-first playback history.
//

import XCTest
@testable import PandoraCore

final class PlayHistoryTests: XCTestCase {

    private func track(_ token: String, title: String = "Song") -> Track {
        Track(
            trackToken: token,
            title: title,
            artist: "Artist",
            album: "Album",
            duration: 200,
            stationId: "1"
        )
    }

    func testRecordPutsNewestFirst() {
        var history = PlayHistory()
        history.record(track("A"), at: Date(timeIntervalSince1970: 100))
        history.record(track("B"), at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(history.entries.map(\.trackToken), ["B", "A"])
        XCTAssertEqual(history.entries[0].playedAt, Date(timeIntervalSince1970: 200))
    }

    func testRepeatedTrackMovesToFrontInsteadOfDuplicating() {
        var history = PlayHistory()
        history.record(track("A"))
        history.record(track("B"))
        history.record(track("A"))
        XCTAssertEqual(history.entries.map(\.trackToken), ["A", "B"])
        XCTAssertEqual(history.entries.count, 2)
    }

    func testCapacityDropsOldestEntries() {
        var history = PlayHistory(capacity: 3)
        for index in 0..<5 {
            history.record(track("T\(index)"))
        }
        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.entries.map(\.trackToken), ["T4", "T3", "T2"])
    }

    func testEntryCarriesTrackMetadata() {
        var history = PlayHistory()
        history.record(track("A", title: "Hit"))
        let entry = try? XCTUnwrap(history.entries.first)
        XCTAssertEqual(entry?.title, "Hit")
        XCTAssertEqual(entry?.artist, "Artist")
        XCTAssertEqual(entry?.album, "Album")
    }

    func testCodableRoundTrip() throws {
        var history = PlayHistory()
        history.record(track("A"), at: Date(timeIntervalSince1970: 123))
        let data = try JSONEncoder().encode(history)
        let restored = try JSONDecoder().decode(PlayHistory.self, from: data)
        XCTAssertEqual(restored, history)
    }
}
