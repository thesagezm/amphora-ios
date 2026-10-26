//
//  FeedbackTests.swift
//  PandoraCoreTests
//
//  `station.addFeedback` / `station.deleteFeedback` and the bookmark
//  endpoints (`user.getBookmarks`, `bookmark.add*Bookmark`,
//  `bookmark.delete*Bookmark`) — request shapes and reply decoding.
//

import XCTest
@testable import PandoraCore

final class FeedbackTests: XCTestCase {

    // MARK: - Rating

    func testAddFeedbackSendsTokenStationAndPositiveFlag() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok(#"{"feedbackId":"FB-1"}"#)
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        let receipt = try await subject.addFeedback(
            trackToken: "TT-1",
            stationToken: "ST-1",
            rating: .loved
        )
        XCTAssertEqual(receipt.feedbackId, "FB-1")

        let requests = transport.requests
        XCTAssertEqual(requests.count, 3, "partner, user, addFeedback")
        let request = try XCTUnwrap(requests.last)
        XCTAssertTrue(request.url.absoluteString.contains("method=station.addFeedback"))
        let body = try decryptedBody(request)
        XCTAssertTrue(body.contains(#""trackToken":"TT-1""#), body)
        XCTAssertTrue(body.contains(#""stationToken":"ST-1""#), body)
        XCTAssertTrue(body.contains(#""isPositive":true"#), body)
    }

    func testThumbsDownSendsIsPositiveFalse() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok(#"{"feedbackId":"FB-2"}"#)
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        _ = try await subject.addFeedback(
            trackToken: "TT-2",
            stationToken: "ST-1",
            rating: .banned
        )
        let body = try decryptedBody(try XCTUnwrap(transport.requests.last))
        XCTAssertTrue(body.contains(#""isPositive":false"#), body)
    }

    func testAddFeedbackReplyWithoutIdIsMalformed() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}")
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        do {
            _ = try await subject.addFeedback(
                trackToken: "TT", stationToken: "ST", rating: .loved
            )
            XCTFail("expected malformed response")
        } catch let error as PandoraMalformedResponseError {
            XCTAssertEqual(error.detail, "addFeedback reply missing feedbackId")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testDeleteFeedbackSendsFeedbackIdAndStationToken() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}")
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        try await subject.deleteFeedback(feedbackId: "FB-1", stationToken: "ST-1")

        let requests = transport.requests
        XCTAssertEqual(requests.count, 3)
        let request = try XCTUnwrap(requests.last)
        XCTAssertTrue(request.url.absoluteString.contains("method=station.deleteFeedback"))
        let body = try decryptedBody(request)
        XCTAssertTrue(body.contains(#""feedbackId":"FB-1""#), body)
        XCTAssertTrue(body.contains(#""stationToken":"ST-1""#), body)
    }

    // MARK: - Rating a song that has already played

    func testRateTrackTransformsASharedStationFirst() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}"),                             // transformSharedStation
            ok(#"{"feedbackId":"FB-9"}"#)        // addFeedback
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        let result = try await subject.rateTrack(
            trackToken: "TT-OLD",
            station: sharedStation(),
            rating: .loved
        )

        XCTAssertEqual(result.rating, .loved)
        XCTAssertEqual(result.feedbackId, "FB-9")

        let requests = transport.requests
        XCTAssertEqual(requests.count, 4, "partner, user, transform, addFeedback")
        XCTAssertTrue(requests[2].url.absoluteString.contains("method=station.transformSharedStation"))
        XCTAssertTrue(requests[3].url.absoluteString.contains("method=station.addFeedback"))
        let transformBody = try decryptedBody(requests[2])
        XCTAssertTrue(transformBody.contains(#""stationToken":"ST-SHARED""#), transformBody)
    }

    func testRateTrackDoesNotTransformAPersonalStation() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok(#"{"feedbackId":"FB-9"}"#)
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        _ = try await subject.rateTrack(
            trackToken: "TT-OLD",
            station: personalStation(),
            rating: .loved
        )

        let requests = transport.requests
        XCTAssertEqual(requests.count, 3, "partner, user, addFeedback")
        XCTAssertFalse(
            requests[2].url.absoluteString.contains("transformSharedStation"),
            "a personal station must not be transformed"
        )
    }

    func testRateTrackTransformsASharedStationOnlyOnce() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}"),                              // transform
            ok(#"{"feedbackId":"FB-1"}"#),        // first rating
            ok(#"{"feedbackId":"FB-2"}"#)         // second rating
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        let station = sharedStation()
        _ = try await subject.rateTrack(
            trackToken: "TT-1", station: station, rating: .loved
        )
        _ = try await subject.rateTrack(
            trackToken: "TT-1", station: station, rating: .banned
        )

        let transforms = transport.requests.filter {
            $0.url.absoluteString.contains("method=station.transformSharedStation")
        }
        XCTAssertEqual(transforms.count, 1, "the transform happens once per station")
    }

    func testRateTrackReplacesAnExistingRatingByItsId() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}"),                              // deleteFeedback
            ok(#"{"feedbackId":"FB-NEW"}"#)        // addFeedback
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        let result = try await subject.rateTrack(
            trackToken: "TT-1",
            station: personalStation(),
            rating: .banned,
            knownFeedbackId: "FB-OLD"
        )

        XCTAssertEqual(result.rating, .banned)
        XCTAssertEqual(result.feedbackId, "FB-NEW")
        let requests = transport.requests
        XCTAssertTrue(requests[2].url.absoluteString.contains("method=station.deleteFeedback"))
        let deleteBody = try decryptedBody(requests[2])
        XCTAssertTrue(deleteBody.contains(#""feedbackId":"FB-OLD""#), deleteBody)
        XCTAssertTrue(requests[3].url.absoluteString.contains("method=station.addFeedback"))
        let addBody = try decryptedBody(requests[3])
        XCTAssertTrue(addBody.contains(#""isPositive":false"#), addBody)
    }

    func testRemovingARatingWithoutAKnownIdReRatesFirstToObtainIt() async throws {
        // Pithos' trick: add the opposite rating to learn the feedback
        // id, then delete that feedback.
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok(#"{"feedbackId":"FB-TEMP"}"#),     // addFeedback (opposite)
            ok("{}")                               // deleteFeedback
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        let result = try await subject.rateTrack(
            trackToken: "TT-1",
            station: personalStation(),
            rating: .none
        )

        XCTAssertEqual(result.rating, .none)
        XCTAssertNil(result.feedbackId)
        let requests = transport.requests
        XCTAssertEqual(requests.count, 4, "partner, user, addFeedback, deleteFeedback")
        XCTAssertTrue(requests[2].url.absoluteString.contains("method=station.addFeedback"))
        XCTAssertTrue(requests[3].url.absoluteString.contains("method=station.deleteFeedback"))
        let deleteBody = try decryptedBody(requests[3])
        XCTAssertTrue(deleteBody.contains(#""feedbackId":"FB-TEMP""#), deleteBody)
    }

    func testRemovingARatingWithAKnownIdSkipsTheReRating() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}")                               // deleteFeedback only
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        let result = try await subject.rateTrack(
            trackToken: "TT-1",
            station: personalStation(),
            rating: .none,
            knownFeedbackId: "FB-OLD"
        )

        XCTAssertEqual(result.rating, .none)
        XCTAssertNil(result.feedbackId)
        let requests = transport.requests
        XCTAssertEqual(requests.count, 3, "partner, user, deleteFeedback")
        XCTAssertTrue(requests[2].url.absoluteString.contains("method=station.deleteFeedback"))
    }

    func testSleepSongSendsTrackToken() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}")
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        try await subject.sleepSong(trackToken: "TT-9")

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertTrue(request.url.absoluteString.contains("method=user.sleepSong"))
        let body = try decryptedBody(request)
        XCTAssertTrue(body.contains(#""trackToken":"TT-9""#), body)
    }

    // MARK: - Bookmarks

    func testGetBookmarksParsesSongsAndArtists() async throws {
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
            ok(
                #"""
                {
                  "songs": [
                    {
                      "bookmarkToken": "B-SONG",
                      "musicToken": "M-SONG",
                      "artistName": "Band",
                      "songName": "Hit",
                      "albumName": "Album",
                      "artUrl": "https://art",
                      "dateCreated": 1700000000
                    }
                  ],
                  "artists": [
                    {
                      "bookmarkToken": "B-ARTIST",
                      "musicToken": "M-ARTIST",
                      "artistName": "Other Band"
                    }
                  ]
                }
                """#
            )
        ])
        let subject = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: store,
            now: { Date(timeIntervalSince1970: 1_000_000_000) }
        )
        let restored = await subject.restore()
        XCTAssertTrue(restored)

        let bookmarks = try await subject.getBookmarks()
        XCTAssertEqual(bookmarks.count, 2)

        let song = try XCTUnwrap(bookmarks.first { $0.kind == .song })
        XCTAssertEqual(song.bookmarkToken, "B-SONG")
        XCTAssertEqual(song.title, "Hit")
        XCTAssertEqual(song.artistName, "Band")
        XCTAssertEqual(song.albumName, "Album")
        XCTAssertEqual(song.artworkUrl, "https://art")
        XCTAssertEqual(song.createdAt?.timeIntervalSince1970, 1_700_000_000)

        let artist = try XCTUnwrap(bookmarks.first { $0.kind == .artist })
        XCTAssertEqual(artist.bookmarkToken, "B-ARTIST")
        XCTAssertEqual(artist.title, "Other Band")
        XCTAssertNil(artist.songName)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(request.url.absoluteString.contains("method=user.getBookmarks"))
    }

    func testMalformedBookmarkEntriesAreSkipped() throws {
        let result = try envelopeResult(
            #"""
            {
              "songs": [
                { "musicToken": "M" },
                { "bookmarkToken": "B", "musicToken": "M2", "artistName": "A" }
              ],
              "artists": []
            }
            """#
        )
        let bookmarks = Bookmark.bookmarks(from: result)
        XCTAssertEqual(bookmarks.map(\.bookmarkToken), ["B"])
    }

    func testAddAndDeleteBookmarkEndpoints() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok("{}"),  // add song bookmark
            ok("{}"),  // add artist bookmark
            ok("{}"),  // delete song bookmark
            ok("{}")   // delete artist bookmark
        ])
        let subject = makeManager(transport: transport)
        _ = try await subject.login(username: "u", password: "p")

        try await subject.addSongBookmark(trackToken: "TT")
        try await subject.addArtistBookmark(trackToken: "TT")
        try await subject.deleteSongBookmark(bookmarkToken: "B-S")
        try await subject.deleteArtistBookmark(bookmarkToken: "B-A")

        let requests = transport.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertTrue(requests[2].url.absoluteString.contains("method=bookmark.addSongBookmark"))
        XCTAssertTrue(requests[3].url.absoluteString.contains("method=bookmark.addArtistBookmark"))
        XCTAssertTrue(requests[4].url.absoluteString.contains("method=bookmark.deleteSongBookmark"))
        XCTAssertTrue(requests[5].url.absoluteString.contains("method=bookmark.deleteArtistBookmark"))

        let addBody = try decryptedBody(requests[2])
        XCTAssertTrue(addBody.contains(#""trackToken":"TT""#), addBody)
        let deleteBody = try decryptedBody(requests[4])
        XCTAssertTrue(deleteBody.contains(#""bookmarkToken":"B-S""#), deleteBody)
    }

    // MARK: - Helpers

    /// A station the user owns.
    private func personalStation() -> Station {
        Station(
            id: "1",
            token: "ST-1",
            name: "My Station",
            isShared: false,
            isQuickMix: false
        )
    }

    /// A shared station — one the user has not personalised yet.
    private func sharedStation() -> Station {
        Station(
            id: "2",
            token: "ST-SHARED",
            name: "Shared Station",
            isShared: true,
            isQuickMix: false
        )
    }

    private func makeManager(transport: MockTransport) -> SessionManager {
        SessionManager(
            client: LegacyPandoraClient(transport: transport),
            now: { Date(timeIntervalSince1970: 1_000_000_000) }
        )
    }

    private func ok(_ resultObjectJSON: String) -> Result<Data, Error> {
        .success(Data("{\"stat\":\"ok\",\"result\":\(resultObjectJSON)}".utf8))
    }

    private func partnerOK() -> Result<Data, Error> {
        ok(
            #"""
            {
              "partnerId": "77",
              "partnerAuthToken": "P-TOKEN",
              "syncTime": "ac7b93e6a3c44c45258042bca01c9f6f40befffb546dee73"
            }
            """#
        )
    }

    private func userOK(token: String = "U-TOKEN") -> Result<Data, Error> {
        ok(#"{"userId":"u-1","userAuthToken":"\#(token)","isSubscriber":true}"#)
    }

    private func envelopeResult(_ objectJSON: String) throws -> [String: AnyJSON] {
        let envelope = Data(#"{"stat":"ok","result":\#(objectJSON)}"#.utf8)
        return try ResponseEnvelope.result(from: envelope)
    }

    private func decryptedBody(_ request: MockTransport.RecordedRequest) throws -> String {
        let hex = String(decoding: request.body, as: UTF8.self)
        let plain = try PandoraCrypto.decryptFromHex(hex, key: PandoraAPI.encryptKey)
        return String(decoding: plain.prefix { $0 != 0 }, as: UTF8.self)
    }
}
