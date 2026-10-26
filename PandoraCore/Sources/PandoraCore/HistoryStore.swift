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
        /// The station the track was played from (`stationToken`) — the
        /// rating of a past track belongs to that station, so the
        /// Recents list can rate it later. Nil for entries recorded
        /// before this field existed.
        public let stationToken: String?
        /// The rating the track carried when it played (`songRating`),
        /// and the rating the user gives it later from the Recents
        /// list. Nil = unknown/unrated.
        public var rating: FeedbackRating?
        /// When the track was played (epoch seconds).
        public let playedAt: Date

        public var id: String { trackToken }

        public init(
            trackToken: String,
            title: String,
            artist: String,
            album: String,
            artworkUrl: String? = nil,
            stationToken: String? = nil,
            rating: FeedbackRating? = nil,
            playedAt: Date = Date()
        ) {
            self.trackToken = trackToken
            self.title = title
            self.artist = artist
            self.album = album
            self.artworkUrl = artworkUrl
            self.stationToken = stationToken
            self.rating = rating
            self.playedAt = playedAt
        }

        /// Builds an entry from a played track.
        public init(
            track: Track,
            stationToken: String? = nil,
            playedAt: Date = Date()
        ) {
            self.init(
                trackToken: track.trackToken,
                title: track.title,
                artist: track.artist,
                album: track.album,
                artworkUrl: track.artworkUrl,
                stationToken: stationToken,
                rating: nil,
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
    ///
    /// A re-listen keeps the rating the user already gave the track —
    /// the rating belongs to the song, not to the play.
    public mutating func record(_ track: Track, stationToken: String? = nil, at date: Date = Date()) {
        let existingRating = entries.first { $0.trackToken == track.trackToken }?.rating
        let entry = Entry(
            track: track,
            stationToken: stationToken,
            playedAt: date
        )
        entries.removeAll { $0.trackToken == entry.trackToken }
        var stored = entry
        stored.rating = existingRating
        entries.insert(stored, at: 0)
        trim()
    }

    /// Sets the rating of a remembered track. Returns false when the
    /// track is not in the history.
    @discardableResult
    public mutating func setRating(_ rating: FeedbackRating?, for trackToken: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.trackToken == trackToken }) else {
            return false
        }
        entries[index].rating = rating
        return true
    }

    /// The rating of a remembered track, if it has one.
    public func rating(for trackToken: String) -> FeedbackRating? {
        entries.first { $0.trackToken == trackToken }?.rating
    }

    /// Drops the oldest entries until the list fits the capacity.
    private mutating func trim() {
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }
}
