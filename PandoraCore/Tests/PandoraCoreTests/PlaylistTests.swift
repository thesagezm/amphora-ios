//
//  PlaylistTests.swift
//  PandoraCoreTests
//
//  `station.getPlaylist` decoding (wire fields, quality promotion, ad
//  flagging) and the SessionManager request shape.
//

import XCTest
@testable import PandoraCore

final class PlaylistTests: XCTestCase {

    // MARK: - Parsing

    func testDecodesFullEntry() throws {
        let result = try envelopeResult(
            #"""
            {
              "items": [
                {
                  "albumName": "Album",
                  "artistName": "Band",
                  "trackToken": "TT-1",
                  "songRating": 1,
                  "stationId": "42",
                  "songName": "Title",
                  "songDetailUrl": "https://x",
                  "songExplorerUrl": "https://y",
                  "albumArtUrl": "https://art",
                  "trackLength": 215,
                  "trackGain": "0.75",
                  "adToken": "AD",
                  "audioUrlMap": {
                    "highQuality": {
                      "encoding": "aacplus",
                      "bitrate": "64",
                      "audioUrl": "https://stream/a"
                    }
                  }
                }
              ]
            }
            """#
        )
        let tracks = Track.tracks(from: result)
        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.trackToken, "TT-1")
        XCTAssertEqual(track.title, "Title")
        XCTAssertEqual(track.artist, "Band")
        XCTAssertEqual(track.album, "Album")
        XCTAssertEqual(track.artworkUrl, "https://art")
        XCTAssertEqual(track.duration, 215)
        XCTAssertEqual(track.stationId, "42")
        XCTAssertEqual(track.rating, .loved)
        XCTAssertEqual(track.gain, 0.75)
        XCTAssertTrue(track.isAdvertisement)
        XCTAssertEqual(track.streamURL, "https://stream/a")
        XCTAssertEqual(track.preferredVariant?.bitrate, 64)
        XCTAssertEqual(track.preferredVariant?.encoding, "aacplus")
    }

    func testEntriesWithoutSongNameAreSkipped() throws {
        // pithos filters these out: `[Song(...) for i in playlist if 'songName' in i]`
        let result = try envelopeResult(
            #"""
            {
              "items": [
                { "adToken": "AD-1", "trackToken": "TT-AD" },
                { "songName": "Real", "trackToken": "TT-2", "artistName": "A" }
              ]
            }
            """#
        )
        let tracks = Track.tracks(from: result)
        XCTAssertEqual(tracks.map(\.trackToken), ["TT-2"])
        XCTAssertFalse(tracks[0].isAdvertisement)
    }

    func testNonObjectEntriesAreIgnored() throws {
        let result = try envelopeResult(
            #"""
            { "items": ["nope", { "songName": "Ok", "trackToken": "TT" }] }
            """#
        )
        XCTAssertEqual(Track.tracks(from: result).map(\.trackToken), ["TT"])
    }

    // MARK: - Quality selection

    func testAdditionalUrlsPromoteMp3WhenHighQualityIsBelow128() throws {
        // pithos' rule: the extra 128 MP3 beats a <128 high quality, and the
        // old high becomes the medium variant.
        let result = try envelopeResult(
            #"""
            {
              "items": [
                {
                  "songName": "T",
                  "trackToken": "TT",
                  "audioUrlMap": {
                    "highQuality": {
                      "encoding": "aacplus",
                      "bitrate": "64",
                      "audioUrl": "https://aac64"
                    }
                  },
                  "additionalAudioUrl": ["https://aac32", "https://mp3-128"]
                }
              ]
            }
            """#
        )
        let track = try XCTUnwrap(Track.tracks(from: result).first)
        XCTAssertEqual(track.variants.map(\.quality), [.highQuality, .mediumQuality])
        XCTAssertEqual(track.variants[0].encoding, "mp3")
        XCTAssertEqual(track.variants[0].bitrate, 128)
        XCTAssertEqual(track.variants[0].url, "https://mp3-128")
        XCTAssertEqual(track.variants[1].url, "https://aac64")
        XCTAssertEqual(track.streamURL, "https://mp3-128")
    }

    func testAdditionalUrlsBecomeLowQualityFallbackWhenHighIsAlready128() throws {
        let result = try envelopeResult(
            #"""
            {
              "items": [
                {
                  "songName": "T",
                  "trackToken": "TT",
                  "audioUrlMap": {
                    "highQuality": {
                      "encoding": "mp3",
                      "bitrate": "128",
                      "audioUrl": "https://mp3-128"
                    }
                  },
                  "additionalAudioUrl": ["https://aac32", "https://mp3-128"]
                }
              ]
            }
            """#
        )
        let track = try XCTUnwrap(Track.tracks(from: result).first)
        XCTAssertEqual(track.variants.map(\.quality), [.highQuality, .lowQuality])
        XCTAssertEqual(track.variants[1].bitrate, 32)
        XCTAssertEqual(track.variants[1].url, "https://aac32")
        XCTAssertEqual(track.streamURL, "https://mp3-128")
    }

    func testBareAudioUrlIsTreatedAsHighQualityAacplus() throws {
        // pydora's AudioField: some tokens answer with a plain audioUrl.
        let result = try envelopeResult(
            #"""
            {
              "items": [
                { "songName": "T", "trackToken": "TT", "audioUrl": "https://bare" }
              ]
            }
            """#
        )
        let track = try XCTUnwrap(Track.tracks(from: result).first)
        XCTAssertEqual(track.variants.count, 1)
        XCTAssertEqual(track.variants[0].quality, .highQuality)
        XCTAssertEqual(track.variants[0].encoding, "aacplus")
        XCTAssertEqual(track.variants[0].bitrate, 64)
        XCTAssertEqual(track.streamURL, "https://bare")
    }

    func testEntryWithoutAnyAudioHasNoStream() throws {
        let result = try envelopeResult(
            #"""
            {
              "items": [
                { "songName": "T", "trackToken": "TT", "adToken": "AD" }
              ]
            }
            """#
        )
        let track = try XCTUnwrap(Track.tracks(from: result).first)
        XCTAssertTrue(track.variants.isEmpty)
        XCTAssertNil(track.streamURL)
        XCTAssertTrue(track.isAdvertisement)
    }

    func testVariantsAreOrderedBestQualityFirst() throws {
        let result = try envelopeResult(
            #"""
            {
              "items": [
                {
                  "songName": "T",
                  "trackToken": "TT",
                  "audioUrlMap": {
                    "lowQuality": {
                      "encoding": "aacplus",
                      "bitrate": "32",
                      "audioUrl": "https://low"
                    },
                    "mediumQuality": {
                      "encoding": "aacplus",
                      "bitrate": "64",
                      "audioUrl": "https://med"
                    },
                    "highQuality": {
                      "encoding": "aacplus",
                      "bitrate": "128",
                      "audioUrl": "https://high"
                    }
                  }
                }
              ]
            }
            """#
        )
        let track = try XCTUnwrap(Track.tracks(from: result).first)
        XCTAssertEqual(track.variants.map(\.url), ["https://high", "https://med", "https://low"])
    }

    // MARK: - Playlist expiry

    func testPlaylistExpiresAfterOneHour() {
        let fetched = Date(timeIntervalSince1970: 1_000_000_000)
        let playlist = Playlist(tracks: [], fetchedAt: fetched)
        XCTAssertFalse(playlist.isExpired(now: fetched.addingTimeInterval(3_599)))
        XCTAssertTrue(playlist.isExpired(now: fetched.addingTimeInterval(3_600)))
    }

    // MARK: - Request shape (SessionManager)

    func testGetPlaylistSendsPithosParamsAndDecodesItems() async throws {
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
                  "items": [
                    {
                      "songName": "Song",
                      "artistName": "Artist",
                      "trackToken": "TT",
                      "stationId": "7",
                      "trackLength": 100,
                      "audioUrlMap": {
                        "highQuality": {
                          "encoding": "aacplus",
                          "bitrate": "64",
                          "audioUrl": "https://stream"
                        }
                      }
                    }
                  ]
                }
                """#
            )
        ])
        let manager = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: store,
            now: { Date(timeIntervalSince1970: 1_000_000_000) }
        )
        let restored = await manager.restore()
        XCTAssertTrue(restored)

        let station = Station(
            id: "7", token: "ST-7", name: "Rock", isShared: false, isQuickMix: false
        )
        let playlist = try await manager.getPlaylist(for: station)

        XCTAssertEqual(playlist.tracks.count, 1)
        XCTAssertEqual(playlist.tracks.first?.title, "Song")
        XCTAssertEqual(playlist.tracks.first?.streamURL, "https://stream")

        let requests = transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.url.absoluteString.contains("method=station.getPlaylist"))
        XCTAssertTrue(request.url.absoluteString.contains("auth_token=U-TOKEN"))

        let hex = String(decoding: request.body, as: UTF8.self)
        let plain = try PandoraCrypto.decryptFromHex(hex, key: PandoraAPI.encryptKey)
        let body = String(decoding: plain.prefix { $0 != 0 }, as: UTF8.self)
        XCTAssertTrue(body.contains(#""stationToken":"ST-7""#), body)
        XCTAssertTrue(body.contains(#""includeTrackLength":true"#), body)
        XCTAssertTrue(
            body.contains(#""additionalAudioUrl":"HTTP_32_AACPLUS,HTTP_128_MP3""#),
            body
        )
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
