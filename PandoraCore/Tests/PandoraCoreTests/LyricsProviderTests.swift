//
//  LyricsProviderTests.swift
//  PandoraCoreTests
//
//  The lrclib.net client and the translation client, against scripted
//  GET responses. No network in any unit test.
//
//  The response shapes are the ones the live service returns (verified
//  against lrclib's own server source, `server/src/routes/*.rs`).
//

import XCTest
@testable import PandoraCore

// MARK: - Stub transport

/// Returns scripted responses in call order and records every request.
final class StubGETTransport: HTTPGETTransport, @unchecked Sendable {
    struct RecordedRequest {
        let url: URL
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var recorded: [RecordedRequest] = []
    private let responses: [Result<Data, Error>]
    private var next = 0

    init(responses: [Result<Data, Error>]) {
        self.responses = responses
    }

    var requests: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func get(url: URL, headers: [String: String]) async throws -> Data {
        let index = record(url: url, headers: headers)
        guard index < responses.count else {
            throw PandoraTransportError(reason: "stub exhausted at request \(index)")
        }
        return try responses[index].get()
    }

    private func record(url: URL, headers: [String: String]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(RecordedRequest(url: url, headers: headers))
        let index = next
        next += 1
        return index
    }
}

// MARK: - Tests

/// Escapes a string for a JSON fixture (newlines, quotes, apostrophes
/// are fine unescaped, but the newline must become `\n`).
private extension String {
    var jsonEscaped: String {
        var out = ""
        for character in self {
            switch character {
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            default: out.append(character)
            }
        }
        return out
    }
}

final class LyricsProviderTests: XCTestCase {

    private func track(
        title: String = "Creep",
        artist: String = "Radiohead",
        album: String = "Pablo Honey",
        duration: Int = 239
    ) -> Track {
        Track(
            trackToken: "TT-1",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            stationId: "S-1"
        )
    }

    private func recordJSON(
        synced: String? = "[00:12.00]When you were here before\n[00:15.00]Couldn't look you in the eye",
        plain: String? = "When you were here before",
        instrumental: Bool = false
    ) -> Data {
        let syncedField = synced.map { "\"\($0.jsonEscaped)\"" } ?? "null"
        let plainField = plain.map { "\"\($0.jsonEscaped)\"" } ?? "null"
        return Data("""
        {"id":496,"name":"Creep","trackName":"Creep","artistName":"Radiohead",
        "albumName":"Pablo Honey","duration":239.0,"instrumental":\(instrumental),
        "hasWordSync":false,"plainLyrics":\(plainField),"syncedLyrics":\(syncedField),
        "lyricsfile":null}
        """.utf8)
    }

    // MARK: lrclib

    func testFetchesSyncedLyricsByMetadata() async throws {
        let transport = StubGETTransport(responses: [.success(recordJSON())])
        let client = LRCLibClient(transport: transport)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines[0].timestamp, 12, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[0].text, "When you were here before")
        XCTAssertEqual(lyrics.trackID, 496)
        XCTAssertFalse(lyrics.instrumental)

        let request = try XCTUnwrap(transport.requests.first)
        let url = request.url.absoluteString
        XCTAssertTrue(url.hasPrefix("https://lrclib.net/api/get?"))
        XCTAssertTrue(url.contains("track_name=Creep"))
        XCTAssertTrue(url.contains("artist_name=Radiohead"))
        XCTAssertTrue(url.contains("album_name=Pablo%20Honey"))
        XCTAssertTrue(url.contains("duration=239"))
        // The service asks clients to identify themselves.
        XCTAssertNotNil(request.headers["User-Agent"])
        XCTAssertNotNil(request.headers["Lrclib-Client"])
    }

    func testPlainLyricsAreKeptWhenNotSynced() async throws {
        let transport = StubGETTransport(responses: [
            .success(recordJSON(synced: nil, plain: "Line one\nLine two"))
        ])
        let client = LRCLibClient(transport: transport)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertFalse(lyrics.isSynced)
        XCTAssertEqual(lyrics.plainText, "Line one\nLine two")
    }

    func testInstrumentalTrackIsFlagged() async throws {
        let transport = StubGETTransport(responses: [
            .success(recordJSON(synced: nil, plain: nil, instrumental: true))
        ])
        let client = LRCLibClient(transport: transport)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertTrue(lyrics.instrumental)
    }

    func testNotFoundIsTyped() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 404"))
        ])
        let client = LRCLibClient(transport: transport)

        do {
            _ = try await client.lyrics(for: track())
            XCTFail("expected a not-found error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .notFound)
        }
    }

    func testBusyServiceIsRetriedThenReported() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 503")),
            .failure(PandoraTransportError(reason: "HTTP 503")),
            .failure(PandoraTransportError(reason: "HTTP 503"))
        ])
        let client = LRCLibClient(transport: transport, maxRetries: 2)

        do {
            _ = try await client.lyrics(for: track())
            XCTFail("expected a busy error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .serviceBusy)
        }
        // The initial attempt plus two retries.
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testBusyServiceRecoversOnRetry() async throws {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 503")),
            .success(recordJSON())
        ])
        let client = LRCLibClient(transport: transport, maxRetries: 2)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testMalformedResponseIsTyped() async {
        let transport = StubGETTransport(responses: [.success(Data("not json".utf8))])
        let client = LRCLibClient(transport: transport)

        do {
            _ = try await client.lyrics(for: track())
            XCTFail("expected a malformed-response error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .malformedResponse)
        }
    }

    // MARK: Translation

    func testTranslatesForeignLyrics() async throws {
        let response = Data("""
        [[["I am a cat","Je suis un chat",null,null,3]],null,"fr",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let translated = await client.englishTranslation(of: ["Je suis un chat"])

        XCTAssertEqual(translated, ["I am a cat"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(request.url.absoluteString.contains("tl=en"))
        XCTAssertTrue(request.url.absoluteString.contains("sl=auto"))
    }

    func testEnglishLyricsNeedNoTranslation() async {
        let response = Data("""
        [[["Hallelujah","Hallelujah",null,null,5]],null,"en",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let translated = await client.englishTranslation(of: ["Hallelujah"])

        XCTAssertNil(translated)
    }

    func testTranslationFailureReturnsNil() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "network failure"))
        ])
        let client = GoogleTranslateClient(transport: transport)

        let translated = await client.englishTranslation(of: ["Bonjour"])

        XCTAssertNil(translated)
    }
}
