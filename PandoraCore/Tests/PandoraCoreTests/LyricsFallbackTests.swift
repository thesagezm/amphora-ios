//
//  LyricsFallbackTests.swift
//  PandoraCoreTests
//
//  The lyrics fallback chain: lrclib's fuzzy search, lyrics.ovh, the
//  candidate scorer, and the chain that ties them together.
//
//  The response shapes are the ones the live services return (verified
//  against both services this session).
//

import XCTest
@testable import PandoraCore

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

final class LyricsFallbackTests: XCTestCase {

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

    // MARK: - Scoring

    func testExactTitleAndArtistScoresHighest() {
        let candidate = LyricsCandidate(
            id: 1,
            trackName: "Creep",
            artistName: "Radiohead",
            duration: 239
        )
        XCTAssertGreaterThanOrEqual(
            LyricsMatchScorer.score(track: track(), candidate: candidate),
            LyricsMatchScorer.minimumScore
        )
    }

    func testDifferentSongScoresBelowTheMinimum() {
        let candidate = LyricsCandidate(
            id: 2,
            trackName: "Paranoid Android",
            artistName: "Radiohead",
            duration: 383
        )
        XCTAssertLessThan(
            LyricsMatchScorer.score(track: track(), candidate: candidate),
            LyricsMatchScorer.minimumScore
        )
    }

    func testSameTitleDifferentArtistIsRejected() {
        // "Brilliant" exists by several artists — the artist has to
        // decide.
        let candidate = LyricsCandidate(
            id: 3,
            trackName: "Brilliant",
            artistName: "Someone Else",
            duration: 239
        )
        XCTAssertLessThan(
            LyricsMatchScorer.score(
                track: track(title: "Brilliant", artist: "Radiohead"),
                candidate: candidate
            ),
            LyricsMatchScorer.minimumScore
        )
    }

    func testDifferentLengthIsPenalisedButStillUsable() {
        let candidate = LyricsCandidate(
            id: 4,
            trackName: "Creep",
            artistName: "Radiohead",
            duration: 242
        )
        let score = LyricsMatchScorer.score(track: track(), candidate: candidate)
        XCTAssertGreaterThanOrEqual(score, LyricsMatchScorer.minimumScore)
    }

    func testNormalisationIgnoresCasePunctuationAndDiacritics() {
        XCTAssertEqual(LyricsMatchScorer.normalize("Café"), "cafe")
        XCTAssertEqual(LyricsMatchScorer.normalize("A-ha!"), "a ha")
        XCTAssertEqual(LyricsMatchScorer.normalize("  Radio   HEAD "), "radio head")
    }

    func testDecoratedTitleStillMatchesThePlainOne() {
        // "Creep (Remastered)" against "Creep" — one contains the other.
        let candidate = LyricsCandidate(
            id: 5,
            trackName: "Creep (Remastered)",
            artistName: "Radiohead",
            duration: 239
        )
        XCTAssertGreaterThanOrEqual(
            LyricsMatchScorer.score(track: track(), candidate: candidate),
            LyricsMatchScorer.minimumScore
        )
    }

    // MARK: - lrclib search

    func testSearchPicksTheBestScoringCandidate() async throws {
        let transport = StubGETTransport(responses: [
            .success(Data(searchJSON([
                candidateJSON(id: 10, track: "Paranoid Android", artist: "Radiohead", duration: 383),
                candidateJSON(id: 11, track: "Creep", artist: "Radiohead", duration: 239),
                candidateJSON(id: 12, track: "Creep", artist: "Someone Else", duration: 239)
            ]).utf8))
        ])
        let client = LRCLibSearchClient(transport: transport)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertEqual(lyrics.trackID, 11, "the exact match must win")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(request.url.absoluteString.hasPrefix("https://lrclib.net/api/search?"))
        XCTAssertTrue(request.url.absoluteString.contains("track_name=Creep"))
        XCTAssertTrue(request.url.absoluteString.contains("artist_name=Radiohead"))
        XCTAssertNotNil(request.headers["User-Agent"])
    }

    func testSearchKeepsSyncedLyricsSynchronised() async throws {
        let transport = StubGETTransport(responses: [
            .success(Data(searchJSON([
                candidateJSON(
                    id: 20,
                    track: "Creep",
                    artist: "Radiohead",
                    duration: 239,
                    synced: "[00:12.00]When you were here before\n[00:15.00]Couldn't look you in the eye"
                )
            ]).utf8))
        ])
        let client = LRCLibSearchClient(transport: transport)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines[0].timestamp, 12, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[0].text, "When you were here before")
    }

    func testSearchWithNoUsableCandidateIsNotFound() async {
        let transport = StubGETTransport(responses: [
            .success(Data(searchJSON([
                candidateJSON(id: 30, track: "Something Else", artist: "Another Band", duration: 100)
            ]).utf8))
        ])
        let client = LRCLibSearchClient(transport: transport)

        do {
            _ = try await client.lyrics(for: track())
            XCTFail("expected a not-found error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .notFound)
        }
    }

    func testSearchRetriesWhenTheServiceIsBusy() async throws {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 503")),
            .success(Data(searchJSON([
                candidateJSON(id: 40, track: "Creep", artist: "Radiohead", duration: 239)
            ]).utf8))
        ])
        let client = LRCLibSearchClient(transport: transport)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertEqual(lyrics.trackID, 40)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSearchWithAnEmptyArrayIsNotFound() async {
        let transport = StubGETTransport(responses: [.success(Data("[]".utf8))])
        let client = LRCLibSearchClient(transport: transport)

        do {
            _ = try await client.lyrics(for: track())
            XCTFail("expected a not-found error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .notFound)
        }
    }

    // MARK: - lyrics.ovh

    func testLyricsOvhReturnsPlainLyrics() async throws {
        let transport = StubGETTransport(responses: [
            .success(Data(#"{"lyrics":"When you were here before\nCouldn't look you in the eye"}"#.utf8))
        ])
        let client = LyricsOvhClient(transport: transport)

        let lyrics = try await client.lyrics(for: track())

        XCTAssertFalse(lyrics.isSynced)
        XCTAssertEqual(
            lyrics.plainText,
            "When you were here before\nCouldn't look you in the eye"
        )
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(request.url.absoluteString.contains("/v1/Radiohead/Creep"))
    }

    func testLyricsOvhEncodesASlashInTheArtistName() async throws {
        let transport = StubGETTransport(responses: [
            .success(Data(#"{"lyrics":"Rock on"}"#.utf8))
        ])
        let client = LyricsOvhClient(transport: transport)

        _ = try await client.lyrics(for: track(title: "Back In Black", artist: "AC/DC"))

        let request = try XCTUnwrap(transport.requests.first)
        // The slash must be escaped, not treated as a path separator.
        XCTAssertTrue(request.url.path.contains("AC%2FDC"), request.url.absoluteString)
    }

    func testLyricsOvhNotFoundIsTyped() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 404"))
        ])
        let client = LyricsOvhClient(transport: transport)

        do {
            _ = try await client.lyrics(for: track())
            XCTFail("expected a not-found error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .notFound)
        }
    }

    func testLyricsOvhEmptyLyricsIsNotFound() async {
        let transport = StubGETTransport(responses: [
            .success(Data(#"{"lyrics":"   "}"#.utf8))
        ])
        let client = LyricsOvhClient(transport: transport)

        do {
            _ = try await client.lyrics(for: track())
            XCTFail("expected a not-found error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .notFound)
        }
    }

    // MARK: - The chain

    func testChainFallsThroughToTheNextProvider() async throws {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 404")),   // exact match
            .success(Data(searchJSON([                              // search
                candidateJSON(id: 50, track: "Creep", artist: "Radiohead", duration: 239)
            ]).utf8))
        ])
        let chain = LyricsProviderChain(providers: [
            LRCLibClient(transport: transport),
            LRCLibSearchClient(transport: transport)
        ])

        let lyrics = try await chain.lyrics(for: track())

        XCTAssertEqual(lyrics.trackID, 50)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testChainReportsNotFoundWhenEveryProviderHasNothing() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 404")),
            .failure(PandoraTransportError(reason: "HTTP 404")),
            .failure(PandoraTransportError(reason: "HTTP 404"))
        ])
        let chain = LyricsProviderChain(providers: [
            LRCLibClient(transport: transport),
            LRCLibSearchClient(transport: transport),
            LyricsOvhClient(transport: transport)
        ])

        do {
            _ = try await chain.lyrics(for: track())
            XCTFail("expected a not-found error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .notFound)
        }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testChainSkipsAProviderThatReturnsEmptyLyrics() async throws {
        let transport = StubGETTransport(responses: [
            .success(Data(
                #"{"id":1,"trackName":"Creep","artistName":"Radiohead","albumName":"x","duration":239,"instrumental":false,"plainLyrics":null,"syncedLyrics":null}"#.utf8
            )),
            .success(Data(searchJSON([
                candidateJSON(id: 60, track: "Creep", artist: "Radiohead", duration: 239)
            ]).utf8))
        ])
        let chain = LyricsProviderChain(providers: [
            LRCLibClient(transport: transport),
            LRCLibSearchClient(transport: transport)
        ])

        let lyrics = try await chain.lyrics(for: track())

        XCTAssertEqual(lyrics.trackID, 60)
    }

    func testChainStopsAtTheFirstProviderThatAnswers() async throws {
        let transport = StubGETTransport(responses: [
            .success(Data(
                #"{"id":496,"trackName":"Creep","artistName":"Radiohead","albumName":"Pablo Honey","duration":239,"instrumental":false,"plainLyrics":null,"syncedLyrics":"[00:12.00]When you were here before"}"#.utf8
            ))
        ])
        let chain = LyricsProviderChain(providers: [
            LRCLibClient(transport: transport),
            LRCLibSearchClient(transport: transport)
        ])

        let lyrics = try await chain.lyrics(for: track())

        XCTAssertEqual(lyrics.trackID, 496)
        XCTAssertEqual(transport.requests.count, 1, "no fallback request when the first answers")
    }

    // MARK: - Fixtures

    private func candidateJSON(
        id: Int,
        track: String,
        artist: String,
        duration: Double,
        synced: String? = nil,
        plain: String? = "line one"
    ) -> String {
        let syncedField = synced.map { "\"\($0.jsonEscaped)\"" } ?? "null"
        let plainField = plain.map { "\"\($0.jsonEscaped)\"" } ?? "null"
        return """
        {"id":\(id),"trackName":"\(track)","artistName":"\(artist)",
        "albumName":"Some Album","duration":\(duration),"instrumental":false,
        "plainLyrics":\(plainField),"syncedLyrics":\(syncedField)}
        """
    }

    private func searchJSON(_ candidates: [String]) -> String {
        "[\(candidates.joined(separator: ","))]"
    }
}
