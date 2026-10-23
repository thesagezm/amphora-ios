//
//  LyricsProvider.swift
//  PandoraCore
//
//  Fetches time-synchronised lyrics from lrclib.net and, when the lyrics
//  are not in English, an English translation from a translation service.
//
//  **lrclib.net** (https://lrclib.net) — a free, open lyrics database
//  with a documented JSON API. The endpoints and response fields were
//  verified against the live service and against the server's own source
//  (`github.com/tranxuanthang/lrclib`, `server/src/router.rs`):
//
//    - `GET /api/get?artist_name=…&track_name=…&album_name=…&duration=…`
//      → one track record (404 when nothing matches)
//    - `GET /api/get/{id}` → one track record by id
//    - `GET /api/search?track_name=…&artist_name=…` → an array of records
//
//  A record looks like:
//
//    { "id": 496, "name": "Creep", "trackName": "Creep",
//      "artistName": "Radiohead", "albumName": "Pablo Honey",
//      "duration": 239.0, "instrumental": false, "hasWordSync": false,
//      "plainLyrics": "…", "syncedLyrics": "[00:12.00]…", "lyricsfile": null }
//
//  The service asks clients to identify themselves with a `User-Agent`
//  (it also accepts `Lrclib-Client` / `X-User-Agent`), and answers
//  `503 {"name":"ServerOverloaded"}` when it is busy — that is retried,
//  not reported as an error.
//
//  **Translation**: lrclib itself has no translation endpoint, so the
//  English line comes from a separate translation service (the
//  `translate_a` endpoint of Google Translate, with `sl=auto` so the
//  source language is detected). The detected language comes back in the
//  response, so English lyrics are recognised and left alone.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Transport

/// A minimal GET transport, so the lyrics client never talks to
/// `URLSession` directly and can be tested with a stub.
public protocol HTTPGETTransport: Sendable {
    func get(url: URL, headers: [String: String]) async throws -> Data
}

/// `URLSession`-backed GET transport. `URLSession` is thread-safe; Linux's
/// corelibs type just lacks the `Sendable` conformance, so it is boxed.
public struct URLSessionGETTransport: HTTPGETTransport {
    private final class SessionBox: @unchecked Sendable {
        let session: URLSession
        init(_ session: URLSession) { self.session = session }
    }

    private let box: SessionBox

    public init(session: URLSession = .shared) {
        self.box = SessionBox(session)
    }

    public func get(url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (data, response) = try await box.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PandoraTransportError(reason: "non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw PandoraTransportError(reason: "HTTP \(http.statusCode)")
            }
            return data
        } catch let error as PandoraTransportError {
            throw error
        } catch {
            throw PandoraTransportError(reason: "network failure")
        }
    }
}

// MARK: - Errors

public enum LyricsError: Error, Sendable, Equatable {
    /// The lyrics service is busy (HTTP 503) — the caller may retry.
    case serviceBusy
    /// The service answered with something unexpected.
    case malformedResponse
    /// The track has no lyrics at all.
    case notFound
}

// MARK: - Provider

/// Fetches lyrics for a track.
public protocol LyricsProviding: Sendable {
    func lyrics(for track: Track) async throws -> Lyrics
}

/// The lrclib.net client.
public struct LRCLibClient: LyricsProviding, Sendable {
    /// The service's API root.
    public static let defaultBaseURL = URL(string: "https://lrclib.net/api")!

    private let transport: any HTTPGETTransport
    private let baseURL: URL
    /// The identifying string the service asks for.
    private let userAgent: String
    /// How many times a busy service is retried.
    private let maxRetries: Int

    public init(
        transport: any HTTPGETTransport = URLSessionGETTransport(),
        baseURL: URL = LRCLibClient.defaultBaseURL,
        userAgent: String = "Amphora (https://github.com/thesagezm/amphora-ios)",
        maxRetries: Int = 2
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.maxRetries = maxRetries
    }

    /// Looks the track up by its metadata (title / artist / album /
    /// duration) and returns its lyrics.
    public func lyrics(for track: Track) async throws -> Lyrics {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("get"),
            resolvingAgainstBaseURL: false
        )
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        if !track.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if track.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(track.duration)))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw LyricsError.malformedResponse }

        let data = try await fetch(url)
        let record = try decode(Record.self, from: data)
        return Lyrics(
            lines: record.syncedLyrics.map { LRC.parse($0).lines } ?? [],
            plainText: record.syncedLyrics == nil ? record.plainLyrics : nil,
            instrumental: record.instrumental,
            trackID: record.id
        )
    }

    /// One request with a retry when the service reports it is busy.
    private func fetch(_ url: URL) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await transport.get(
                    url: url,
                    headers: ["User-Agent": userAgent, "Lrclib-Client": userAgent]
                )
            } catch let error as PandoraTransportError where error.reason == "HTTP 503" {
                attempt += 1
                if attempt > maxRetries { throw LyricsError.serviceBusy }
                // A short pause before trying again — the service asks
                // clients to retry in a moment.
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            } catch let error as PandoraTransportError where error.reason == "HTTP 404" {
                throw LyricsError.notFound
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LyricsError.malformedResponse
        }
    }

    /// One lyric record (the shape lrclib returns for a track).
    struct Record: Decodable {
        let id: Int
        let name: String?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?
    }
}

// MARK: - Translation

/// Translates lyric lines into English.
public protocol LyricsTranslating: Sendable {
    /// The English version of `lines`, or nil when the lines are already
    /// in English (or nothing could be translated).
    func englishTranslation(of lines: [String]) async -> [String]?
}

/// The Google `translate_a` endpoint with automatic source-language
/// detection. The response is
/// `[[["translated","original",…]],null,"<detected source>",…]`.
public struct GoogleTranslateClient: LyricsTranslating, Sendable {
    /// The translation endpoint.
    public static let defaultEndpoint = URL(
        string: "https://translate.googleapis.com/translate_a/single"
    )!

    private let transport: any HTTPGETTransport
    private let endpoint: URL
    private let userAgent: String

    public init(
        transport: any HTTPGETTransport = URLSessionGETTransport(),
        endpoint: URL = GoogleTranslateClient.defaultEndpoint,
        userAgent: String = "Amphora (https://github.com/thesagezm/amphora-ios)"
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.userAgent = userAgent
    }

    public func englishTranslation(of lines: [String]) async -> [String]? {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return nil }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components?.url else { return nil }

        guard let data = try? await transport.get(
            url: url,
            headers: ["User-Agent": userAgent]
        ) else { return nil }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return nil
        }
        // Already English — no translation needed.
        let detected = response.detectedSourceLanguage?.lowercased() ?? ""
        if detected == "en" || detected.hasPrefix("en-") { return nil }
        // The service keeps the line breaks, so the segments line up with
        // the input lines one-to-one.
        guard response.segments.count == lines.count else { return nil }
        return response.segments.map(\.translated)
    }

    /// The service's reply: `[[segments], null, detectedLanguage, …]`.
    struct Response: Decodable {
        struct Segment: Decodable {
            let translated: String
            let original: String

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                translated = try container.decode(String.self)
                original = try container.decode(String.self)
            }
        }

        let segments: [Segment]
        let detectedSourceLanguage: String?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            segments = try container.decode([Segment].self)
            // The second element is a placeholder (`null`).
            _ = try container.decode([Segment]?.self)
            detectedSourceLanguage = try container.decode(String?.self)
        }
    }
}
