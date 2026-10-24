//
//  LastFmTests.swift
//  PandoraCoreTests
//
//  Signature known-answer vectors (including the API spec's own example),
//  request shapes against a scripted transport, error-code mapping, and
//  the pithos scrobble-rule boundaries. No network in any unit test.
//

import XCTest
@testable import PandoraCore

final class LastFmTests: XCTestCase {

    // MARK: - Signature

    /// The API spec's own example (last.fm/api/authspec): params
    /// api_key=xxxxxxxx, method=auth.getSession, token=yyyyyy; the
    /// secret "ilovecher". Expected MD5 precomputed.
    func testSignatureMatchesSpecExample() {
        let signature = LastFmSigning.signature(
            [
                "api_key": "xxxxxxxx",
                "method": "auth.getSession",
                "token": "yyyyyy"
            ],
            secret: "ilovecher"
        )
        XCTAssertEqual(signature, "1333ebf6f7dec747486b6ce965cca66b")
    }

    /// `format` and `callback` are excluded from the signed string; an
    /// alphabetical sort of the remaining names is used (scrobble-shaped
    /// parameter set, MD5 precomputed).
    func testSignatureExcludesFormatAndCallbackAndSorts() {
        let base: [String: String] = [
            "api_key": "K123",
            "artist": "Artist Name",
            "duration": "213",
            "method": "track.scrobble",
            "sk": "SESS",
            "timestamp": "1690000000",
            "track": "Song Title"
        ]
        var withExcluded = base
        withExcluded["format"] = "json"
        withExcluded["callback"] = "cb"
        XCTAssertEqual(
            LastFmSigning.signature(withExcluded, secret: "SECRET"),
            "8d620eabaf3d00bf836f5b33ba078706"
        )
        XCTAssertEqual(LastFmSigning.signature(base, secret: "SECRET"),
                       "8d620eabaf3d00bf836f5b33ba078706")
    }

    // MARK: - Transport mock

    private final class MockLastFmTransport: LastFmTransport, @unchecked Sendable {
        struct RecordedRequest {
            let url: URL
            let form: Data
            let headers: [String: String]
        }

        private let lock = NSLock()
        private var recorded: [RecordedRequest] = []
        private let responses: [Result<(Int, Data), Error>]
        private var next = 0

        init(responses: [Result<(Int, Data), Error>]) {
            self.responses = responses
        }

        var requests: [RecordedRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func post(url: URL, form: Data, headers: [String: String]) async throws -> LastFmHTTPResponse {
            // Locked work lives in sync helpers: Swift 6 marks NSLock
            // lock/unlock noasync.
            let index = record(url: url, form: form, headers: headers)
            guard index < responses.count else {
                throw LastFmError.transport("mock exhausted at request \(index)")
            }
            let (status, body) = try responses[index].get()
            return LastFmHTTPResponse(statusCode: status, body: body)
        }

        private func record(url: URL, form: Data, headers: [String: String]) -> Int {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(RecordedRequest(url: url, form: form, headers: headers))
            let index = next
            next += 1
            return index
        }
    }

    // MARK: - Helpers

    /// Decodes an `application/x-www-form-urlencoded` body back into its
    /// parameters.
    private func formFields(of form: Data) -> [String: String] {
        var result: [String: String] = [:]
        let body = String(decoding: form, as: UTF8.self)
        for pair in body.split(separator: "&") {
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard halves.count == 2 else { continue }
            let key = String(halves[0]).removingPercentEncoding ?? String(halves[0])
            let value = String(halves[1]).removingPercentEncoding ?? String(halves[1])
            result[key] = value
        }
        return result
    }

    private func ok(_ json: String) -> Result<(Int, Data), Error> {
        .success((200, Data(json.utf8)))
    }

    private func makeClient(_ transport: MockLastFmTransport) -> LastFmClient {
        LastFmClient(transport: transport)
    }

    // MARK: - Authentication

    func testAuthenticateSendsMobileSessionAndDecodes() async throws {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"session":{"name":"scrobbler","key":"K-SESSION","subscriber":0}}"#)
        ])
        let session = try await makeClient(transport)
            .authenticate(username: "me@example.com", password: "hunter2")

        XCTAssertEqual(session.username, "scrobbler")
        XCTAssertEqual(session.key, "K-SESSION")
        XCTAssertFalse(session.isSubscriber)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url, LastFmClient.endpoint)
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
        let fields = formFields(of: request.form)
        XCTAssertEqual(fields["method"], "auth.getMobileSession")
        XCTAssertEqual(fields["api_key"], LastFmClient.apiKey)
        XCTAssertEqual(fields["username"], "me@example.com")
        XCTAssertEqual(fields["password"], "hunter2")
        // The signature covers everything except itself (and format).
        var signed = fields
        let sent = signed.removeValue(forKey: "api_sig")
        XCTAssertEqual(sent?.count, 32)
        XCTAssertEqual(
            sent,
            LastFmSigning.signature(signed, secret: LastFmClient.apiSecret)
        )
    }

    func testAuthenticateInvalidCredentialsMapsError4() async {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"error":4,"message":"Authentication Failed"}"#)
        ])
        do {
            _ = try await makeClient(transport).authenticate(username: "u", password: "p")
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? LastFmError, .invalidCredentials)
        }
    }

    func testAuthenticateMalformedSessionIsMalformed() async {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"session":{"name":"x"}}"#)
        ])
        do {
            _ = try await makeClient(transport).authenticate(username: "u", password: "p")
            XCTFail("expected malformed")
        } catch {
            XCTAssertEqual(error as? LastFmError, .malformed)
        }
    }

    // MARK: - Scrobbling

    func testScrobbleSendsSessionTrackAndTimestamp() async throws {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"scrobbles":{"@attr":{"accepted":1,"ignored":0},"scrobble":{"artist":{"corrected":"0"},"track":{"corrected":"0"}}}}"#)
        ])
        try await makeClient(transport).scrobble(
            sessionKey: "K-SESSION",
            artist: "Artist Name",
            track: "Song Title",
            album: "Album Name",
            timestamp: 1_690_000_000,
            duration: 213
        )

        let request = try XCTUnwrap(transport.requests.first)
        let fields = formFields(of: request.form)
        XCTAssertEqual(fields["method"], "track.scrobble")
        XCTAssertEqual(fields["sk"], "K-SESSION")
        XCTAssertEqual(fields["artist"], "Artist Name")
        XCTAssertEqual(fields["track"], "Song Title")
        XCTAssertEqual(fields["album"], "Album Name")
        XCTAssertEqual(fields["timestamp"], "1690000000")
        XCTAssertEqual(fields["duration"], "213")
        var signed = fields
        signed.removeValue(forKey: "api_sig")
        XCTAssertEqual(
            fields["api_sig"],
            LastFmSigning.signature(signed, secret: LastFmClient.apiSecret)
        )
    }

    func testScrobbleOmitsAbsentAlbumAndDuration() async throws {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"scrobbles":{"@attr":{"accepted":1,"ignored":0}}}"#)
        ])
        try await makeClient(transport).scrobble(
            sessionKey: "K",
            artist: "A",
            track: "T",
            album: nil,
            timestamp: 100,
            duration: nil
        )
        let fields = formFields(of: transport.requests[0].form)
        XCTAssertNil(fields["album"])
        XCTAssertNil(fields["duration"])
    }

    /// Unicode and reserved characters survive the form round trip.
    func testScrobbleEncodesUnicodeAndReservedCharacters() async throws {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"scrobbles":{"@attr":{"accepted":1,"ignored":0}}}"#)
        ])
        try await makeClient(transport).scrobble(
            sessionKey: "K",
            artist: "Sigur Rós",
            track: "Hoppípolla & Vaka",
            timestamp: 100
        )
        let fields = formFields(of: transport.requests[0].form)
        XCTAssertEqual(fields["artist"], "Sigur Rós")
        XCTAssertEqual(fields["track"], "Hoppípolla & Vaka")
    }

    // MARK: - Now playing

    func testUpdateNowPlayingSendsAndAccepts() async throws {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"nowplaying":{"track":{"corrected":"0"},"artist":{"corrected":"0"}}}"#)
        ])
        try await makeClient(transport).updateNowPlaying(
            sessionKey: "K-SESSION",
            artist: "Artist",
            track: "Track",
            album: "Album",
            duration: 180
        )
        let fields = formFields(of: transport.requests[0].form)
        XCTAssertEqual(fields["method"], "track.updateNowPlaying")
        XCTAssertEqual(fields["sk"], "K-SESSION")
        XCTAssertEqual(fields["artist"], "Artist")
        XCTAssertEqual(fields["album"], "Album")
        XCTAssertEqual(fields["duration"], "180")
    }

    func testUpdateNowPlayingInvalidSessionMapsError9() async {
        let transport = MockLastFmTransport(responses: [
            ok(#"{"error":9,"message":"Invalid session key"}"#)
        ])
        do {
            try await makeClient(transport).updateNowPlaying(
                sessionKey: "K", artist: "A", track: "T")
            XCTFail("expected invalidSessionKey")
        } catch {
            XCTAssertEqual(error as? LastFmError, .invalidSessionKey)
        }
    }

    // MARK: - Error mapping

    func testErrorCodesMapToTypedErrors() async {
        func error(for code: Int) async -> LastFmError {
            let transport = MockLastFmTransport(responses: [
                ok(#"{"error":\#(code),"message":"m"}"#)
            ])
            do {
                try await LastFmClient(transport: transport)
                    .scrobble(sessionKey: "K", artist: "A", track: "T", timestamp: 1)
                return .malformed
            } catch let error as LastFmError {
                return error
            } catch {
                return .malformed
            }
        }

        // XCT* autoclosures do not support `await` — hoist first.
        let rateLimited = await error(for: 29)
        let invalidSignature = await error(for: 13)
        let invalidApiKey = await error(for: 10)
        let suspended = await error(for: 26)
        XCTAssertEqual(rateLimited, .rateLimited)
        XCTAssertEqual(invalidSignature, .invalidSignature)
        XCTAssertEqual(invalidApiKey, .invalidApiKey)
        XCTAssertEqual(suspended, .rejected(code: 26, message: "m"))
    }

    func testNon2xxWithoutErrorBodyMapsHttpStatus() async {
        let transport = MockLastFmTransport(responses: [
            .success((500, Data("Bad Gateway".utf8)))
        ])
        do {
            try await makeClient(transport).updateNowPlaying(sessionKey: "K", artist: "A", track: "T")
            XCTFail("expected httpStatus(500)")
        } catch {
            XCTAssertEqual(error as? LastFmError, .httpStatus(500))
        }
    }

    func testMalformedBodyMapsMalformed() async {
        let transport = MockLastFmTransport(responses: [
            ok("this is not json")
        ])
        do {
            try await makeClient(transport).updateNowPlaying(sessionKey: "K", artist: "A", track: "T")
            XCTFail("expected malformed")
        } catch {
            XCTAssertEqual(error as? LastFmError, .malformed)
        }
    }

    // MARK: - Scrobble policy (pithos rule)

    func testPolicyMirrorsPithosRule() {
        // Ads never scrobble.
        XCTAssertFalse(ScrobblePolicy.shouldScrobble(duration: 200, position: 200, isAdvertisement: true))
        // Tracks of 30 s or shorter never scrobble (pithos: duration > 30).
        XCTAssertFalse(ScrobblePolicy.shouldScrobble(duration: 30, position: 30, isAdvertisement: false))
        // Past the midpoint, but not at it.
        XCTAssertFalse(ScrobblePolicy.shouldScrobble(duration: 100, position: 50, isAdvertisement: false))
        XCTAssertTrue(ScrobblePolicy.shouldScrobble(duration: 100, position: 50.5, isAdvertisement: false))
        // Past 240 s, but not at it.
        XCTAssertFalse(ScrobblePolicy.shouldScrobble(duration: 600, position: 240, isAdvertisement: false))
        XCTAssertTrue(ScrobblePolicy.shouldScrobble(duration: 600, position: 241, isAdvertisement: false))
        // Early skip: neither rule met.
        XCTAssertFalse(ScrobblePolicy.shouldScrobble(duration: 600, position: 30, isAdvertisement: false))
    }

    // MARK: - Form encoding

    func testPercentEncodedFormRoundTrips() {
        let form = LastFmClient.percentEncodedForm([
            "b": "two words",
            "a": "at&sign=plus+tilde~",
            "c": "Sigur Rós"
        ])
        // Three pairs, sorted by key, strict percent-encoding ('~' and
        // other RFC 3986 unreserved characters stay literal).
        XCTAssertEqual(form.split(separator: "&").count, 3)
        XCTAssertTrue(form.hasPrefix("a=at%26sign%3Dplus%2Btilde~&"))
        XCTAssertEqual(
            LastFmClient.percentEncodedForm(["a": "two words"]),
            "a=two%20words"
        )
        XCTAssertEqual(
            LastFmClient.percentEncodedForm(["c": "Sigur Rós"]),
            "c=Sigur%20R%C3%B3s"
        )
        // No raw space, '&', '=' or '+' ever survives inside a value.
        XCTAssertFalse(form.contains(" "))
        for pair in form.split(separator: "&") {
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            XCTAssertEqual(halves.count, 2)
            if halves.count == 2 {
                XCTAssertFalse(halves[1].contains("+"))
                XCTAssertFalse(halves[1].contains("&"))
            }
        }
    }
}
