//
//  SongArtwork.swift
//  PandoraCore
//
//  Song artwork for a radio station's *identified* song, from the
//  iTunes Search API. A radio station announces "Artist - Title" in
//  its ICY metadata — nothing more — so the cover has to be looked up
//  by that pair. The station's own tile stays the fallback in the app.
//
//  The lookup is deliberately distrustful. The search answers the
//  *best fuzzy match*, which is not always the asked-for song — the
//  motivating case, observed live while building this: a query for
//  "Céline Dion" answered with a track by "Olivier Dion". A wrong
//  cover is worse than no cover, so the answer is verified before it
//  is trusted:
//
//  - **artist must match exactly** after normalization (lowercase,
//    diacritics folded — "Céline" == "celine"), with a primary-artist
//    tolerance for guests the station announces and the store does not
//    ("X feat. Y" is still X's song);
//  - **title must match loosely** — containment either way, because
//    stations announce variants ("Title (Radio Edit)", "Title - Live")
//    that still refer to the same song.
//
//  A result that fails the check yields **no artwork**, not a guess.
//  The lookup runs two passes (combined "artist title" term, then the
//  artist alone) and scans each window — the details are on the
//  client struct below.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - The result

/// The cover art found for one song.
public struct SongArtwork: Sendable, Equatable {
    /// The artwork URL the API returned (its 100×100 size).
    public let artworkURL: URL
    /// The same artwork at 600×600 — the source the full player uses.
    /// Falls back to `artworkURL` when the URL does not carry the
    /// size token the API normally embeds.
    public let largeArtworkURL: URL

    public init(artworkURL: URL) {
        self.artworkURL = artworkURL
        self.largeArtworkURL = Self.sixHundred(of: artworkURL)
    }

    public init(artworkURL: URL, largeArtworkURL: URL) {
        self.artworkURL = artworkURL
        self.largeArtworkURL = largeArtworkURL
    }

    /// The API's artwork URLs end in a size token like
    /// `100x100bb.jpg`; asking for the large cover is the same URL
    /// with `600x600` in its place. Anything that does not carry the
    /// token is returned unchanged — the app scales what it gets.
    static func sixHundred(of url: URL) -> URL {
        let string = url.absoluteString
        guard string.contains("100x100") else { return url }
        return URL(string: string.replacingOccurrences(of: "100x100", with: "600x600")) ?? url
    }
}

// MARK: - Errors

public enum SongArtworkError: Error, Sendable, Equatable {
    /// The service answered with something that does not decode.
    case malformedResponse
}

// MARK: - The lookup

/// Finds song artwork by artist and title.
public protocol SongArtworkProviding: Sendable {
    /// The cover for the song, or `nil` when the answer cannot be
    /// trusted to be the asked-for song (no result, or the verification
    /// refused it). Transport failures and malformed answers throw.
    func artwork(forArtist artist: String, title: String) async throws -> SongArtwork?
}

/// The iTunes Search API client (`https://itunes.apple.com/search`).
///
/// Two passes, both verified before anything is trusted:
///
/// 1. **"artist title"** — the search a person would type. The *whole*
///    result window is scanned for a verified match, not just the top
///    answer: the API's best fuzzy match is frequently another
///    artist's same-titled song (verified live 2026-11-12: a "Céline
///    Dion — Tous les chemins mènent à l'amour" query answered with
///    Floran, Olivier Dion ×2, Stromae and Rose in its first five —
///    with `limit=1` the verification could only ever refuse, which is
///    the "stations identify songs but fetch no artwork" report).
/// 2. **artist only** — the combined query can be too narrow (the
///    store's title variant drags the ranking down); the artist's own
///    catalogue is searched and the *title* check picks the song.
///
public struct ITunesSongArtworkClient: SongArtworkProviding, Sendable {
    /// The service's API root.
    public static let defaultBaseURL = URL(string: "https://itunes.apple.com/search")!

    /// How many results each pass fetches — big enough to hold the
    /// song behind a crowd of same-titled tracks, small enough to stay
    /// a light request.
    private static let limit = 25

    private let transport: any HTTPGETTransport
    private let baseURL: URL

    public init(
        transport: any HTTPGETTransport = URLSessionGETTransport(),
        baseURL: URL = ITunesSongArtworkClient.defaultBaseURL
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func artwork(forArtist artist: String, title: String) async throws -> SongArtwork? {
        if let found = try await searchAndVerify(
            term: "\(artist) \(title)", artist: artist, title: title
        ) {
            return found
        }
        // No verified match in the combined window — the artist's own
        // catalogue, verified by title. A refusal here yields no
        // artwork, never a guess.
        return try await searchAndVerify(term: artist, artist: artist, title: title)
    }

    /// One search pass: fetches the window and returns the first
    /// result that *is* the asked-for song.
    private func searchAndVerify(
        term: String, artist: String, title: String
    ) async throws -> SongArtwork? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(Self.limit))
        ]
        guard let url = components?.url else { return nil }

        let data = try await transport.get(url: url, headers: [:])
        let decoded: ITunesSearchResponse
        do {
            decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        } catch {
            throw SongArtworkError.malformedResponse
        }
        for result in decoded.results {
            guard let artwork = result.artworkUrl100, let url = URL(string: artwork) else {
                continue
            }
            // The verification per result: a fuzzy window is only
            // trusted one entry at a time. Anything else is skipped —
            // a wrong cover is worse than none.
            guard Self.artistMatches(result.artistName, artist),
                  Self.titleLooselyMatches(result.trackName, title) else {
                continue
            }
            return SongArtwork(artworkURL: url)
        }
        return nil
    }

    // MARK: Normalization and the two checks

    /// Lowercase with diacritics folded — the comparison space both
    /// checks live in ("Céline" == "celine", "Beyoncé" == "beyonce").
    /// Whitespace runs collapse to one space (and the ends trim), so
    /// "AB  BA" and "AB BA" are the same artist.
    static func normalized(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The artist must be the artist: exact equality after
    /// normalization — or equality of the *primary* artist, because
    /// stations announce guests the store does not carry
    /// ("Céline Dion feat. someone" vs "Céline Dion"). The primary
    /// comparison still refuses the "Olivier Dion" answer to a
    /// "Céline Dion" query.
    static func artistMatches(_ found: String?, _ asked: String) -> Bool {
        guard let found else { return false }
        let foundNormalized = normalized(found)
        let askedNormalized = normalized(asked)
        if foundNormalized == askedNormalized { return true }
        let foundPrimary = primaryArtist(foundNormalized)
        let askedPrimary = primaryArtist(askedNormalized)
        guard !foundPrimary.isEmpty, !askedPrimary.isEmpty else { return false }
        return foundPrimary == askedPrimary
    }

    /// The artist without its guest markers ("feat. …", "ft …",
    /// "featuring …", "vs …", "& …", "with …"). When everything after
    /// cutting is empty (an artist *named* by a marker word), the full
    /// name is kept — a real artist must never be cut away to nothing.
    static func primaryArtist(_ normalizedArtist: String) -> String {
        let markers: Set<String> = ["feat", "ft", "featuring", "vs", "with", "&"]
        let tokens = normalizedArtist
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;()")) }
        var primary: [String] = []
        for token in tokens {
            if markers.contains(token) { break }
            primary.append(token)
        }
        let joined = primary.joined(separator: " ")
        return joined.isEmpty ? normalizedArtist : joined
    }

    /// The title may differ in its decorations: stations announce
    /// variants ("Title (Radio Edit)", "Title - Live") and the store
    /// may carry a longer form. Containment either way after
    /// normalization accepts those and still refuses a different song.
    static func titleLooselyMatches(_ found: String?, _ asked: String) -> Bool {
        guard let found else { return false }
        let foundTitle = normalized(found)
        let askedTitle = normalized(asked)
        guard !foundTitle.isEmpty, !askedTitle.isEmpty else { return false }
        return foundTitle.contains(askedTitle) || askedTitle.contains(foundTitle)
    }
}

// MARK: - The wire shape

/// The response of `itunes.apple.com/search` — only the fields the
/// verification needs; the API sends many more and they are ignored.
private struct ITunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [ITunesResult]
}

private struct ITunesResult: Decodable {
    let artistName: String?
    let trackName: String?
    let artworkUrl100: String?
}
