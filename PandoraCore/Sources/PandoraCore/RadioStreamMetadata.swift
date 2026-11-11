//
//  RadioStreamMetadata.swift
//  PandoraCore
//
//  The now-playing metadata that internet-radio streams carry — the
//  ICY protocol (Shoutcast / Icecast). Verified live against real
//  stations while building this: Europe 1 and MANGORADIO both answer
//  the stream request with an `icy-metaint` header and interleave a
//  `StreamTitle` into the audio.
//
//  How it works — the client asks for the metadata (`Icy-MetaData: 1`)
//  and the server answers with `icy-metaint: N`: every N bytes of
//  audio, one length byte follows, and the metadata block after it is
//  `length × 16` bytes long:
//
//      <N bytes audio> <length byte> <length × 16 bytes metadata> …
//
//  The length byte counts *blocks of 16 bytes* (0 means "no metadata
//  this time"), and the block itself is a list of `key='value';` pairs
//  padded with nulls:
//
//      StreamTitle='Céline Dion - Tous les chemins mènent à l'amour';StreamUrl='';
//
//  This file is the pure part: the byte state machine, the header
//  lookup and the "Artist - Title" split. The transport (the socket
//  or the URLSession byte stream) belongs to the app target, so this
//  stays portable and testable — the whole suite runs on Linux.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

// MARK: - The now-playing song

/// The song a radio station is currently announcing.
public struct RadioNowPlaying: Sendable, Equatable {
    /// The station's own `StreamTitle` string, verbatim
    /// ("Artist - Title").
    public let rawTitle: String
    /// The artist, when the announcement could be split into one.
    public let artist: String?
    /// The song title (the `StreamTitle` without its artist part).
    public let title: String

    public init(rawTitle: String, artist: String?, title: String) {
        self.rawTitle = rawTitle
        self.artist = artist
        self.title = title
    }

    /// The query a lyrics or an artwork lookup would use.
    public var lookupQuery: String {
        guard let artist, !artist.isEmpty else { return title }
        return "\(artist) \(title)"
    }
}

// MARK: - Reading the metadata

/// Reads the metadata blocks out of a live stream's byte flow.
///
/// The parser is fed whatever bytes arrive — in whatever sizes they
/// arrive — and hands back the metadata blocks it completed. It never
/// buffers more than one metadata block, and it never looks at the
/// audio itself.
public struct ICYMetadataParser: Sendable {
    /// Where the parser is in the stream.
    public enum State: Equatable, Sendable {
        /// No interval yet — the response header has not arrived, so
        /// there is nothing to look for in the bytes.
        case idle
        /// Reading audio bytes; `remaining` of them before the next
        /// metadata block.
        case audio(remaining: Int)
        /// Reading the one-byte metadata length.
        case length
        /// Reading the metadata block; `remaining` bytes of it.
        case metadata(remaining: Int)
    }

    /// Where the parser currently is.
    public private(set) var state: State = .idle
    /// The metadata interval in bytes (the `icy-metaint` header).
    public private(set) var interval: Int = 0
    /// `true` when the stream announced a metadata interval — a
    /// station that announces nothing can never be identified.
    public var isSupported: Bool { interval > 0 }

    /// The bytes of the metadata block being read.
    private var blockBuffer: [UInt8] = []

    public init() {}

    /// Sets the metadata interval from the response's `icy-metaint`
    /// header. A non-positive value means the stream announces
    /// nothing, and the parser goes idle.
    public mutating func setMetadataInterval(_ bytes: Int) {
        interval = max(0, bytes)
        blockBuffer.removeAll(keepingCapacity: true)
        state = interval > 0 ? .audio(remaining: interval) : .idle
    }

    /// Feeds bytes from the stream and returns the metadata blocks they
    /// completed — the raw `key='value';` text, with the null padding
    /// trimmed. Blocks that carry no text (the server says "nothing
    /// changed") are not returned.
    public mutating func consume(_ data: Data) -> [String] {
        var blocks: [String] = []
        var index = data.startIndex
        while index < data.endIndex {
            switch state {
            case .idle:
                // No interval yet — the bytes are just audio.
                index = data.endIndex
            case .audio(let remaining):
                let available = data.distance(from: index, to: data.endIndex)
                let take = min(available, remaining)
                index = data.index(index, offsetBy: take)
                if take == remaining {
                    state = .length
                } else {
                    // Part of the audio is still to come — the counter
                    // has to follow it down.
                    state = .audio(remaining: remaining - take)
                }
            case .length:
                let length = Int(data[index]) * 16
                index = data.index(after: index)
                state = length > 0
                    ? .metadata(remaining: length)
                    : .audio(remaining: interval)
            case .metadata(let remaining):
                let available = data.distance(from: index, to: data.endIndex)
                let take = min(available, remaining)
                let end = data.index(index, offsetBy: take)
                blockBuffer.append(contentsOf: data[index..<end])
                index = end
                if take == remaining {
                    let block = String(decoding: blockBuffer, as: UTF8.self)
                    blockBuffer.removeAll(keepingCapacity: true)
                    state = .audio(remaining: interval)
                    // The block is padded with nulls; the text itself
                    // never contains one.
                    let trimmed = block.trimmingCharacters(in: .controlCharacters)
                        .trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { blocks.append(trimmed) }
                } else {
                    state = .metadata(remaining: remaining - take)
                }
            }
        }
        return blocks
    }

    /// The metadata interval from a response's headers — the
    /// `icy-metaint` header, looked up case-insensitively (servers
    /// spell it `icy-metaint`, `Icy-MetaInt`, `ICY-METAINT`…).
    public static func metadataInterval(in headers: [String: String]) -> Int? {
        for (key, value) in headers {
            guard key.lowercased() == "icy-metaint" else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard let interval = Int(trimmed), interval > 0 else { return nil }
            return interval
        }
        return nil
    }
}

// MARK: - The announcement

/// The pieces of a station's now-playing announcement.
public enum RadioStreamMetadata {
    /// The `StreamTitle` in a metadata block, if the block carries one.
    ///
    /// The value ends at the first `';` — the separator between the
    /// metadata keys. (An apostrophe inside a title is harmless: it is
    /// only the quote *and* the semicolon that end the value.)
    public static func streamTitle(in block: String) -> String? {
        let key = "streamtitle='"
        guard let range = block.range(of: key, options: .caseInsensitive) else {
            return nil
        }
        let start = range.upperBound
        let rest = block[start...]
        if let end = rest.range(of: "';") {
            let value = String(rest[rest.startIndex..<end.lowerBound])
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        // No closing separator — the value runs to the end of the block.
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Splits a `StreamTitle` into the artist and the song title.
    ///
    /// The convention (Shoutcast, Icecast, and what radio apps show)
    /// is "Artist - Title". Some stations announce only a title, so the
    /// artist is optional. The separator is the *spaced* " - ": a bare
    /// hyphen is part of a title far more often than a separator.
    public static func nowPlaying(fromStreamTitle raw: String) -> RadioNowPlaying? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let separator = trimmed.range(of: " - ") {
            let artist = String(trimmed[trimmed.startIndex..<separator.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let title = String(trimmed[separator.upperBound..<trimmed.endIndex])
                .trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty {
                return RadioNowPlaying(rawTitle: trimmed, artist: artist, title: title)
            }
        }
        return RadioNowPlaying(rawTitle: trimmed, artist: nil, title: trimmed)
    }

    /// The now-playing song a metadata block announces, if any.
    public static func nowPlaying(in block: String) -> RadioNowPlaying? {
        guard let title = streamTitle(in: block) else { return nil }
        return nowPlaying(fromStreamTitle: title)
    }
}
