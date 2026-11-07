//
//  RadioBrowser.swift
//  PandoraCore
//
//  The community internet-radio directory behind Shortwave (and many
//  other players): radio-browser.info. A free, keyless, GET-only JSON
//  API served from a set of mirrors. This client keeps the same shape
//  as the Pandora side: an injected transport (tests never touch the
//  network), typed models, and malformed entries skipped — never fatal.
//
//  Reference behavior (docs at https://api.radio-browser.info and
//  GNOME Shortwave's `api` crate):
//
//  - Mirrors: several independent servers exist; a client should move
//    to another when one fails. `/json/servers` lists them; we keep a
//    small known-good default list and rotate on failure.
//  - Search/discover endpoints all live under `/json/stations/…` and
//    accept `order`, `reverse`, `hidebroken`, `limit`.
//  - `url_resolved` is the stream URL actually resolved by the server
//    (follows redirects at directory time) — preferred for playback.
//  - Playing should ping `/json/url/{stationuuid}` so the directory's
//    click counter stays meaningful (Shortwave does this; best-effort).
//  - The API asks clients to identify themselves via User-Agent.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation
#if canImport(FoundationNetworking)
// Linux (swift-corelibs-foundation): URLSession/URLRequest live here.
import FoundationNetworking
#endif

// MARK: - Flexible field access

private extension Dictionary where Key == String, Value == AnyJSON {
    /// Numbers arrive as JSON numbers or numeric strings (the directory
    /// mostly sends real numbers, but be tolerant).
    func intLike(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        if let number = value.intValue { return number }
        if let text = value.stringValue { return Int(text) }
        return nil
    }
}

// MARK: - Models

/// One directory station. Built from a `/json/stations/…` entry;
/// entries missing a uuid, a name or a resolved stream URL are skipped
/// by the client (a directory row must be playable and showable).
public struct RadioStation: Codable, Sendable, Equatable, Identifiable {
    /// The directory's stable id (`stationuuid`).
    public let uuid: String
    public let name: String
    /// The resolved stream URL (`url_resolved`) — what the player opens.
    public let streamURL: String
    public let homepageURL: String?
    public let faviconURL: String?
    /// Lowercase, comma-separated free-form tags ("jazz", "smooth jazz").
    public let tags: [String]
    public let country: String
    /// ISO 3166-1 alpha-2 code, uppercased; may be empty for uncategorized
    /// stations.
    public let countryCode: String
    public let language: String?
    /// Stream codec ("MP3", "AAC", …) as reported by the directory.
    public let codec: String
    /// Bitrate in kbps; 0 when the directory does not know.
    public let bitrate: Int
    /// Community upvotes — the default ranking signal.
    public let votes: Int
    /// Cumulative play clicks recorded by the directory.
    public let clicks: Int

    public var id: String { uuid }

    public init(
        uuid: String,
        name: String,
        streamURL: String,
        homepageURL: String? = nil,
        faviconURL: String? = nil,
        tags: [String] = [],
        country: String = "",
        countryCode: String = "",
        language: String? = nil,
        codec: String = "",
        bitrate: Int = 0,
        votes: Int = 0,
        clicks: Int = 0
    ) {
        self.uuid = uuid
        self.name = name
        self.streamURL = streamURL
        self.homepageURL = homepageURL
        self.faviconURL = faviconURL
        self.tags = tags
        self.country = country
        self.countryCode = countryCode
        self.language = language
        self.codec = codec
        self.bitrate = bitrate
        self.votes = votes
        self.clicks = clicks
    }

    /// A compact human caption ("Germany · MP3 · 128 kbps") for list rows.
    /// Empty pieces are omitted; an entirely unknown station yields "".
    public var caption: String {
        var parts: [String] = []
        if !country.isEmpty { parts.append(country) }
        if !codec.isEmpty { parts.append(codec) }
        if bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: " · ")
    }

    /// Wire entry → station; nil when the entry is unusable.
    public static func station(from entry: [String: AnyJSON]) -> RadioStation? {
        guard
            let uuid = entry["stationuuid"]?.stringValue,
            !uuid.isEmpty,
            let name = entry["name"]?.stringValue,
            !name.isEmpty
        else { return nil }
        // `url_resolved` falls back to `url` (the submitted form) — some
        // entries never got resolved by the server side. An *empty*
        // resolved URL must fall back too, not just a null one.
        let resolved = entry["url_resolved"]?.stringValue ?? ""
        let submitted = entry["url"]?.stringValue ?? ""
        let stream = resolved.isEmpty ? submitted : resolved
        guard !stream.isEmpty else { return nil }
        let tags = (entry["tags"]?.stringValue ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return RadioStation(
            uuid: uuid,
            name: name,
            streamURL: stream,
            homepageURL: entry["homepage"]?.stringValue,
            faviconURL: entry["favicon"]?.stringValue,
            tags: tags,
            country: entry["country"]?.stringValue ?? "",
            countryCode: (entry["countrycode"]?.stringValue ?? "").uppercased(),
            language: entry["language"]?.stringValue,
            codec: entry["codec"]?.stringValue ?? "",
            bitrate: entry.intLike("bitrate") ?? 0,
            votes: entry.intLike("votes") ?? 0,
            clicks: entry.intLike("clicks") ?? 0
        )
    }

    /// Decodes an array of directory entries, skipping malformed ones.
    public static func stations(from data: Data) -> [RadioStation] {
        guard let entries = try? JSONDecoder().decode([AnyJSON].self, from: data) else {
            return []
        }
        return entries.compactMap { $0.objectValue.flatMap { station(from: $0) } }
    }
}

/// One country in the directory (`/json/countries`), with how many
/// stations it carries — the discovery list's currency.
public struct RadioCountry: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    /// ISO 3166-1 alpha-2 code used by the by-country filter.
    public let code: String
    public let stationCount: Int

    public var id: String { code.isEmpty ? name : code }

    public init(name: String, code: String, stationCount: Int) {
        self.name = name
        self.code = code
        self.stationCount = stationCount
    }
}

/// One community tag (`/json/tags`) — Shortwave's genre discovery.
public struct RadioTag: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let stationCount: Int

    public var id: String { name }

    public init(name: String, stationCount: Int) {
        self.name = name
        self.stationCount = stationCount
    }
}

// MARK: - Errors

/// Typed failures of the directory client — mapped to short user copy
/// above the core, same as the Pandora error codes.
public enum RadioBrowserError: Error, Sendable, Equatable {
    case httpStatus(Int)
    case networkFailure
    /// The body was not the expected JSON shape (never happens for
    /// arrays of entries — those skip bad entries instead — only for
    /// the ping/lookup endpoints).
    case badResponse
}

// MARK: - Transport

/// GETs a URL and returns the raw body. Injected so tests never touch
/// the network (mirrors the Pandora side's `HTTPTransport`).
public protocol RadioBrowserTransport: Sendable {
    func get(url: URL) async throws -> Data
}

/// `URLSession`-backed GET transport. Radio-browser asks clients to
/// identify themselves, so the User-Agent is required.
public struct RadioURLSessionTransport: RadioBrowserTransport {
    /// `URLSession` is not Sendable on Linux corelibs — box it (same
    /// pattern as `URLSessionTransport` on the Pandora side).
    private final class SessionBox: @unchecked Sendable {
        let session: URLSession
        init(_ session: URLSession) { self.session = session }
    }

    private let box: SessionBox
    private let userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "Amphora/0.1 (personal)") {
        self.box = SessionBox(session)
        self.userAgent = userAgent
    }

    public func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await box.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RadioBrowserError.networkFailure
            }
            guard (200..<300).contains(http.statusCode) else {
                throw RadioBrowserError.httpStatus(http.statusCode)
            }
            return data
        } catch let error as RadioBrowserError {
            throw error
        } catch {
            // Detail stays sanitized — no URL material in user copy.
            throw RadioBrowserError.networkFailure
        }
    }
}

// MARK: - Client

/// The radio-browser directory client.
///
/// An actor: mirror rotation is shared state and must not race. On any
/// failure the next mirror is tried immediately within the same call;
/// only when every mirror failed does the last error surface.
public actor RadioBrowserClient {

    /// One known directory mirror (base URL without trailing slash).
    public struct Mirror: Sendable, Equatable {
        public let baseURL: String
        public init(baseURL: String) { self.baseURL = baseURL }
    }

    /// The default mirrors — independent servers run by the
    /// radio-browser project. `all.api…` round-robins via DNS; the
    /// country mirrors are tried directly.
    public static let defaultMirrors: [Mirror] = [
        Mirror(baseURL: "https://de1.api.radio-browser.info"),
        Mirror(baseURL: "https://de2.api.radio-browser.info"),
        Mirror(baseURL: "https://fi1.api.radio-browser.info"),
    ]

    private let transport: any RadioBrowserTransport
    private var mirrors: [Mirror]
    /// Where the rotation starts next — advances after every failure so
    /// a dead mirror is not retried first forever.
    private var mirrorOffset = 0

    public init(
        transport: any RadioBrowserTransport = RadioURLSessionTransport(),
        mirrors: [Mirror] = RadioBrowserClient.defaultMirrors
    ) {
        self.transport = transport
        self.mirrors = mirrors
    }

    // MARK: Discovery endpoints

    /// Full-text search by station name (`/json/stations/search`).
    /// Ranked by community votes, broken stations hidden.
    public func searchStations(name: String, limit: Int = 50) async throws -> [RadioStation] {
        let query = trimmed(name)
        guard !query.isEmpty else { return [] }
        return try await fetchStations(
            path: "/json/stations/search",
            query: [
                URLQueryItem(name: "name", value: query),
                URLQueryItem(name: "order", value: "votes"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    /// The directory's most upvoted stations (`/json/stations/topvote`).
    public func topStations(limit: Int = 50) async throws -> [RadioStation] {
        try await fetchStations(path: "/json/stations/topvote/\(limit)")
    }

    /// Stations of one country, by ISO code
    /// (`/json/stations/bycountrycodeexact/{code}`).
    public func stations(countryCode: String, limit: Int = 50) async throws -> [RadioStation] {
        let code = trimmed(countryCode).uppercased()
        guard !code.isEmpty else { return [] }
        return try await fetchStations(
            path: "/json/stations/bycountrycodeexact/\(percentEncoded(code))",
            query: Self.listQuery(limit: limit)
        )
    }

    /// Stations under one community tag (`/json/stations/bytag/{tag}`).
    public func stations(tag: String, limit: Int = 50) async throws -> [RadioStation] {
        let tag = trimmed(tag)
        guard !tag.isEmpty else { return [] }
        return try await fetchStations(
            path: "/json/stations/bytag/\(percentEncoded(tag))",
            query: Self.listQuery(limit: limit)
        )
    }

    /// Countries with at least one station, largest first
    /// (`/json/countries`).
    public func countries(limit: Int = 100) async throws -> [RadioCountry] {
        struct Wire: Decodable {
            let name: String
            let iso_3166_1: String?
            let stationcount: Int
        }
        let wire: [Wire] = try await fetchDecoded(
            path: "/json/countries",
            query: [
                URLQueryItem(name: "order", value: "stationcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return wire.map { RadioCountry(name: $0.name, code: ($0.iso_3166_1 ?? "").uppercased(), stationCount: $0.stationcount) }
    }

    /// Community tags, largest first (`/json/tags`).
    public func tags(limit: Int = 100) async throws -> [RadioTag] {
        struct Wire: Decodable {
            let name: String
            let stationcount: Int
        }
        let wire: [Wire] = try await fetchDecoded(
            path: "/json/tags",
            query: [
                URLQueryItem(name: "order", value: "stationcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return wire.map { RadioTag(name: $0.name, stationCount: $0.stationcount) }
    }

    /// Registers one play click (`/json/url/{uuid}`). Fire-and-forget on
    /// the caller's side — a failure here must never disturb playback.
    public func registerClick(uuid: String) async {
        guard !trimmed(uuid).isEmpty else { return }
        _ = try? await fetch(
            path: "/json/url/\(percentEncoded(uuid))",
            query: []
        )
    }

    // MARK: Internals

    /// The shared list ordering: most popular first, broken hidden.
    private static func listQuery(limit: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "order", value: "votes"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
    }

    private func fetchStations(path: String, query: [URLQueryItem] = []) async throws -> [RadioStation] {
        RadioStation.stations(from: try await fetch(path: path, query: query))
    }

    private func fetchDecoded<Wire: Decodable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> [Wire] {
        let data = try await fetch(path: path, query: query)
        do {
            return try JSONDecoder().decode([Wire].self, from: data)
        } catch {
            throw RadioBrowserError.badResponse
        }
    }

    /// One GET against the current mirror; on failure the next mirror is
    /// tried immediately. The rotation remembers only *failures*: after
    /// a mirror fails, subsequent calls start past it — a mirror that
    /// answered stays first until it stops answering.
    private func fetch(path: String, query: [URLQueryItem]) async throws -> Data {
        guard !mirrors.isEmpty else { throw RadioBrowserError.networkFailure }
        let start = mirrorOffset
        var lastError: Error = RadioBrowserError.networkFailure
        for attempt in 0..<mirrors.count {
            let index = (start + attempt) % mirrors.count
            let base = mirrors[index].baseURL
            var components = URLComponents(string: base + path)
            components?.queryItems = query.isEmpty ? nil : query
            guard let url = components?.url else {
                throw RadioBrowserError.networkFailure
            }
            do {
                return try await transport.get(url: url)
            } catch {
                lastError = error
                mirrorOffset = (index + 1) % mirrors.count
            }
        }
        throw lastError
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
