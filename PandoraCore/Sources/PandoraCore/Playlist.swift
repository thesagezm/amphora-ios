//
//  Playlist.swift
//  PandoraCore
//
//  `station.getPlaylist` decoding: one playlist entry → one `Track` with
//  its audio variants, mirroring the two references:
//
//  - `pithos/pandora/pandora.py` `Station.get_playlist` / `Song.__init__`:
//    request params (`stationToken`, `includeTrackLength`,
//    `additionalAudioUrl: 'HTTP_32_AACPLUS,HTTP_128_MP3'`), the wire fields,
//    and the quality promotion rule — when the account's `highQuality` is
//    below 128 kbps the extra 128 MP3 URL becomes the new high quality.
//  - pydora `pandora/models/playlist.py` `AudioField`: a response with a
//    bare `audioUrl` and no `audioUrlMap` still yields a playable
//    high-quality (aacplus/64) stream.
//
//  Entries without `songName` are skipped (pithos filters them) — except
//  advertisement entries, which carry `title` instead (pydora's `AdItem`);
//  those are kept and flagged (`is_ad`) so playback can resolve them via
//  `ad.getAdMetadata` and register the impression (`ad.registerAd`).
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

// MARK: - Audio

/// One playable stream for a track: encoding, bitrate and URL.
public struct AudioVariant: Codable, Sendable, Equatable, Identifiable {
    /// Wire key of the quality bucket (`highQuality` / `mediumQuality` /
    /// `lowQuality`) this variant came from.
    public enum Quality: String, Codable, Sendable, CaseIterable {
        case highQuality
        case mediumQuality
        case lowQuality

        /// Higher rank = preferred.
        var rank: Int {
            switch self {
            case .highQuality: return 3
            case .mediumQuality: return 2
            case .lowQuality: return 1
            }
        }
    }

    public let quality: Quality
    public let encoding: String
    public let bitrate: Int
    public let url: String

    public var id: String { "\(quality.rawValue):\(encoding):\(bitrate)" }

    public init(quality: Quality, encoding: String, bitrate: Int, url: String) {
        self.quality = quality
        self.encoding = encoding
        self.bitrate = bitrate
        self.url = url
    }
}

// MARK: - Track

/// One track from a station playlist.
public struct Track: Codable, Sendable, Equatable, Identifiable {
    /// Pandora's `songRating`: 1 = thumbs up, -1 = thumbs down,
    /// 0 = unrated (pithos `RATE_LOVE` / `RATE_BAN` / `RATE_NONE`).
    public enum Rating: Int, Codable, Sendable {
        case banned = -1
        case none = 0
        case loved = 1
    }

    public let trackToken: String
    public let title: String
    public let artist: String
    public let album: String
    public let artworkUrl: String?
    /// Track length in seconds (`trackLength`, with `includeTrackLength`).
    public let duration: Int
    public let stationId: String
    public let rating: Rating
    /// Pandora's playback gain hint (`trackGain`) — informational only.
    public let gain: Double
    /// Ads carry an `adToken`; they are not music (pydora `is_ad`).
    /// Playlist ad entries are usually stubs without audio — resolve them
    /// with `SessionManager.getAdMetadata` before playing.
    public let isAdvertisement: Bool
    /// The ad token of an advertisement entry, nil for music tracks
    /// (pydora `AdItem.ad_token`; keys the resolve/register calls).
    public let adToken: String?
    /// Available streams, best first (highest quality bucket, then
    /// bitrate). Empty when the server sent no playable URL.
    public let variants: [AudioVariant]

    public var id: String { trackToken }

    /// The stream to play: highest available quality (pithos' default
    /// `audio_quality = 'highQuality'`, pydora's downward search).
    public var preferredVariant: AudioVariant? { variants.first }

    /// Playable URL, or nil when Pandora sent no audio (ads, expired items).
    public var streamURL: String? { preferredVariant?.url }

    public init(
        trackToken: String,
        title: String,
        artist: String,
        album: String,
        artworkUrl: String? = nil,
        duration: Int,
        stationId: String,
        rating: Rating = .none,
        gain: Double = 0,
        isAdvertisement: Bool = false,
        adToken: String? = nil,
        variants: [AudioVariant] = []
    ) {
        self.trackToken = trackToken
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkUrl = artworkUrl
        self.duration = duration
        self.stationId = stationId
        self.rating = rating
        self.gain = gain
        self.isAdvertisement = isAdvertisement
        self.adToken = adToken
        self.variants = variants
    }

    /// Parses the `items` array of a `station.getPlaylist` result.
    /// Music entries without `songName` are dropped (pithos' filter);
    /// advertisements are kept (see `track(from:)`); a malformed entry is
    /// skipped, never fatal.
    public static func tracks(from result: [String: AnyJSON]) -> [Track] {
        (result["items"]?.arrayValue ?? []).compactMap { entry in
            entry.objectValue.flatMap { track(from: $0) }
        }
    }

    /// One playlist entry → one track.
    ///
    /// Music entries carry `songName` + `trackToken` (pithos' filter).
    /// Advertisement entries carry `adToken` and use `title`/`companyName`
    /// instead (pydora `AdItem`) and usually have no audio — they are kept,
    /// flagged, and get a synthetic id (`ad.<adToken>`) when the entry has
    /// no `trackToken`, so playback can resolve them (`ad.getAdMetadata`)
    /// and register the impression (`ad.registerAd`) instead of silently
    /// dropping them (a silent drop consumes the impression while never
    /// playing anything).
    public static func track(from entry: [String: AnyJSON]) -> Track? {
        let adToken = entry["adToken"]?.stringValue
        let title = entry["songName"]?.stringValue ?? entry["title"]?.stringValue
        let trackToken = entry["trackToken"]?.stringValue ?? adToken.map { "ad." + $0 }
        guard let title, let trackToken else { return nil }
        let artist = entry["artistName"]?.stringValue
            ?? entry["companyName"]?.stringValue ?? ""
        let album = entry["albumName"]?.stringValue ?? ""
        let artwork = entry["albumArtUrl"]?.stringValue ?? entry["imageUrl"]?.stringValue
        let duration = entry.intLike("trackLength") ?? 0
        let stationId = entry.stringLike("stationId") ?? ""
        let rating = Rating(rawValue: entry.intLike("songRating") ?? 0) ?? .none
        let gain = entry.doubleLike("trackGain") ?? 0

        return Track(
            trackToken: trackToken,
            title: title,
            artist: artist,
            album: album,
            artworkUrl: artwork,
            duration: duration,
            stationId: stationId,
            rating: rating,
            gain: gain,
            isAdvertisement: adToken != nil,
            adToken: adToken,
            variants: variants(from: entry)
        )
    }

    /// Builds the ordered variant list for one playlist entry.
    ///
    /// Wire shape (pithos `Song.__init__`):
    ///
    ///     "audioUrlMap": { "highQuality": { "bitrate": "64",
    ///                         "encoding": "aacplus", "audioUrl": "…" } }
    ///     "additionalAudioUrl": ["…aacplus-32…", "…mp3-128…"]
    ///
    /// Rules, in order:
    /// 1. Parse every quality bucket that carries a URL and bitrate.
    /// 2. With two additional URLs, promote the 128 MP3 to `highQuality`
    ///    when the server's high quality is below 128 kbps (pithos), else
    ///    keep the 32 AAC+ as a `lowQuality` fallback (pithos).
    /// 3. A bare `audioUrl` without a map is treated as a 64 kbps aacplus
    ///    high-quality stream (pydora `AudioField`).
    private static func variants(from entry: [String: AnyJSON]) -> [AudioVariant] {
        var byQuality: [AudioVariant.Quality: AudioVariant] = [:]

        if let map = entry["audioUrlMap"]?.objectValue {
            for quality in AudioVariant.Quality.allCases {
                guard let bucket = map[quality.rawValue]?.objectValue,
                      let url = bucket["audioUrl"]?.stringValue,
                      !url.isEmpty,
                      let bitrate = bucket.intLike("bitrate") else { continue }
                let encoding = bucket["encoding"]?.stringValue ?? "unknown"
                byQuality[quality] = AudioVariant(
                    quality: quality, encoding: encoding, bitrate: bitrate, url: url
                )
            }
        }

        // Additional URLs: index 0 = HTTP_32_AACPLUS, index 1 = HTTP_128_MP3
        // (the order Amphora requests them in).
        let additional = (entry["additionalAudioUrl"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }
        if additional.count >= 2 {
            let high = byQuality[.highQuality]
            if let high, high.bitrate < 128 {
                // The 128 MP3 stream is better than what we were offered:
                // it becomes the new high quality, the old high drops to
                // medium (pithos' exact promotion).
                byQuality[.mediumQuality] = AudioVariant(
                    quality: .mediumQuality,
                    encoding: high.encoding,
                    bitrate: high.bitrate,
                    url: high.url
                )
                byQuality[.highQuality] = AudioVariant(
                    quality: .highQuality, encoding: "mp3", bitrate: 128, url: additional[1]
                )
            } else if high == nil {
                byQuality[.highQuality] = AudioVariant(
                    quality: .highQuality, encoding: "mp3", bitrate: 128, url: additional[1]
                )
                byQuality[.lowQuality] = AudioVariant(
                    quality: .lowQuality, encoding: "aacplus", bitrate: 32, url: additional[0]
                )
            } else {
                byQuality[.lowQuality] = AudioVariant(
                    quality: .lowQuality, encoding: "aacplus", bitrate: 32, url: additional[0]
                )
            }
        }

        if byQuality.isEmpty,
           let bare = entry["audioUrl"]?.stringValue,
           !bare.isEmpty {
            // pydora: mobile tokens sometimes answer with a bare URL.
            byQuality[.highQuality] = AudioVariant(
                quality: .highQuality, encoding: "aacplus", bitrate: 64, url: bare
            )
        }

        return byQuality.values.sorted { lhs, rhs in
            if lhs.quality.rank != rhs.quality.rank { return lhs.quality.rank > rhs.quality.rank }
            return lhs.bitrate > rhs.bitrate
        }
    }
}

// MARK: - Playlist

/// A fetched playlist plus the moment it was requested. Pandora's playlists
/// expire after an hour (pithos `PLAYLIST_VALIDITY_TIME`).
public struct Playlist: Codable, Sendable, Equatable {
    public let tracks: [Track]
    public let fetchedAt: Date

    public init(tracks: [Track], fetchedAt: Date = Date()) {
        self.tracks = tracks
        self.fetchedAt = fetchedAt
    }

    /// How long a playlist stays usable (pithos `PLAYLIST_VALIDITY_TIME`).
    public static let validityTime: TimeInterval = 60 * 60

    /// `true` once the playlist is older than Pandora allows.
    public func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) >= Self.validityTime
    }
}

// MARK: - Flexible field access

private extension Dictionary where Key == String, Value == AnyJSON {
    /// Numbers arrive as JSON numbers or as numeric strings (pithos reads
    /// `int(d['audioUrlMap']['highQuality']['bitrate'])` — a string).
    func intLike(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        if let number = value.intValue { return number }
        if let text = value.stringValue { return Int(text) }
        return nil
    }

    func doubleLike(_ key: String) -> Double? {
        guard let value = self[key] else { return nil }
        if let number = value.doubleValue { return number }
        if let text = value.stringValue { return Double(text) }
        return nil
    }

    /// Ids arrive as numbers or strings depending on the endpoint.
    func stringLike(_ key: String) -> String? {
        guard let value = self[key] else { return nil }
        if let text = value.stringValue { return text }
        if let number = value.intValue { return String(number) }
        return nil
    }
}
