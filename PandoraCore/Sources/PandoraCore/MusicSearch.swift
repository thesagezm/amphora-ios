//
//  MusicSearch.swift
//  PandoraCore
//
//  `music.search` results, mirroring `pithos.pandora.Pandora.search()`:
//
//    artists: score ≥ 80 kept; songs: score ≥ 80 kept; genreStations: all.
//    Merged and sorted by score descending (Python's sort is stable, so
//    ties keep the artists → songs → genre merge order).
//
//  Every kind carries `musicToken` — pithos' `SearchResult.musicId` reads
//  it unconditionally, and its add-station dialog creates stations from
//  any kind via `add_station_by_music_id(musicId)`.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

public struct MusicSearchResult: Codable, Sendable, Equatable, Identifiable {
    /// pithos `SearchResult.resultType`.
    public enum Kind: String, Codable, Sendable {
        case artist
        case song
        case genre
    }

    public let kind: Kind
    /// Relevance score from the server (pithos filters `< 80` on
    /// artist/song; genre passes through with whatever it sent).
    public let score: Int
    /// Seed token for `station.createStation` (`musicToken`).
    public let musicToken: String
    /// Primary label: song title, artist name, or genre station name.
    public let title: String
    /// Artist name for songs; nil otherwise.
    public let subtitle: String?

    /// Sections can theoretically repeat a token across kinds; kind+token
    /// is unique in practice and stable across reloads.
    public var id: String { "\(kind.rawValue):\(musicToken)" }

    public init(kind: Kind, score: Int, musicToken: String, title: String, subtitle: String? = nil) {
        self.kind = kind
        self.score = score
        self.musicToken = musicToken
        self.title = title
        self.subtitle = subtitle
    }

    /// Parses `music.search`'s unwrapped result object into pithos'
    /// filter-and-sort order. A malformed entry is skipped (one bad seed
    /// must not fail the whole sheet) — pithos would crash instead.
    public static func searchResults(from result: [String: AnyJSON]) -> [MusicSearchResult] {
        var merged: [(order: Int, hit: MusicSearchResult)] = []
        var order = 0

        func append(_ hit: MusicSearchResult?) {
            if let hit {
                merged.append((order, hit))
                order += 1
            }
        }

        for entry in result["artists"]?.arrayValue ?? [] {
            // pithos: `if i['score'] >= 80`
            guard let hit = artistOrSong(entry, kind: .artist), hit.score >= 80 else { continue }
            append(hit)
        }
        for entry in result["songs"]?.arrayValue ?? [] {
            guard let hit = artistOrSong(entry, kind: .song), hit.score >= 80 else { continue }
            append(hit)
        }
        for entry in result["genreStations"]?.arrayValue ?? [] {
            guard let name = entry["stationName"]?.stringValue,
                  let token = entry["musicToken"]?.stringValue,
                  let score = entry["score"]?.intValue else { continue }
            append(MusicSearchResult(kind: .genre, score: score, musicToken: token, title: name))
        }

        // Score descending; original merge order breaks ties (pithos relies
        // on Python's stable sort with the same key).
        merged.sort { lhs, rhs in
            if lhs.hit.score != rhs.hit.score { return lhs.hit.score > rhs.hit.score }
            return lhs.order < rhs.order
        }
        return merged.map(\.hit)
    }

    private static func artistOrSong(_ entry: [String: AnyJSON], kind: Kind) -> MusicSearchResult? {
        guard let token = entry["musicToken"]?.stringValue,
              let score = entry["score"]?.intValue else { return nil }
        switch kind {
        case .artist:
            guard let name = entry["artistName"]?.stringValue else { return nil }
            return MusicSearchResult(kind: .artist, score: score, musicToken: token, title: name)
        case .song:
            guard let title = entry["songName"]?.stringValue else { return nil }
            return MusicSearchResult(
                kind: .song, score: score, musicToken: token,
                title: title, subtitle: entry["artistName"]?.stringValue
            )
        case .genre:
            return nil  // handled above; kept so `kind` stays exhaustive
        }
    }
}
