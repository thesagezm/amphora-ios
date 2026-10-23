//
//  HistoryStore.swift
//  PandoraCore
//
//  Local playback history — "recently played" (AGENTS.md feature set).
//  Pure logic: a bounded list of played tracks, newest first, with
//  de-duplication by track token. No UI, no AVFoundation — the app target
//  persists it to disk (Codable-friendly value type).
//

import Foundation

/// A bounded, newest-first history of played tracks.
///
/// The cap keeps memory and disk usage flat: the oldest entry falls off
/// when the list grows past `capacity`.
public struct PlayHistory: Codable, Sendable, Equatable {

    /// One remembered play.
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let trackToken: String
        public let title: String
        public let artist: String
        public let album: String
        public let artworkUrl: String?
        /// When the track was played (epoch seconds).
        public let playedAt: Date

        public var id: String { trackToken }

        public init(
            trackToken: String,
            title: String,
            artist: String,
            album: String,
            artworkUrl: String? = nil,
            playedAt: Date = Date()
        ) {
            self.trackToken = trackToken
            self.title = title
            self.artist = artist
            self.album = album
            self.artworkUrl = artworkUrl
            self.playedAt = playedAt
        }

        /// Builds an entry from a played track.
        public init(track: Track, playedAt: Date = Date()) {
            self.init(
                trackToken: track.trackToken,
                title: track.title,
                artist: track.artist,
                album: track.album,
                artworkUrl: track.artworkUrl,
                playedAt: playedAt
            )
        }
    }

    /// How many plays are remembered.
    public static let defaultCapacity = 100

    /// Newest first.
    public private(set) var entries: [Entry]

    /// Whether anything has been played yet.
    public var isEmpty: Bool { entries.isEmpty }

    /// The remembered plays, newest first.
    public var count: Int { entries.count }

    /// The plays as a plain array (for `List`/`ForEach`).
    public var items: [Entry] { entries }

    /// The maximum number of entries kept.
    public let capacity: Int

    public init(entries: [Entry] = [], capacity: Int = PlayHistory.defaultCapacity) {
        self.entries = entries
        self.capacity = max(1, capacity)
        trim()
    }

    /// Records a play. A track that is already in the history moves to
    /// the front instead of appearing twice.
    public mutating func record(_ track: Track, at date: Date = Date()) {
        let entry = Entry(track: track, playedAt: date)
        entries.removeAll { $0.trackToken == entry.trackToken }
        entries.insert(entry, at: 0)
        trim()
    }

    /// Drops the oldest entries until the list fits the capacity.
    private mutating func trim() {
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }
}
