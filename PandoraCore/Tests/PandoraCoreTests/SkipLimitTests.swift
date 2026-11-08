//
//  SkipLimitTests.swift
//  PandoraCoreTests
//
//  Pandora's daily skip limit. The legacy API signals it by fault
//  **message** on `station.getPlaylist`, not by a numeric code — the
//  reference (Elpis `Libs/PandoraSharp/Station.cs:232`) compares the
//  exception message against "PLAYLIST_END" and
//  "DAILY_SKIP_LIMIT_REACHED", and pithos has no special case at all
//  (its `json_call` raises `ApiError` carrying the server's message).
//
//  The core turns those faults into a typed `PlaylistError`, so the app
//  can tell the user what happened and stop asking — AGENTS.md:
//  "Respect skip limits and rate limits. Never hammer the API."
//

import XCTest
@testable import PandoraCore

final class SkipLimitTests: XCTestCase {

    // MARK: - Fixtures

    private static let clock: @Sendable () -> Date = {
        Date(timeIntervalSince1970: 1_000_000_000)
    }

    /// A station to request a playlist for.
    private func makeStation() -> Station {
        Station(
            id: "1",
            token: "S1",
            name: "Deep Cuts",
            isShared: false,
            isQuickMix: false
        )
    }

    /// A fail envelope with proper string escaping.
    private func fail(code: Int, message: String) -> Result<Data, Error> {
        .success(JSONValue.encoded([
            "stat": .string("fail"),
            "code": .int(code),
            "message": .string(message)
        ]))
    }

    /// A restored session — no login traffic, so the first response is
    /// the playlist request's.
    private func makeManager(transport: MockTransport) -> SessionManager {
        let store = InMemorySessionStore(record: SessionRecord(
            credentials: Credentials(username: "me@example.com", password: "hunter2"),
            tokens: SessionTokens(
                partnerId: "77",
                partnerAuthToken: "P-TOKEN",
                userId: "u-1",
                userAuthToken: "U-LISTED",
                timeOffset: 760_000_000
            ),
            isSubscriber: false
        ))
        return SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: store,
            now: Self.clock
        )
    }

    // MARK: - Message detection

    func testDailySkipLimitMessageIsRecognised() {
        let error = PandoraAPIError(code: 1004, message: "DAILY_SKIP_LIMIT_REACHED")
        XCTAssertTrue(error.isSkipLimitReached)
        XCTAssertFalse(error.isPlaylistEnd)
    }

    func testPlaylistEndMessageIsRecognised() {
        let error = PandoraAPIError(code: 1004, message: "PLAYLIST_END")
        XCTAssertTrue(error.isSkipLimitReached)
        XCTAssertTrue(error.isPlaylistEnd)
    }

    func testSkipLimitDetectionToleratesCaseAndWhitespace() {
        let error = PandoraAPIError(code: 1004, message: "  daily_skip_limit_reached \n")
        XCTAssertTrue(error.isSkipLimitReached)
    }

    func testSkipLimitDetectionAcceptsAMessageWithContext() {
        // The server may append its own sentence to the token.
        let error = PandoraAPIError(
            code: 1004,
            message: "DAILY_SKIP_LIMIT_REACHED: try again tomorrow"
        )
        XCTAssertTrue(error.isSkipLimitReached)
    }

    func testUnrelatedFaultsAreNotSkipLimits() {
        let expired = PandoraAPIError(code: 1001, message: "Invalid auth token")
        XCTAssertFalse(expired.isSkipLimitReached)
        XCTAssertFalse(expired.isPlaylistEnd)

        let other = PandoraAPIError(code: 1039, message: "Too many playlist requests")
        XCTAssertFalse(other.isSkipLimitReached)
        XCTAssertFalse(other.isPlaylistEnd)
    }

    // MARK: - Typed mapping

    func testGetPlaylistMapsDailySkipLimitToTypedError() async throws {
        let transport = MockTransport(responses: [
            fail(code: 1004, message: "DAILY_SKIP_LIMIT_REACHED")
        ])
        let subject = makeManager(transport: transport)
        let restored = await subject.restore()
        XCTAssertTrue(restored)

        do {
            _ = try await subject.getPlaylist(for: makeStation())
            XCTFail("expected the skip limit to be surfaced")
        } catch let error as PlaylistError {
            XCTAssertEqual(error, .skipLimitReached(playlistEnded: false))
        }
    }

    func testGetPlaylistMapsPlaylistEndToTypedError() async throws {
        let transport = MockTransport(responses: [
            fail(code: 1004, message: "PLAYLIST_END")
        ])
        let subject = makeManager(transport: transport)
        let restored = await subject.restore()
        XCTAssertTrue(restored)

        do {
            _ = try await subject.getPlaylist(for: makeStation())
            XCTFail("expected the skip limit to be surfaced")
        } catch let error as PlaylistError {
            XCTAssertEqual(error, .skipLimitReached(playlistEnded: true))
        }
    }

    func testPlaylistEndedAccessorDistinguishesTheTwoSignals() {
        XCTAssertTrue(PlaylistError.skipLimitReached(playlistEnded: true).playlistEnded)
        XCTAssertFalse(PlaylistError.skipLimitReached(playlistEnded: false).playlistEnded)
    }

    func testOtherPlaylistFaultsStayAPandoraAPIError() async throws {
        let transport = MockTransport(responses: [
            fail(code: 1039, message: "Too many playlist requests")
        ])
        let subject = makeManager(transport: transport)
        let restored = await subject.restore()
        XCTAssertTrue(restored)

        do {
            _ = try await subject.getPlaylist(for: makeStation())
            XCTFail("expected the fault to propagate")
        } catch let error as PandoraAPIError {
            XCTAssertEqual(error.code, 1039)
            XCTAssertFalse(error.isSkipLimitReached)
        }
    }

    func testSkipLimitIsNotRetried() async throws {
        // The request must be made exactly once: the server refuses it,
        // and hammering it would only deepen the limit. (Compare with
        // the 1001 contract, where one replay is correct.)
        let transport = MockTransport(responses: [
            fail(code: 1004, message: "DAILY_SKIP_LIMIT_REACHED")
        ])
        let subject = makeManager(transport: transport)
        let restored = await subject.restore()
        XCTAssertTrue(restored)

        _ = try? await subject.getPlaylist(for: makeStation())
        XCTAssertEqual(transport.requests.count, 1)
    }
}
