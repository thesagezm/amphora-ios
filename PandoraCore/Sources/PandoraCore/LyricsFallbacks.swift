//
//  LyricsFallbacks.swift
//  PandoraCore
//
//  Fallback lyrics sources, so a track whose lyrics the first provider
//  does not have still gets words.
//
//  The exact-match endpoint of lrclib (`/api/get`) is strict: it
//  matches on title **and** artist **and** album **and** duration, so
//  a wrong album name or a two-second duration difference answers
//  404 even when the lyrics exist. Two fallbacks close that gap:
//
//  1. **lrclib's own search** (`/api/search?track_name=…&artist_name=…`)
//     — the same database, but fuzzy: it answers with every record it
//     knows for the title/artist. The candidate is then scored against
//     the track (artist match, title match, duration proximity) and
//     the best one wins. This is the same idea as pithos' own
//     fallback path, which searches the database when the direct
//     lookup comes back empty.
//
//  2. **lyrics.ovh** (`https://api.lyrics.ovh/v1/{artist}/{title}`) — a
//     completely different database. It only serves plain (not
//     time-synchronised) lyrics, but it covers a lot of songs lrclib
//     does not have.
//
//  Both are pure logic + a GET transport — no UI, no AVFoundation, so
//  PandoraCore stays portable.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Candidate scoring

/// One record a search endpoint returned, before it is scored against
/// the track being played.
public struct LyricsCandidate: Sendable, Equatable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    /// The record's length in seconds, when the source sent one.
    public let duration: Double?
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public init(
        id: Int,
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        duration: Double? = nil,
        instrumental: Bool = false,
        plainLyrics: String? = nil,
        syncedLyrics: String? = nil
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    /// The lyrics this candidate carries, parsed into the app's model.
    public var lyrics: Lyrics {
        if let synced = syncedLyrics, !synced.isEmpty {
            let parsed = LRC.parse(synced)
            if parsed.isSynced {
                return Lyrics(
                    lines: parsed.lines,
                    instrumental: instrumental,
                    trackID: id
                )
            }
        }
        return Lyrics(
            plainText: plainLyrics,
            instrumental: instrumental,
            trackID: id
        )
    }
}

/// Scores a search result against the track being played.
///
/// The scoring is deliberately simple and deterministic: a wrong song
/// with the same title ("Brilliant" by one artist vs another) must not
/// win over the right one, and a live cover (different length, same
/// song) should still be usable.
public enum LyricsMatchScorer {
    /// The score below which a candidate is not the song we are looking
    /// for.
    public static let minimumScore = 30

    /// Scores `candidate` for `track`. Higher is better; a negative
    /// score means "not this song".
    public static func score(track: Track, candidate: LyricsCandidate) -> Int {
        let title = normalize(track.title)
        let artist = normalize(track.artist)
        let candidateTitle = normalize(candidate.trackName)
        let candidateArtist = normalize(candidate.artistName)

        var score = 0

        // The artist decides first: two songs can share a title
        // ("Brilliant" by several artists), and the wrong artist's
        // version is the wrong song — no amount of title agreement
        // makes up for it.
        if !artist.isEmpty, !candidateArtist.isEmpty {
            if artist == candidateArtist {
                score += 40
            } else if artist.contains(candidateArtist) || candidateArtist.contains(artist) {
                score += 20
            } else {
                // A different artist is disqualifying on its own.
                return -100
            }
        }

        // The title is the second signal.
        if !title.isEmpty, !candidateTitle.isEmpty {
            if title == candidateTitle {
                score += 50
            } else if title.contains(candidateTitle) || candidateTitle.contains(title) {
                score += 25
            } else {
                return -100
            }
        }

        // The length is a tie-breaker: a different recording of the same
        // song is usually still the right song.
        if track.duration > 0, let candidateDuration = candidate.duration {
            let difference = abs(Double(track.duration) - candidateDuration)
            if difference <= 3 {
                score += 20
            } else if difference <= 10 {
                score += 10
            } else if difference > 30 {
                score -= 15
            }
        }

        return score
    }

    /// Lower-cases, strips punctuation and diacritics, and collapses
    /// whitespace, so "ÆØÅ" / "A-ha!" / "A HA" compare equal.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US")
        )
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        return String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

// MARK: - lrclib search

/// The lrclib *search* endpoint — the fuzzy fallback for the strict
/// `/api/get` lookup.
public struct LRCLibSearchClient: LyricsProviding, Sendable {
    public static let defaultBaseURL = URL(string: "https://lrclib.net/api")!

    private let transport: any HTTPGETTransport
    private let baseURL: URL
    private let userAgent: String
    private let maxRetries: Int

    public init(
        transport: any HTTPGETTransport = URLSessionGETTransport(),
        baseURL: URL = LRCLibSearchClient.defaultBaseURL,
        userAgent: String = "Amphora (https://github.com/thesagezm/amphora-ios)",
        maxRetries: Int = 2
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.maxRetries = maxRetries
    }

    public func lyrics(for track: Track) async throws -> Lyrics {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        guard let url = components?.url else { throw LyricsError.malformedResponse }

        let data = try await fetch(url)
        let candidates = try decode([CandidateRecord].self, from: data)
            .map(\.candidate)

        guard let best = bestCandidate(for: track, among: candidates) else {
            throw LyricsError.notFound
        }
        let lyrics = best.lyrics
        if lyrics.isEmpty {
            throw LyricsError.notFound
        }
        return lyrics
    }

    /// The candidate with the best score, or nil when none scores
    /// above the minimum.
    func bestCandidate(
        for track: Track,
        among candidates: [LyricsCandidate]
    ) -> LyricsCandidate? {
        candidates
            .map { ($0, LyricsMatchScorer.score(track: track, candidate: $0)) }
            .filter { $0.1 >= LyricsMatchScorer.minimumScore }
            .max { $0.1 < $1.1 }?
            .0
    }

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

    /// One record of the search reply (the same shape `/api/get`
    /// returns, but in an array).
    struct CandidateRecord: Decodable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?

        var candidate: LyricsCandidate {
            LyricsCandidate(
                id: id,
                trackName: trackName ?? "",
                artistName: artistName ?? "",
                albumName: albumName,
                duration: duration,
                instrumental: instrumental,
                plainLyrics: plainLyrics,
                syncedLyrics: syncedLyrics
            )
        }
    }
}

// MARK: - lyrics.ovh

/// The lyrics.ovh API — a second, independent lyrics database.
///
/// It only serves plain lyrics (no timestamps), and it is keyed by
/// artist and title, so it works for songs lrclib does not have.
public struct LyricsOvhClient: LyricsProviding, Sendable {
    public static let defaultBaseURL = URL(string: "https://api.lyrics.ovh")!

    private let transport: any HTTPGETTransport
    private let baseURL: URL
    private let userAgent: String

    public init(
        transport: any HTTPGETTransport = URLSessionGETTransport(),
        baseURL: URL = LyricsOvhClient.defaultBaseURL,
        userAgent: String = "Amphora (https://github.com/thesagezm/amphora-ios)"
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.userAgent = userAgent
    }

    public func lyrics(for track: Track) async throws -> Lyrics {
        guard !track.artist.isEmpty, !track.title.isEmpty else {
            throw LyricsError.notFound
        }
        // The path components are percent-encoded by hand — an artist
        // like "AC/DC" would otherwise break the URL (and
        // `appendingPathComponent` treats a slash as a separator).
        let encodedArtist = track.artist.addingPercentEncoding(
            withAllowedCharacters: Self.pathComponentAllowed
        ) ?? track.artist
        let encodedTitle = track.title.addingPercentEncoding(
            withAllowedCharacters: Self.pathComponentAllowed
        ) ?? track.title
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = "/v1/\(encodedArtist)/\(encodedTitle)"
        guard let url = components?.url else { throw LyricsError.notFound }

        let data: Data
        do {
            data = try await transport.get(
                url: url,
                headers: ["User-Agent": userAgent]
            )
        } catch let error as PandoraTransportError where error.reason == "HTTP 404" {
            throw LyricsError.notFound
        }

        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw LyricsError.malformedResponse
        }
        let text = (reply.lyrics ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LyricsError.notFound }
        return Lyrics(plainText: text)
    }

    /// Everything a path segment may contain — but never a slash.
    private static let pathComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    /// The reply: `{"lyrics": "…"}` (or `{"error": "…"}` with a 404).
    struct Reply: Decodable {
        let lyrics: String?
    }
}

// MARK: - The chain

/// Tries several providers in order and returns the first lyrics it
/// gets.
///
/// This is what makes a missing lyric a non-event: the strict exact
/// match comes first, then the fuzzy search of the same database, then
/// a completely different database. A provider that fails is skipped —
/// only when *every* provider has nothing does the chain report
/// "not found".
public struct LyricsProviderChain: LyricsProviding, Sendable {
    private let providers: [any LyricsProviding]

    public init(providers: [any LyricsProviding]) {
        self.providers = providers
    }

    /// The chain Amphora uses: exact match → fuzzy search → a second
    /// database.
    public static func defaultChain() -> LyricsProviderChain {
        LyricsProviderChain(providers: [
            LRCLibClient(),
            LRCLibSearchClient(),
            LyricsOvhClient()
        ])
    }

    public func lyrics(for track: Track) async throws -> Lyrics {
        var lastError: Error = LyricsError.notFound
        for provider in providers {
            do {
                let lyrics = try await provider.lyrics(for: track)
                if !lyrics.isEmpty {
                    return lyrics
                }
                lastError = LyricsError.notFound
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
