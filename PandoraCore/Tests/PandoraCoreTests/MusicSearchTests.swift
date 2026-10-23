//
//  MusicSearchTests.swift
//  PandoraCoreTests
//
//  `music.search` parsing (pithos filter ≥ 80 / genre pass-through / stable
//  score-desc order) and the SessionManager request shape.
//

import XCTest
@testable import PandoraCore

final class MusicSearchTests: XCTestCase {

    // MARK: - Parsing (pure)

    func testFiltersLowScoresAndSortsDescending() throws {
        let result = try envelopeResult(
            #"{"artists":[{"artistName":"Low","musicToken":"m1","score":70},{"artistName":"High","musicToken":"m2","score":90}],"#
            + #""songs":[{"songName":"Hit","artistName":"Band","musicToken":"m3","score":95},{"songName":"Edge","artistName":"B2","musicToken":"m4","score":80}],"#
            + #""genreStations":[{"stationName":"Rock","musicToken":"m5","score":50}]}"#
        )
        let hits = MusicSearchResult.searchResults(from: result)
        // ≥80 for artist/song; genre passes regardless of score.
        XCTAssertEqual(hits.map(\.musicToken), ["m3", "m2", "m4", "m5"])
        XCTAssertEqual(hits.map(\.kind), [.song, .artist, .song, .genre])
    }

    func testScoreTiesKeepArtistThenSongThenGenreOrder() throws {
        // Python's list.sort is stable; equal scores must preserve the
        // artists → songs → genreStations merge order.
        let result = try envelopeResult(
            #"{"artists":[{"artistName":"A","musicToken":"a","score":90}],"#
            + #""songs":[{"songName":"S","artistName":"X","musicToken":"s","score":90}],"#
            + #""genreStations":[{"stationName":"G","musicToken":"g","score":90}]}"#
        )
        let hits = MusicSearchResult.searchResults(from: result)
        XCTAssertEqual(hits.map(\.musicToken), ["a", "s", "g"])
    }

    func testFieldMappingPerKind() throws {
        let result = try envelopeResult(
            #"{"artists":[{"artistName":"Weezer","musicToken":"ma","score":88}],"#
            + #""songs":[{"songName":"Buddy Holly","artistName":"Weezer","musicToken":"ms","score":99}],"#
            + #""genreStations":[{"stationName":"90s Alternative","musicToken":"mg","score":10}]}"#
        )
        let hits = MusicSearchResult.searchResults(from: result)
        XCTAssertEqual(hits.count, 3)

        let artist = hits.first { $0.kind == .artist }
        XCTAssertEqual(artist?.title, "Weezer")
        XCTAssertNil(artist?.subtitle)

        let song = hits.first { $0.kind == .song }
        XCTAssertEqual(song?.title, "Buddy Holly")
        XCTAssertEqual(song?.subtitle, "Weezer")

        let genre = hits.first { $0.kind == .genre }
        XCTAssertEqual(genre?.title, "90s Alternative")
    }

    func testMalformedEntriesAreSkippedNotFatal() throws {
        // One field missing on each — pithos would KeyError; we drop the
        // entry and keep the well-formed one.
        let result = try envelopeResult(
            #"{"artists":[{"artistName":"NoToken","score":99},{"artistName":"OK","musicToken":"keep","score":85}],"#
            + #""songs":[{"songName":"NoScore","artistName":"X","musicToken":"t"}],"#
            + #""genreStations":[{"stationName":"NoToken","score":90}]}"#
        )
        let hits = MusicSearchResult.searchResults(from: result)
        XCTAssertEqual(hits.map(\.musicToken), ["keep"])
    }

    func testEmptyResultIsEmptyList() throws {
        let hits = MusicSearchResult.searchResults(from: try envelopeResult("{}"))
        XCTAssertEqual(hits, [])
    }

    // MARK: - Request shape (SessionManager)

    func testSearchSendsPithosParamsUnderRestoredSession() async throws {
        // Restore-from-store path: no login traffic, exactly one search call.
        let store = InMemorySessionStore(record: SessionRecord(
            credentials: Credentials(username: "u", password: "p"),
            tokens: SessionTokens(
                partnerId: "77",
                partnerAuthToken: "P-TOKEN",
                userId: "u-1",
                userAuthToken: "U-TOKEN",
                timeOffset: 0
            ),
            isSubscriber: true
        ))
        let transport = MockTransport(responses: [
            ok(#"{"artists":[{"artistName":"Weezer","musicToken":"m-1","score":91}],"songs":[],"genreStations":[]}"#)
        ])
        let manager = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: store,
            now: { Date(timeIntervalSince1970: 1_000_000_000) }
        )
        let restored = await manager.restore()
        XCTAssertTrue(restored)

        let hits = try await manager.search("weezer")
        XCTAssertEqual(hits.map(\.musicToken), ["m-1"])

        let requests = transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.url.absoluteString.contains("method=music.search"))
        XCTAssertTrue(request.url.absoluteString.contains("auth_token=U-TOKEN"))

        // Encrypted body: pithos' exact param set, NUL-pad trimmed.
        let hex = String(decoding: request.body, as: UTF8.self)
        let plain = try PandoraCrypto.decryptFromHex(hex, key: PandoraAPI.encryptKey)
        let body = String(decoding: plain.prefix { $0 != 0 }, as: UTF8.self)
        XCTAssertTrue(body.contains(#""includeGenreStations":true"#), body)
        XCTAssertTrue(body.contains(#""includeNearMatches":true"#), body)
        XCTAssertTrue(body.contains(#""searchText":"weezer""#), body)
    }

    // MARK: - Helpers

    private func envelopeResult(_ objectJSON: String) throws -> [String: AnyJSON] {
        let envelope = Data(#"{"stat":"ok","result":\#(objectJSON)}"#.utf8)
        return try ResponseEnvelope.result(from: envelope)
    }

    private func ok(_ resultObjectJSON: String) -> Result<Data, Error> {
        .success(Data("{\"stat\":\"ok\",\"result\":\(resultObjectJSON)}".utf8))
    }
}
