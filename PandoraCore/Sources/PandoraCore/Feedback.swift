//
//  Feedback.swift
//  PandoraCore
//
//  Thumbs up / down and the "why" state, mirroring the references:
//
//  - `pithos/pandora/pandora.py` `Pandora.add_feedback` /
//    `delete_feedback` / `Song.rate`: `station.addFeedback` with
//    `trackToken` + `isPositive`, the reply carries `feedbackId`;
//    `station.deleteFeedback` with `feedbackId` (+ `stationToken`).
//  - libpiano `source/request.c` (`PIANO_REQUEST_ADD_FEEDBACK`,
//    `PIANO_REQUEST_DELETE_FEEDBACK`): adds `stationToken` to the add
//    call; the delete call carries `feedbackId` only.
//  - pydora `pandora/client.py`: `add_feedback(track_token, positive)`
//    and `delete_feedback(feedback_id)`.
//
//  The legacy v5 API has **no reason/"why" parameter** in any of those
//  references — a dislike is a plain `isPositive: false`. Amphora
//  therefore does not invent a reason field; the reason list stays out
//  of scope until a reference documents it.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

// MARK: - Rating

/// The three ratings Pandora's legacy API understands.
public enum FeedbackRating: String, Codable, Sendable, CaseIterable {
    /// Thumbs up (`isPositive: true`).
    case loved
    /// Thumbs down (`isPositive: false`).
    case banned
    /// No rating — the feedback is removed.
    case none

    /// The `isPositive` flag the API expects. `none` never reaches the
    /// API (a rating is deleted instead).
    var isPositive: Bool { self == .loved }
}

// MARK: - Feedback

/// The result of a rating call: the id needed to undo the rating later.
public struct FeedbackReceipt: Codable, Sendable, Equatable {
    /// `feedbackId` from the `station.addFeedback` reply (pithos'
    /// `Pandora.add_feedback` returns exactly this).
    public let feedbackId: String

    public init(feedbackId: String) {
        self.feedbackId = feedbackId
    }

    /// Decodes the reply of `station.addFeedback`.
    public init(result: [String: AnyJSON]) throws {
        guard let id = result["feedbackId"]?.stringValue else {
            throw PandoraMalformedResponseError(detail: "addFeedback reply missing feedbackId")
        }
        self.feedbackId = id
    }
}

// MARK: - Track rating result

/// The outcome of a rating change: the track's rating afterwards, and
/// the `feedbackId` that rating now carries (nil when the rating was
/// removed — there is no feedback left to undo).
///
/// The id matters because a rating can only be *replaced* or *removed*
/// by its id, and the id is not known for a song rated before this
/// device saw it.
public struct TrackRatingResult: Sendable, Equatable {
    /// The rating the track carries now.
    public let rating: FeedbackRating
    /// The feedback id of the new rating, nil when unrated.
    public let feedbackId: String?

    public init(rating: FeedbackRating, feedbackId: String?) {
        self.rating = rating
        self.feedbackId = feedbackId
    }
}

// MARK: - Bookmarks

/// One bookmarked artist or song (`user.getBookmarks`).
///
/// Wire fields follow pydora's `pandora/models/bookmark.py`:
/// `musicToken`, `artistName`, `artUrl`, `bookmarkToken`, `dateCreated`,
/// plus `songName` / `albumName` / `sampleUrl` / `sampleGain` for songs.
public struct Bookmark: Codable, Sendable, Equatable, Identifiable {
    /// Whether this bookmark is a song or the whole artist.
    public enum Kind: String, Codable, Sendable {
        case song
        case artist
    }

    public let kind: Kind
    /// `bookmarkToken` — what the delete calls need.
    public let bookmarkToken: String
    /// `musicToken` — the seed behind the bookmark.
    public let musicToken: String
    public let artistName: String
    /// Song title (nil for artist bookmarks).
    public let songName: String?
    /// Album title (nil for artist bookmarks).
    public let albumName: String?
    public let artworkUrl: String?
    /// `dateCreated` — epoch seconds when the server sent a number.
    public let createdAt: Date?

    public var id: String { bookmarkToken }

    /// Display title: the song title for songs, the artist name for
    /// artist bookmarks.
    public var title: String {
        if let songName, !songName.isEmpty { return songName }
        return artistName
    }

    public init(
        kind: Kind,
        bookmarkToken: String,
        musicToken: String,
        artistName: String,
        songName: String? = nil,
        albumName: String? = nil,
        artworkUrl: String? = nil,
        createdAt: Date? = nil
    ) {
        self.kind = kind
        self.bookmarkToken = bookmarkToken
        self.musicToken = musicToken
        self.artistName = artistName
        self.songName = songName
        self.albumName = albumName
        self.artworkUrl = artworkUrl
        self.createdAt = createdAt
    }

    /// Parses `user.getBookmarks`'s result: `songs` and `artists`
    /// (pydora's `BookmarkList`).
    public static func bookmarks(from result: [String: AnyJSON]) -> [Bookmark] {
        var list: [Bookmark] = []
        for entry in result["songs"]?.arrayValue ?? [] {
            guard let bookmark = entry.objectValue.flatMap({ bookmark(from: $0, kind: .song) }) else {
                continue
            }
            list.append(bookmark)
        }
        for entry in result["artists"]?.arrayValue ?? [] {
            guard let bookmark = entry.objectValue.flatMap({ bookmark(from: $0, kind: .artist) }) else {
                continue
            }
            list.append(bookmark)
        }
        return list
    }

    private static func bookmark(from entry: [String: AnyJSON], kind: Kind) -> Bookmark? {
        guard let token = entry["bookmarkToken"]?.stringValue,
              let musicToken = entry["musicToken"]?.stringValue else { return nil }
        let artist = entry["artistName"]?.stringValue ?? ""
        let song = entry["songName"]?.stringValue
        let album = entry["albumName"]?.stringValue
        let artwork = entry["artUrl"]?.stringValue
        var created: Date?
        if let seconds = entry["dateCreated"]?.doubleValue {
            created = Date(timeIntervalSince1970: seconds)
        } else if let text = entry["dateCreated"]?.stringValue,
                  let seconds = Double(text) {
            created = Date(timeIntervalSince1970: seconds)
        }
        return Bookmark(
            kind: kind,
            bookmarkToken: token,
            musicToken: musicToken,
            artistName: artist,
            songName: song,
            albumName: album,
            artworkUrl: artwork,
            createdAt: created
        )
    }
}
