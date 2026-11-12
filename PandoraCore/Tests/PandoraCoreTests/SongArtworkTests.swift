//
//  SongArtworkTests.swift
//  PandoraCoreTests
//
//  The iTunes Search artwork client, against scripted GET responses.
//  No network in any unit test.
//
//  The response shape is the one the live service returns (verified
//  against itunes.apple.com/search this session); the motivating
//  refusal case is real: a "Céline Dion" query answered with an
//  "Olivier Dion" track — and the top window is *full* of other
//  artists for that song (Floran, Olivier Dion ×2, Stromae, Rose were
//  its first five answers live). The client scans the window and runs
//  an artist-only second pass; these tests script both passes.
//

import XCTest
@testable import PandoraCore

final class SongArtworkTests: XCTestCase {

    // MARK: Fixtures

    /// One iTunes result as JSON, with only the fields the client
    /// reads; the API sends many more and they are ignored here too.
    private func resultJSON(
        artist: String?,
        track: String?,
        artwork: String? = "https://is1-ssl.mzstatic.com/image/thumb/Music/1.jpg/100x100bb.jpg"
    ) -> String {
        var fields: [String] = []
        if let artist { fields.append(#""artistName": "\#(artist)""#) }
        if let track { fields.append(#""trackName": "\#(track)""#) }
        if let artwork { fields.append(#""artworkUrl100": "\#(artwork)""#) }
        fields.append(#""collectionName": "An album""#)
        return "{\(fields.joined(separator: ", "))"
            + ", \"kind\": \"song\", \"trackId\": 1}"
    }

    private func searchJSON(_ results: [String]) -> Data {
        Data("""
        {"resultCount": \(results.count), "results": [\(results.joined(separator: ", "))]}
        """.utf8)
    }

    private func success(_ data: Data) -> Result<Data, Error> { .success(data) }

    /// A client whose first pass answers `first`. When the first pass
    /// finds nothing verified, the client runs the artist-only second
    /// pass — `second` scripts it (default: empty results).
    private func makeClient(
        _ first: Result<Data, Error>,
        second: Result<Data, Error>? = nil
    ) -> ITunesSongArtworkClient {
        let secondResponse = second ?? success(searchJSON([]))
        return ITunesSongArtworkClient(
            transport: StubGETTransport(responses: [first, secondResponse])
        )
    }

    private func makeClient(_ responses: [Result<Data, Error>]) -> ITunesSongArtworkClient {
        ITunesSongArtworkClient(transport: StubGETTransport(responses: responses))
    }

    // MARK: The wire request

    func testRequestCarriesTermEntityAndWindow() async throws {
        let transport = StubGETTransport(responses: [
            success(searchJSON([])),
            success(searchJSON([])),
        ])
        let client = ITunesSongArtworkClient(transport: transport)
        _ = try await client.artwork(forArtist: "Céline Dion", title: "Tous les chemins")
        let request = try XCTUnwrap(transport.requests.first)
        let url = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(url.queryItems)
        XCTAssertEqual(query.value(for: "term"), "Céline Dion Tous les chemins")
        XCTAssertEqual(query.value(for: "entity"), "song")
        XCTAssertEqual(query.value(for: "limit"), "25")
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(url.path, "/search")
        // The lookup sends no headers.
        XCTAssertTrue(request.headers.isEmpty)
    }

    // MARK: The happy path

    func testMatchingResultYieldsArtwork() async throws {
        let client = makeClient(success(searchJSON([resultJSON(
            artist: "Céline Dion",
            track: "Tous les chemins mènent à l'amour"
        )])))
        let found = try await client.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins mènent à l'amour"
        )
        let artwork = try XCTUnwrap(found)
        XCTAssertEqual(
            artwork.artworkURL.absoluteString,
            "https://is1-ssl.mzstatic.com/image/thumb/Music/1.jpg/100x100bb.jpg"
        )
    }

    func testVerifiedMatchBelowTheTopResultIsFound() async throws {
        // The live case: the top of the window is other artists' same-
        // titled songs; the asked-for song sits further down. The scan
        // must find it — and stop after the first pass.
        let client = makeClient(success(searchJSON([
            resultJSON(artist: "Floran", track: "Tous les chemins mènent à toi"),
            resultJSON(artist: "Olivier Dion", track: "Tous les chemins"),
            resultJSON(artist: "Céline Dion", track: "Tous les chemins mènent à l'amour"),
        ])))
        let artwork = try await client.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins mènent à l'amour"
        )
        XCTAssertNotNil(artwork)
    }

    func testArtistOnlySecondPassFindsTheSongTheCombinedQueryMissed() async throws {
        let stub = StubGETTransport(responses: [
            success(searchJSON([resultJSON(
                artist: "Olivier Dion",
                track: "Tous les chemins mènent à l'amour"
            )])),
            success(searchJSON([resultJSON(
                artist: "Céline Dion",
                track: "Tous les chemins mènent à l'amour"
            )])),
        ])
        let client = ITunesSongArtworkClient(transport: stub)
        let artwork = try await client.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins mènent à l'amour"
        )
        XCTAssertNotNil(artwork)
        // Two requests: the combined term, then the artist alone.
        XCTAssertEqual(stub.requests.count, 2)
        let second = try XCTUnwrap(
            URLComponents(url: stub.requests[1].url, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(second.queryItems?.value(for: "term"), "Céline Dion")
    }

    // MARK: Size tokens

    func testLargeArtworkReplacesTheSizeToken() {
        let artwork = SongArtwork(artworkURL: URL(
            string: "https://is1-ssl.mzstatic.com/image/thumb/Music/1.jpg/100x100bb.jpg"
        )!)
        XCTAssertEqual(
            artwork.largeArtworkURL.absoluteString,
            "https://is1-ssl.mzstatic.com/image/thumb/Music/1.jpg/600x600bb.jpg"
        )
    }

    func testArtworkWithoutSizeTokenIsReturnedUnchanged() {
        let url = URL(string: "https://example.com/cover.jpg")!
        let artwork = SongArtwork(artworkURL: url)
        XCTAssertEqual(artwork.largeArtworkURL, url)
    }

    // MARK: The verification — a wrong answer yields no artwork

    func testWrongArtistIsRefused() async throws {
        // The real case: the fuzzy search answered a "Céline Dion"
        // query with an "Olivier Dion" track — and nothing else in
        // either pass is the asked-for song. No artwork, never a
        // wrong cover.
        let client = makeClient(
            success(searchJSON([resultJSON(
                artist: "Olivier Dion",
                track: "Tous les chemins mènent à l'amour"
            )])),
            second: success(searchJSON([resultJSON(
                artist: "Olivier Dion",
                track: "Tous les chemins mènent à l'amour"
            )]))
        )
        let artwork = try await client.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins mènent à l'amour"
        )
        XCTAssertNil(artwork)
    }

    func testDifferentTitleIsRefused() async throws {
        let client = makeClient(success(searchJSON([resultJSON(
            artist: "Céline Dion",
            track: "Un tout autre titre"
        )])))
        let artwork = try await client.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins"
        )
        XCTAssertNil(artwork)
    }

    func testGuestArtistIsAccepted() async throws {
        // Stations announce the guests ("Céline Dion feat. …") — the
        // primary-artist comparison accepts it, the guest is not
        // promoted to the artist.
        let client = makeClient(success(searchJSON([resultJSON(
            artist: "Céline Dion feat. a stranger",
            track: "Tous les chemins mènent à l'amour"
        )])))
        let artwork = try await client.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins mènent à l'amour"
        )
        XCTAssertNotNil(artwork)
    }

    func testDiacriticsAndCaseDoNotRefuse() async throws {
        // "Céline" vs "celine", "Beyoncé" vs "beyonce" — same artist.
        let client = makeClient(success(searchJSON([resultJSON(
            artist: "beyonce",
            track: "Halo"
        )])))
        let artwork = try await client.artwork(forArtist: "Beyoncé", title: "Halo")
        XCTAssertNotNil(artwork)
    }

    func testTitleVariantIsAcceptedByLooseContainment() async throws {
        // Stations announce "Title (Radio Edit)" / "Title - Live"; the
        // store may carry the plain form. Either containment matches.
        let decorated = makeClient(success(searchJSON([resultJSON(
            artist: "Céline Dion",
            track: "Tous les chemins (Radio Edit)"
        )])))
        let variant = try await decorated.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins"
        )
        XCTAssertNotNil(variant)

        let reversed = makeClient(success(searchJSON([resultJSON(
            artist: "Céline Dion",
            track: "Tous les chemins"
        )])))
        let other = try await reversed.artwork(
            forArtist: "Céline Dion",
            title: "Tous les chemins mènent à l'amour"
        )
        XCTAssertNotNil(other)
    }

    // MARK: Empty / broken answers

    func testNoResultsYieldsNoArtwork() async throws {
        let client = makeClient(success(searchJSON([])))
        let artwork = try await client.artwork(forArtist: "Nobody", title: "Nothing")
        XCTAssertNil(artwork)
    }

    func testResultWithoutArtworkURLYieldsNoArtwork() async throws {
        let client = makeClient(success(searchJSON(
            [resultJSON(artist: "Céline Dion", track: "Halo", artwork: nil)]
        )))
        let artwork = try await client.artwork(forArtist: "Céline Dion", title: "Halo")
        XCTAssertNil(artwork)
    }

    func testResultWithoutArtistOrTrackFieldsIsRefused() async throws {
        let client = makeClient(success(
            searchJSON([resultJSON(artist: nil, track: nil)])
        ))
        let artwork = try await client.artwork(forArtist: "Céline Dion", title: "Halo")
        XCTAssertNil(artwork)
    }

    func testMalformedJSONThrows() async {
        let client = makeClient(success(Data("<html>503</html>".utf8)))
        do {
            _ = try await client.artwork(forArtist: "Céline Dion", title: "Halo")
            XCTFail("expected malformedResponse")
        } catch {
            XCTAssertEqual(error as? SongArtworkError, .malformedResponse)
        }
    }

    func testTransportFailurePropagates() async {
        let client = makeClient(.failure(PandoraTransportError(reason: "network failure")))
        do {
            _ = try await client.artwork(forArtist: "Céline Dion", title: "Halo")
            XCTFail("expected the transport error")
        } catch let error as PandoraTransportError {
            XCTAssertEqual(error.reason, "network failure")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: The normalization itself

    func testNormalizationFoldsDiacriticsCaseAndWhitespace() {
        XCTAssertEqual(ITunesSongArtworkClient.normalized("  Céline  DION "), "celine dion")
        XCTAssertEqual(ITunesSongArtworkClient.normalized("Beyoncé"), "beyonce")
        XCTAssertEqual(ITunesSongArtworkClient.normalized("Björk"), "bjork")
    }

    func testPrimaryArtistCutsTheGuests() {
        XCTAssertEqual(
            ITunesSongArtworkClient.primaryArtist("celine dion feat. a stranger"),
            "celine dion"
        )
        XCTAssertEqual(
            ITunesSongArtworkClient.primaryArtist("milow & anouk"),
            "milow"
        )
        XCTAssertEqual(ITunesSongArtworkClient.primaryArtist("k's choice featuring sarah"), "k's choice")
    }

    func testPrimaryArtistNeverCutsAnArtistAway() {
        // An artist *named* by a marker word keeps its full name.
        XCTAssertEqual(ITunesSongArtworkClient.primaryArtist("with"), "with")
        XCTAssertEqual(ITunesSongArtworkClient.primaryArtist("feat"), "feat")
    }
}

private extension [URLQueryItem] {
    func value(for name: String) -> String? {
        first { $0.name == name }?.value
    }
}
