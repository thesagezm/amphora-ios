//
//  LastFm.swift
//  PandoraCore
//
//  Last.fm scrobbling client (AudioScrobbler 2.0 web services). Pure
//  logic — no UI, no AVFoundation — so the Android port can reuse it.
//
//  Protocol, verified 2026-10-24 against the Last.fm API documentation:
//
//  - Endpoint: POST https://ws.audioscrobbler.com/2.0/ with
//    `application/x-www-form-urlencoded` parameters, `format=json`.
//  - Signing (last.fm/api/authspec): all parameters except `format` and
//    `callback`, ordered alphabetically by name, concatenated as
//    <name><value>, the API secret appended, then MD5 — a 32-character
//    lowercase hexadecimal hash.
//  - `auth.getMobileSession` (last.fm/api/show/auth.getMobileSession):
//    `username` + `password` (plain text; the `authToken =
//    md5(username + md5(password))` variant is the deprecated one),
//    POST over HTTPS, no session needed. Reply
//    `{"session": {"name", "key", "subscriber"}}`. Pithos authenticates
//    through the web flow instead (pithos `plugins/lastfm.py` opens a
//    browser and polls for the session key) — that flow needs a URL
//    scheme callback Amphora cannot register in LiveContainer, so the
//    documented mobile flow is used here. The API key/secret pair is
//    Pithos's public pair (`plugins/lastfm.py:25`), the same class of
//    public client identity as Pandora's partner credentials.
//  - `track.updateNowPlaying`: required `artist`, `track`, `sk`;
//    optional `album`, `duration`, `albumArtist`.
//  - `track.scrobble`: required `artist`, `track`, `timestamp` (UNIX
//    seconds — when the track *started* playing), `sk`; optional
//    `album`, `duration`, `albumArtist`. Single scrobbles may omit the
//    `artist[0]`-style index (0 ≤ i ≤ 49 for batches; Amphora sends one
//    at a time).
//  - Errors (JSON): `{"error": <code>, "message": "…"}` — 4 auth
//    failed, 9 invalid session key, 10 invalid API key, 13 invalid
//    signature, 29 rate limit exceeded.
//  - Scrobble rule (pithos `plugins/lastfm.py` `_on_song_ended`):
//    scrobble when the track is not an ad, is longer than 30 s, and was
//    played past 240 s or past its midpoint —
//    `not is_ad and duration > 30 and (position > 240 or position >
//    duration / 2)`. `ScrobblePolicy` implements exactly that.
//

import Foundation
import CryptoSwift
#if canImport(FoundationNetworking)
// Linux (swift-corelibs-foundation): URLSession lives here.
import FoundationNetworking
#endif

// MARK: - Models

/// An established Last.fm session (`session.name` / `key` / `subscriber`).
/// Codable so the app can persist the key in the Keychain as-is.
public struct LastFmSession: Codable, Sendable, Equatable {
    public let username: String
    public let key: String
    public let isSubscriber: Bool

    public init(username: String, key: String, isSubscriber: Bool) {
        self.username = username
        self.key = key
        self.isSubscriber = isSubscriber
    }
}

public enum LastFmError: Error, Equatable, Sendable {
    /// Error 4 — wrong username/password (auth.getMobileSession).
    case invalidCredentials
    /// Error 9 — the session key was rejected; the user must re-authenticate.
    case invalidSessionKey
    /// Error 10.
    case invalidApiKey
    /// Error 13.
    case invalidSignature
    /// Error 29 — back off; never retry in a tight loop.
    case rateLimited
    /// Any other `{"error": code, "message": …}` reply.
    case rejected(code: Int, message: String)
    /// A non-2xx reply whose body carried no Last.fm error object.
    case httpStatus(Int)
    /// A 2xx reply whose body was not parseable JSON.
    case malformed
    /// The request never left (network failure).
    case transport(String)
}

// MARK: - Signing

public enum LastFmSigning {

    /// The AudioScrobbler request signature: parameters sorted by name
    /// (ASCII order), concatenated `<name><value>`, the secret appended,
    /// MD5 as lowercase hex. `format` and `callback` are excluded.
    public static func signature(_ parameters: [String: String], secret: String) -> String {
        let signed = parameters
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined()
        return hexMD5(signed + secret)
    }

    static func hexMD5(_ string: String) -> String {
        let digest = Digest.md5(Array(string.utf8))
        // Int (not UInt8): %x varargs promotion is unreliable in
        // swift-corelibs-foundation on Linux CI (same as PandoraCrypto).
        return digest.map { String(format: "%02x", Int($0)) }.joined()
    }
}

// MARK: - Scrobble policy

public enum ScrobblePolicy {

    /// Pithos's scrobble decision (`plugins/lastfm.py`): the track is not
    /// an advertisement, is longer than 30 seconds, and was played past
    /// 240 seconds or past its midpoint. `position` is how far into the
    /// track playback reached when it ended (natural end or skip).
    public static func shouldScrobble(
        duration: TimeInterval,
        position: TimeInterval,
        isAdvertisement: Bool
    ) -> Bool {
        !isAdvertisement
            && duration > 30
            && (position > 240 || position > duration / 2)
    }
}

// MARK: - Transport

/// A form-POST reply, *including* the status code (some Last.fm failures
/// arrive as non-2xx without a JSON error body).
public struct LastFmHTTPResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol LastFmTransport: Sendable {
    func post(url: URL, form: Data, headers: [String: String]) async throws -> LastFmHTTPResponse
}

/// `URLSession`-backed transport. `URLSession` is thread-safe; Linux's
/// corelibs type just lacks the `Sendable` conformance, so it is boxed.
public struct URLSessionLastFmTransport: LastFmTransport {
    private final class SessionBox: @unchecked Sendable {
        let session: URLSession
        init(_ session: URLSession) { self.session = session }
    }

    private let box: SessionBox

    public init(session: URLSession = .shared) {
        self.box = SessionBox(session)
    }

    public func post(url: URL, form: Data, headers: [String: String]) async throws -> LastFmHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = form
        do {
            let (data, response) = try await box.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LastFmError.transport("non-HTTP response")
            }
            return LastFmHTTPResponse(statusCode: http.statusCode, body: data)
        } catch let error as LastFmError {
            throw error
        } catch {
            throw LastFmError.transport("network failure")
        }
    }
}

// MARK: - Client

/// The Last.fm web-services client. Stateless and `Sendable`; the session
/// key is passed per call so storage/re-auth stays with the owner.
public struct LastFmClient: Sendable {

    public static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    /// Pithos's public API pair (`pithos/plugins/lastfm.py:25-26`) — a
    /// public client identity, not a user credential.
    public static let apiKey = "997f635176130d5d6fe3a7387de601a8"
    public static let apiSecret = "3243b876f6bf880b923a3c9fb955720c"

    private let transport: any LastFmTransport
    private let userAgent: String

    public init(
        transport: any LastFmTransport = URLSessionLastFmTransport(),
        userAgent: String = "Amphora"
    ) {
        self.transport = transport
        self.userAgent = userAgent
    }

    /// `auth.getMobileSession` — exchanges Last.fm credentials for a
    /// session key. POST over HTTPS per the docs.
    public func authenticate(username: String, password: String) async throws -> LastFmSession {
        var parameters: [String: String] = [
            "method": "auth.getMobileSession",
            "api_key": Self.apiKey,
            "username": username,
            "password": password
        ]
        parameters["api_sig"] = LastFmSigning.signature(parameters, secret: Self.apiSecret)
        let body = try await post(parameters: parameters)
        guard let object = try Self.parseObject(body) else { throw LastFmError.malformed }
        if let error = Self.error(from: object) { throw error }
        guard let session = object["session"]?.objectValue,
              let key = session["key"]?.stringValue, !key.isEmpty else {
            throw LastFmError.malformed
        }
        return LastFmSession(
            username: session["name"]?.stringValue ?? username,
            key: key,
            isSubscriber: session["subscriber"]?.intValue == 1
        )
    }

    /// `track.updateNowPlaying` — updates the user's Last.fm profile page
    /// while the track plays. Fire-and-forget semantics are the caller's
    /// concern; the call itself reports failures.
    public func updateNowPlaying(
        sessionKey: String,
        artist: String,
        track: String,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) async throws {
        var parameters: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": Self.apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": track
        ]
        if let album, !album.isEmpty { parameters["album"] = album }
        if let duration, duration > 0 { parameters["duration"] = String(Int(duration)) }
        parameters["api_sig"] = LastFmSigning.signature(parameters, secret: Self.apiSecret)
        let body = try await post(parameters: parameters)
        guard let object = try Self.parseObject(body) else { throw LastFmError.malformed }
        if let error = Self.error(from: object) { throw error }
        guard object["nowplaying"] != nil else { throw LastFmError.malformed }
    }

    /// `track.scrobble` — one scrobble. `timestamp` is UNIX seconds for
    /// when the track started playing (not when it ended). Single
    /// scrobbles omit the `artist[0]` bracket notation (documented).
    public func scrobble(
        sessionKey: String,
        artist: String,
        track: String,
        album: String? = nil,
        timestamp: Int,
        duration: TimeInterval? = nil
    ) async throws {
        var parameters: [String: String] = [
            "method": "track.scrobble",
            "api_key": Self.apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": track,
            "timestamp": String(timestamp)
        ]
        if let album, !album.isEmpty { parameters["album"] = album }
        if let duration, duration > 0 { parameters["duration"] = String(Int(duration)) }
        parameters["api_sig"] = LastFmSigning.signature(parameters, secret: Self.apiSecret)
        let body = try await post(parameters: parameters)
        guard let object = try Self.parseObject(body) else { throw LastFmError.malformed }
        if let error = Self.error(from: object) { throw error }
        guard object["scrobbles"] != nil else { throw LastFmError.malformed }
    }

    // MARK: Internals (test seams)

    func post(parameters: [String: String]) async throws -> Data {
        let form = Self.percentEncodedForm(parameters)
        let response: LastFmHTTPResponse
        do {
            response = try await transport.post(
                url: Self.endpoint,
                form: Data(form.utf8),
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "User-Agent": userAgent
                ]
            )
        } catch let error as LastFmError {
            throw error
        } catch {
            throw LastFmError.transport("network failure")
        }
        // Parse the body first: failures usually arrive as HTTP 200 with
        // a JSON error object; non-2xx without one is its own failure.
        if let object = try? Self.parseObject(response.body),
           let error = Self.error(from: object) {
            throw error
        }
        guard (200...299).contains(response.statusCode) else {
            throw LastFmError.httpStatus(response.statusCode)
        }
        return response.body
    }

    private static func parseObject(_ data: Data) throws -> [String: AnyJSON]? {
        guard !data.isEmpty else { return nil }
        do {
            let decoded = try JSONDecoder().decode(AnyJSON.self, from: data)
            return decoded.objectValue
        } catch {
            throw LastFmError.malformed
        }
    }

    /// Maps `{"error": code, "message": …}` to a typed error; `code`
    /// tolerates number-or-string.
    static func error(from object: [String: AnyJSON]) -> LastFmError? {
        guard let errorField = object["error"], errorField != .null else { return nil }
        let code = errorField.intValue ?? errorField.stringValue.flatMap(Int.init) ?? 0
        let message = object["message"]?.stringValue ?? ""
        switch code {
        case 4: return .invalidCredentials
        case 9: return .invalidSessionKey
        case 10: return .invalidApiKey
        case 13: return .invalidSignature
        case 29: return .rateLimited
        default: return .rejected(code: code, message: message)
        }
    }

    /// `application/x-www-form-urlencoded` with strict percent-encoding
    /// (RFC 3986 unreserved only — `&`, `+`, `=` inside values must never
    /// survive; spaces become %20).
    static func percentEncodedForm(_ parameters: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        return parameters
            .sorted { $0.key < $1.key }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
    }
}
