//
//  AdvertisementTests.swift
//  PandoraCoreTests
//
//  Ad handling after pydora: playlist ad entries decode as flagged,
//  usually unplayable stubs (with a synthetic id when the entry has no
//  trackToken), `ad.getAdMetadata` / `ad.registerAd` request shapes,
//  and the SessionManager facade (prepareAd: resolve required, register
//  best-effort, skipped entirely without tracking tokens).
//
//  Swift 6 notes: recorded request arrays are hoisted out of XCT*
//  autoclosures (no `await` inside an autoclosure).
//

import XCTest
@testable import PandoraCore

// MARK: - Playlist decode

final class PlaylistAdDecodingTests: XCTestCase {

    private func track(_ entryJSON: String) throws -> Track? {
        let entry = try JSONDecoder().decode(AnyJSON.self, from: Data(entryJSON.utf8))
        guard let object = entry.objectValue else {
            return nil
        }
        return Track.track(from: object)
    }

    func testAdEntryWithAudioIsKeptAndFlagged() throws {
        let decoded = try track("""
        {"adToken":"ADT-1","title":"Big Brand Ad","companyName":"Brand Co.",
         "audioUrl":"https://audio.example/ad.mp3","imageUrl":"https://img.example/ad.png",
         "clickThroughUrl":"https://click.example/","stationId":"123",
         "adTrackingTokens":["t1","t2"]}
        """)
        let ad = try XCTUnwrap(decoded)
        XCTAssertTrue(ad.isAdvertisement)
        XCTAssertEqual(ad.adToken, "ADT-1")
        XCTAssertEqual(ad.title, "Big Brand Ad")
        XCTAssertEqual(ad.artist, "Brand Co.")
        XCTAssertEqual(ad.id, "ad.ADT-1")
        XCTAssertEqual(ad.stationId, "123")
        // pydora AudioField: bare audioUrl = 64 kbps aacplus high quality.
        let variant = try XCTUnwrap(ad.preferredVariant)
        XCTAssertEqual(variant.quality, .highQuality)
        XCTAssertEqual(variant.bitrate, 64)
        XCTAssertEqual(variant.encoding, "aacplus")
        XCTAssertNotNil(ad.streamURL)
    }

    func testAdStubWithoutAudioIsKeptButUnplayable() throws {
        let decoded = try track("""
        {"adToken":"ADT-2","title":"Audio-less Ad","companyName":"Brand Co."}
        """)
        let ad = try XCTUnwrap(decoded)
        XCTAssertTrue(ad.isAdvertisement)
        XCTAssertTrue(ad.variants.isEmpty)
        XCTAssertNil(ad.streamURL)
    }

    func testMusicEntryIsUnaffected() throws {
        let decoded = try track("""
        {"trackToken":"TT-1","songName":"Song","artistName":"Artist",
         "albumName":"Album","trackLength":200,"stationId":"123",
         "songRating":0,"trackGain":-1.5}
        """)
        let song = try XCTUnwrap(decoded)
        XCTAssertFalse(song.isAdvertisement)
        XCTAssertNil(song.adToken)
        XCTAssertEqual(song.id, "TT-1")
    }

    func testEntryWithoutSongNameOrAdTokenIsDropped() throws {
        let dropped = try track(#"{"albumName":"Mystery","stationId":"123"}"#)
        XCTAssertNil(dropped)
    }

    // MARK: Advertisement metadata decoding

    private static let metadataResult = """
    {"title":"Resolved Ad","companyName":"Brand Co.",
     "adTrackingTokens":["tok-1","tok-2"],
     "audioUrl":"https://audio.example/resolved.mp3",
     "imageUrl":"https://img.example/resolved.png",
     "clickThroughUrl":"https://click.example/resolved"}
    """

    func testAdMetadataDecodes() {
        let ad = Advertisement(adToken: "ADT-9", result: Self.metadataJSONObject)
        XCTAssertEqual(ad.adToken, "ADT-9")
        XCTAssertEqual(ad.title, "Resolved Ad")
        XCTAssertEqual(ad.companyName, "Brand Co.")
        XCTAssertEqual(ad.trackingTokens, ["tok-1", "tok-2"])
        XCTAssertEqual(ad.audioURL, "https://audio.example/resolved.mp3")
        XCTAssertEqual(ad.imageURL, "https://img.example/resolved.png")
        XCTAssertEqual(ad.clickThroughURL, "https://click.example/resolved")
    }

    func testAdMetadataToleratesMissingFields() {
        let ad = Advertisement(adToken: "ADT-9", result: [:])
        XCTAssertEqual(ad.title, "")
        XCTAssertTrue(ad.trackingTokens.isEmpty)
        XCTAssertNil(ad.audioURL)
    }

    func testAsTrackBuildsPlayableSlot() {
        let ad = Advertisement(adToken: "ADT-9", result: Self.metadataJSONObject)
        let slot = ad.asTrack(stationId: "123")
        XCTAssertTrue(slot.isAdvertisement)
        XCTAssertEqual(slot.adToken, "ADT-9")
        XCTAssertEqual(slot.id, "ad.ADT-9")
        XCTAssertEqual(slot.title, "Resolved Ad")
        XCTAssertEqual(slot.artist, "Brand Co.")
        XCTAssertEqual(slot.stationId, "123")
        XCTAssertEqual(slot.preferredVariant?.bitrate, 64)
        XCTAssertNotNil(slot.streamURL)
    }

    func testAsTrackWithoutAudioHasNoVariants() {
        let slot = Advertisement(adToken: "ADT-9").asTrack(stationId: "123")
        XCTAssertTrue(slot.variants.isEmpty)
        XCTAssertNil(slot.streamURL)
    }

    private static let metadataJSONObject: [String: AnyJSON] = {
        let decoded = try! JSONDecoder().decode(AnyJSON.self, from: Data(metadataResult.utf8))
        return decoded.objectValue ?? [:]
    }()
}

// MARK: - JSONValue array encoding

final class JSONValueArrayTests: XCTestCase {

    func testArrayEncodesWithSortedKeys() {
        let body = JSONValue.encoded([
            "stationId": .string("123"),
            "adTrackingTokens": .array([.string("t2"), .string("t1")])
        ])
        // Keys sorted; array preserves element order.
        XCTAssertEqual(
            String(decoding: body, as: UTF8.self),
            #"{"adTrackingTokens":["t2","t1"],"stationId":"123"}"#
        )
    }

    func testEmptyArrayEncodes() {
        let body = JSONValue.encoded(["adTrackingTokens": .array([])])
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"adTrackingTokens":[]}"#)
    }
}

// MARK: - SessionManager facade

final class SessionManagerAdTests: XCTestCase {

    /// Same fixture as SessionManagerTests (pithos Blowfish pipeline):
    /// decrypts to bytes[4..<14] = "1760000000" against the fixed clock.
    private static let syncTimeMain =
        "ac7b93e6a3c44c45258042bca01c9f6f40befffb546dee73"

    private static let clock: @Sendable () -> Date = {
        Date(timeIntervalSince1970: 1_000_000_000)
    }

    private func ok(_ resultObjectJSON: String) -> Result<Data, Error> {
        .success(Data("{\"stat\":\"ok\",\"result\":\(resultObjectJSON)}".utf8))
    }

    private func partnerOK() -> Result<Data, Error> {
        ok(#"{"partnerId":"77","partnerAuthToken":"P-TOKEN","syncTime":"\#(Self.syncTimeMain)"}"#)
    }

    private func userOK() -> Result<Data, Error> {
        ok(#"{"userId":"u-1","userAuthToken":"U-TOKEN","isSubscriber":false}"#)
    }

    private func makeManager(
        legacyResponses: [Result<Data, Error>]
    ) -> (SessionManager, MockTransport) {
        let legacy = MockTransport(responses: legacyResponses)
        let manager = SessionManager(
            client: LegacyPandoraClient(transport: legacy),
            store: nil,
            now: Self.clock
        )
        return (manager, legacy)
    }

    /// Decrypts an encrypted request body (responses are Blowfish hex).
    private func decryptedBody(_ request: MockTransport.RecordedRequest) throws -> String {
        let hex = String(decoding: request.body, as: UTF8.self)
        let plain = try PandoraCrypto.decryptFromHex(hex, key: PandoraAPI.encryptKey)
        return String(decoding: plain.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static let metadataReply = """
    {"title":"Resolved Ad","companyName":"Brand Co.",
     "adTrackingTokens":["tok-1","tok-2"],
     "audioUrl":"https://audio.example/resolved.mp3"}
    """

    private static let adTrack = Track(
        trackToken: "ad.ADT-1",
        title: "Big Brand Ad",
        artist: "Brand Co.",
        album: "",
        duration: 0,
        stationId: "123",
        isAdvertisement: true,
        adToken: "ADT-1"
    )

    func testGetAdMetadataSendsPydoraParams() async throws {
        let (manager, transport) = makeManager(
            legacyResponses: [partnerOK(), userOK(), ok(Self.metadataReply)]
        )
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        let ad = try await manager.getAdMetadata(adToken: "ADT-1")
        XCTAssertEqual(ad.title, "Resolved Ad")
        XCTAssertEqual(ad.trackingTokens, ["tok-1", "tok-2"])
        XCTAssertEqual(ad.audioURL, "https://audio.example/resolved.mp3")

        let requests = transport.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertTrue(request.url.absoluteString.contains("method=ad.getAdMetadata"))
        let body = try decryptedBody(request)
        XCTAssertTrue(body.contains(#""adToken":"ADT-1""#))
        XCTAssertTrue(body.contains(#""returnAdTrackingTokens":true"#))
        XCTAssertTrue(body.contains(#""supportAudioAds":true"#))
    }

    func testRegisterAdSendsTokensAndStation() async throws {
        let (manager, transport) = makeManager(
            legacyResponses: [partnerOK(), userOK(), ok("{}")]
        )
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        try await manager.registerAd(stationId: "123", trackingTokens: ["tok-1", "tok-2"])

        let requests = transport.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertTrue(request.url.absoluteString.contains("method=ad.registerAd"))
        let body = try decryptedBody(request)
        XCTAssertTrue(body.contains(#""adTrackingTokens":["tok-1","tok-2"]"#))
        XCTAssertTrue(body.contains(#""stationId":"123""#))
    }

    func testRegisterAdRefusesEmptyTokensWithoutNetwork() async throws {
        let (manager, transport) = makeManager(
            legacyResponses: [partnerOK(), userOK()]
        )
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        do {
            try await manager.registerAd(stationId: "123", trackingTokens: [])
            XCTFail("expected missingTrackingTokens")
        } catch let error as AdvertisementError {
            XCTAssertEqual(error, .missingTrackingTokens)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        // Only the two login calls ever hit the transport.
        let requests = transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testPrepareAdResolvesAndRegisters() async throws {
        let (manager, transport) = makeManager(
            legacyResponses: [partnerOK(), userOK(), ok(Self.metadataReply), ok("{}")]
        )
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        let metadata = try await manager.prepareAd(Self.adTrack)
        XCTAssertEqual(metadata.adToken, "ADT-1")
        XCTAssertEqual(metadata.trackingTokens, ["tok-1", "tok-2"])

        let requests = transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(try XCTUnwrap(requests.last).url.absoluteString.contains("method=ad.registerAd"))
    }

    func testPrepareAdUsesTrackStationWhenNotOverridden() async throws {
        let (manager, transport) = makeManager(
            legacyResponses: [partnerOK(), userOK(), ok(Self.metadataReply), ok("{}")]
        )
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        _ = try await manager.prepareAd(Self.adTrack)

        let requests = transport.requests
        let registerBody = try decryptedBody(try XCTUnwrap(requests.last))
        XCTAssertTrue(registerBody.contains(#""stationId":"123""#))
    }

    func testPrepareAdSkipsRegistrationWithoutTrackingTokens() async throws {
        let (manager, transport) = makeManager(
            legacyResponses: [partnerOK(), userOK(), ok(#"{"title":"No tokens"}"#)]
        )
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        let metadata = try await manager.prepareAd(Self.adTrack)
        XCTAssertEqual(metadata.title, "No tokens")

        // partner + user + metadata only — no registerAd call (pydora
        // prepare_playback skips registration the same way).
        let requests = transport.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testPrepareAdSurvivesRegisterFailure() async throws {
        let (manager, transport) = makeManager(
            legacyResponses: [
                partnerOK(), userOK(), ok(Self.metadataReply),
                .failure(PandoraTransportError(reason: "register exploded"))
            ]
        )
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        // Deliberate deviation from pydora: a failed impression
        // registration must not block playback.
        let metadata = try await manager.prepareAd(Self.adTrack)
        XCTAssertEqual(metadata.title, "Resolved Ad")

        let requests = transport.requests
        XCTAssertEqual(requests.count, 4)
    }

    func testPrepareAdRequiresAnAdvertisement() async throws {
        let (manager, transport) = makeManager(legacyResponses: [partnerOK(), userOK()])
        _ = try await manager.login(username: "me@example.com", password: "hunter2")

        let song = Track(
            trackToken: "TT-1", title: "Song", artist: "Artist", album: "",
            duration: 200, stationId: "123"
        )
        do {
            _ = try await manager.prepareAd(song)
            XCTFail("expected notAnAdvertisement")
        } catch let error as AdvertisementError {
            XCTAssertEqual(error, .notAnAdvertisement)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let requests = transport.requests
        XCTAssertEqual(requests.count, 2)
    }
}
