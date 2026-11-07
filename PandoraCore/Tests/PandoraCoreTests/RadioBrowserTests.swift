//
//  RadioBrowserTests.swift
//  PandoraCoreTests
//
//  The radio-browser directory client: model decoding from captured
//  fixture shapes, request assembly, mirror rotation on failure, and
//  error mapping. No network in any test.
//

import XCTest
@testable import PandoraCore

final class RadioBrowserTests: XCTestCase {

    // MARK: Fixtures

    private static let stationsFixture = """
    [
      {
        "changeuuid": "c1",
        "stationuuid": "11111111-1111-1111-1111-111111111111",
        "name": "Jazz Radio",
        "url": "http://example.com/stream.pls",
        "url_resolved": "http://example.com/stream.mp3",
        "homepage": "http://example.com",
        "favicon": "http://example.com/icon.png",
        "tags": "jazz,smooth jazz, saxophone",
        "country": "Germany",
        "countrycode": "DE",
        "state": "",
        "language": "german",
        "votes": 4211,
        "clicks": 98077,
        "codec": "MP3",
        "bitrate": 128
      },
      {
        "stationuuid": "22222222-2222-2222-2222-222222222222",
        "name": "News Talk",
        "url": "https://news.example/live",
        "url_resolved": "",
        "homepage": null,
        "favicon": null,
        "tags": "",
        "country": "",
        "countrycode": "us",
        "language": null,
        "votes": "12",
        "clicks": null,
        "codec": "AAC",
        "bitrate": 64
      },
      { "stationuuid": "", "name": "No uuid" },
      { "stationuuid": "3", "name": "" },
      { "stationuuid": "4", "name": "No stream", "url_resolved": "" }
    ]
    """.data(using: .utf8)!

    private static let countriesFixture = """
    [
      { "name": "Germany", "iso_3166_1": "DE", "stationcount": 3200 },
      { "name": "United States", "iso_3166_1": "US", "stationcount": 6100 }
    ]
    """.data(using: .utf8)!

    private static let tagsFixture = """
    [
      { "name": "pop", "stationcount": 9100 },
      { "name": "jazz", "stationcount": 2400 }
    ]
    """.data(using: .utf8)!

    // MARK: Model decoding

    func testStationsDecodeAndSkipMalformedEntries() {
        let stations = RadioStation.stations(from: Self.stationsFixture)
        XCTAssertEqual(stations.count, 2)

        let jazz = stations[0]
        XCTAssertEqual(jazz.uuid, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(jazz.name, "Jazz Radio")
        XCTAssertEqual(jazz.streamURL, "http://example.com/stream.mp3")
        XCTAssertEqual(jazz.tags, ["jazz", "smooth jazz", "saxophone"])
        XCTAssertEqual(jazz.country, "Germany")
        XCTAssertEqual(jazz.countryCode, "DE")
        XCTAssertEqual(jazz.bitrate, 128)
        XCTAssertEqual(jazz.votes, 4211)
        XCTAssertEqual(jazz.clicks, 98077)

        // A gapless entry: no resolved URL falls back to the submitted
        // one; numeric strings decode; nulls stay nil.
        let news = stations[1]
        XCTAssertEqual(news.streamURL, "https://news.example/live")
        XCTAssertEqual(news.countryCode, "US")
        XCTAssertEqual(news.votes, 12)
        XCTAssertEqual(news.clicks, 0)
        XCTAssertNil(news.language)
        XCTAssertNil(news.faviconURL)
    }

    func testGarbageBodyYieldsNoStations() {
        XCTAssertEqual(RadioStation.stations(from: Data("not json".utf8)), [])
        XCTAssertEqual(RadioStation.stations(from: Data("[]".utf8)), [])
    }

    func testCaptionJoinsKnownFacts() {
        let known = RadioStation(
            uuid: "1", name: "A", streamURL: "s",
            country: "Germany", codec: "MP3", bitrate: 128
        )
        XCTAssertEqual(known.caption, "Germany · MP3 · 128 kbps")

        let bare = RadioStation(uuid: "2", name: "B", streamURL: "s")
        XCTAssertEqual(bare.caption, "")
    }

    func testCountriesAndTagsDecode() async throws {
        let transport = ScriptedTransport(outcomes: [
            ("/json/countries", .success(Self.countriesFixture)),
            ("/json/tags", .success(Self.tagsFixture)),
        ])
        let api = client(transport)
        let countries = try await api.countries()
        XCTAssertEqual(countries.map(\.code), ["DE", "US"])
        XCTAssertEqual(countries[0].name, "Germany")
        XCTAssertEqual(countries[0].stationCount, 3200)

        let tags = try await api.tags()
        XCTAssertEqual(tags.map(\.name), ["pop", "jazz"])
        XCTAssertEqual(tags[1].stationCount, 2400)
    }

    // MARK: Client behavior

    /// A scripted GET transport: per-URL outcomes plus recording.
    private final class ScriptedTransport: RadioBrowserTransport, @unchecked Sendable {
        private let lock = NSLock()
        private let outcomes: [(match: String, result: Result<Data, Error>)]
        private var used: [String] = []

        init(outcomes: [(String, Result<Data, Error>)]) {
            self.outcomes = outcomes
        }

        var requestedURLs: [String] {
            lock.lock()
            defer { lock.unlock() }
            return used
        }

        func get(url: URL) async throws -> Data {
            let outcome: (match: String, result: Result<Data, any Error>)? = {
                lock.lock()
                defer { lock.unlock() }
                used.append(url.absoluteString)
                return outcomes.first { url.absoluteString.contains($0.match) }
            }()
            guard let outcome else {
                throw RadioBrowserError.networkFailure
            }
            return try outcome.result.get()
        }
    }

    private func client(_ transport: ScriptedTransport) -> RadioBrowserClient {
        RadioBrowserClient(
            transport: transport,
            mirrors: [
                .init(baseURL: "https://one.api.radio-browser.info"),
                .init(baseURL: "https://two.api.radio-browser.info"),
            ]
        )
    }

    func testSearchBuildsVotesOrderedQuery() async throws {
        let transport = ScriptedTransport(outcomes: [
            ("stations/search", .success(Data("[]".utf8)))
        ])
        let stations = try await client(transport).searchStations(name: "jazz fm")
        XCTAssertTrue(stations.isEmpty)

        let url = try XCTUnwrap(transport.requestedURLs.first)
        XCTAssertTrue(url.hasPrefix("https://one.api.radio-browser.info/json/stations/search?"))
        XCTAssertTrue(url.contains("name=jazz%20fm"))
        XCTAssertTrue(url.contains("order=votes"))
        XCTAssertTrue(url.contains("reverse=true"))
        XCTAssertTrue(url.contains("hidebroken=true"))
        XCTAssertTrue(url.contains("limit=50"))
    }

    func testEmptySearchNameSkipsTheNetwork() async throws {
        let transport = ScriptedTransport(outcomes: [])
        let stations = try await client(transport).searchStations(name: "   ")
        XCTAssertTrue(stations.isEmpty)
        XCTAssertTrue(transport.requestedURLs.isEmpty)
    }

    func testMirrorRotationSurvivesADeadMirror() async throws {
        let transport = ScriptedTransport(outcomes: [
            ("one.api.radio-browser.info", .failure(RadioBrowserError.networkFailure)),
            ("topvote", .success(Self.stationsFixture)),
        ])
        let stations = try await client(transport).topStations(limit: 25)
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(transport.requestedURLs.count, 2)
        XCTAssertTrue(transport.requestedURLs[0].contains("one.api"))
        XCTAssertTrue(transport.requestedURLs[1].contains("two.api"))
        XCTAssertTrue(transport.requestedURLs[1].contains("/json/stations/topvote/25"))
    }

    func testFailedMirrorIsNotRetriedFirstNextCall() async throws {
        let transport = ScriptedTransport(outcomes: [
            ("one.api.radio-browser.info", .failure(RadioBrowserError.networkFailure)),
            ("topvote", .success(Data("[]".utf8))),
            ("two.api.radio-browser.info", .success(Data("[]".utf8))),
        ])
        let api = client(transport)
        _ = try await api.topStations()           // one dead → two answers
        _ = try await api.topStations()           // two is tried directly
        XCTAssertEqual(transport.requestedURLs.count, 3)
        XCTAssertTrue(transport.requestedURLs[2].contains("two.api"))
    }

    func testAllMirrorsDownSurfacesTypedError() async {
        let transport = ScriptedTransport(outcomes: [
            ("one.api", .failure(RadioBrowserError.httpStatus(503))),
            ("two.api", .failure(RadioBrowserError.httpStatus(503))),
        ])
        do {
            _ = try await client(transport).topStations()
            XCTFail("expected a thrown error")
        } catch let error as RadioBrowserError {
            XCTAssertEqual(error, .httpStatus(503))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testCountryAndTagPathsArePercentEncoded() async throws {
        let transport = ScriptedTransport(outcomes: [
            ("bycountrycodeexact", .success(Data("[]".utf8))),
            ("bytag", .success(Data("[]".utf8))),
        ])
        let api = client(transport)
        _ = try await api.stations(countryCode: "de")
        _ = try await api.stations(tag: "smooth jazz")
        XCTAssertTrue(try XCTUnwrap(transport.requestedURLs.first)
            .contains("/json/stations/bycountrycodeexact/DE?"))
        XCTAssertTrue(try XCTUnwrap(transport.requestedURLs.last)
            .contains("/json/stations/bytag/smooth%20jazz?"))
    }

    func testClickPingHitsTheURLPath() async throws {
        let transport = ScriptedTransport(outcomes: [
            ("/json/url/", .success(Data(#"{"name":"ok","url":"ok"}"#.utf8)))
        ])
        await client(transport).registerClick(uuid: "11111111-1111-1111-1111-111111111111")
        let url = try XCTUnwrap(transport.requestedURLs.first)
        XCTAssertTrue(url.contains("/json/url/11111111-1111-1111-1111-111111111111"))
    }

    // MARK: Playback bridge

    func testRadioTrackCarriesStationFactsAndLiveDuration() {
        let station = RadioStation(
            uuid: "abc-123",
            name: "Jazz Radio",
            streamURL: "http://example.com/stream.mp3",
            faviconURL: "http://example.com/icon.png",
            country: "Germany",
            codec: "MP3",
            bitrate: 128
        )
        let track = Track.radioTrack(for: station)
        XCTAssertEqual(track.trackToken, "radio.abc-123")
        XCTAssertEqual(track.title, "Jazz Radio")
        XCTAssertEqual(track.artist, "Germany · MP3 · 128 kbps")
        XCTAssertEqual(track.artworkUrl, "http://example.com/icon.png")
        XCTAssertEqual(track.duration, 0)
        XCTAssertEqual(track.rating, .none)
        XCTAssertTrue(track.isRadio)
        XCTAssertEqual(track.streamURL, "http://example.com/stream.mp3")
    }

    func testIsRadioDistinguishesPandoraTracks() {
        XCTAssertFalse(Track(
            trackToken: "T0001", title: "Song", artist: "Artist",
            album: "", duration: 180, stationId: "S1"
        ).isRadio)
        XCTAssertFalse(Track(
            trackToken: "ad.TOKEN", title: "Ad", artist: "",
            album: "", duration: 30, stationId: "S1", isAdvertisement: true
        ).isRadio)
    }
}
