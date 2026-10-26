//
//  Lyrics.swift
//  PandoraCore
//
//  Time-synced lyrics: the LRC format and the model the player renders.
//
//  LRC is the de-facto standard for synchronised lyrics. A line looks
//  like `[01:23.45] the words`, where the bracket holds the timestamp
//  at which the line starts. Several details matter in the wild and are
//  handled here:
//
//  - **Several timestamps per line** — `[00:12.00][01:12.00] chorus`
//    repeats the same words later in the song.
//  - **Fractional seconds** with one, two or three digits, separated by
//    `.` or `:` (`[01:23.4]`, `[01:23.45]`, `[01:23.456]`,
//    `[01:23:45]`).
//  - **Metadata tags** — `[ar:]`, `[ti:]`, `[al:]`, `[by:]`, `[length:]`,
//    `[offset:]`. A tag is not a timestamp and must not be rendered as
//    a lyric.
//  - **Plain (unsynchronised) lyrics** — the same file without any
//    timestamps; they are kept as text so the UI can still show them.
//
//  The lyric *source* (lrclib.net) lives in the app target — this file
//  is the pure, portable logic: parse, order, and answer "which line is
//  playing at time t?".
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

// MARK: - Line

/// One lyric line: when it starts and what it says.
public struct LyricLine: Codable, Sendable, Equatable, Identifiable {
    /// Start of the line, in seconds from the beginning of the track.
    public let timestamp: TimeInterval
    /// The words.
    public let text: String
    /// English translation of `text` (nil when the lyrics are already in
    /// English, or when no translation was fetched).
    public var translation: String?
    /// `text` spelled in alphabet letters (romanization) for lyrics
    /// written in a non-Latin script — "사랑해" → "salanghae". Nil when the
    /// line needs none, or none was fetched.
    public var romanization: String?

    public var id: String { "\(timestamp)-\(text)" }

    public init(
        timestamp: TimeInterval,
        text: String,
        translation: String? = nil,
        romanization: String? = nil
    ) {
        self.timestamp = timestamp
        self.text = text
        self.translation = translation
        self.romanization = romanization
    }

    /// The line as it should be displayed: the original words, with the
    /// translation underneath when there is one.
    public var displayText: String {
        if let translation, !translation.isEmpty { return translation }
        return text
    }
}

// MARK: - Lyrics

/// A track's lyrics: either synchronised lines, plain text, or nothing
/// (instrumental / not found).
public struct Lyrics: Codable, Sendable, Equatable {
    /// The synchronised lines, ordered by timestamp. Empty when the
    /// lyrics are plain text.
    public let lines: [LyricLine]
    /// Un-synchronised lyrics (the whole text). Nil when the lyrics are
    /// synchronised.
    public let plainText: String?
    /// The track is instrumental — there are no words to show.
    public let instrumental: Bool
    /// The id of the lyric record at the source (lrclib's `id`), used
    /// for caching.
    public let trackID: Int?

    public init(
        lines: [LyricLine] = [],
        plainText: String? = nil,
        instrumental: Bool = false,
        trackID: Int? = nil
    ) {
        self.lines = lines
        self.plainText = plainText
        self.instrumental = instrumental
        self.trackID = trackID
    }

    /// No lyrics at all.
    public static let empty = Lyrics()

    /// `true` when the lyrics can be scrolled in sync with playback.
    public var isSynced: Bool { !lines.isEmpty }

    /// `true` when there is nothing to display.
    public var isEmpty: Bool { lines.isEmpty && (plainText?.isEmpty ?? true) && !instrumental }

    /// The index of the line that is playing at `time`, or nil before
    /// the first line starts.
    public func activeLineIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        // The last line whose timestamp is ≤ time.
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].timestamp <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// The line that is playing at `time`.
    public func activeLine(at time: TimeInterval) -> LyricLine? {
        guard let index = activeLineIndex(at: time) else { return nil }
        return lines[index]
    }

    /// The line after the one playing at `time` (the "coming up" line).
    public func nextLine(after time: TimeInterval) -> LyricLine? {
        guard let index = activeLineIndex(at: time) else {
            return lines.first
        }
        let next = index + 1
        return next < lines.count ? lines[next] : nil
    }

    /// How far the current line has progressed (0…1) — used to animate
    /// the highlight.
    public func progress(at time: TimeInterval) -> Double {
        guard let index = activeLineIndex(at: time) else { return 0 }
        let start = lines[index].timestamp
        let end = index + 1 < lines.count ? lines[index + 1].timestamp : start + 4
        let span = end - start
        guard span > 0 else { return 0 }
        return min(1, max(0, (time - start) / span))
    }
}

// MARK: - Parser

/// Parses the LRC format.
public enum LRC {
    /// Parses an LRC document (or plain lyrics) into `Lyrics`.
    public static func parse(_ raw: String) -> Lyrics {
        var synced: [LyricLine] = []
        var plainLines: [String] = []
        var offsetSeconds: TimeInterval = 0
        var trackID: Int? = nil

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let (timestamps, text) = split(line)
            if timestamps.isEmpty {
                // No timestamp: either a metadata tag or a plain lyric
                // line.
                if let tag = metadata(line) {
                    switch tag.key.lowercased() {
                    case "offset":
                        offsetSeconds = (Double(tag.value) ?? 0) / 1000
                    case "id":
                        trackID = Int(tag.value)
                    default:
                        break
                    }
                } else {
                    plainLines.append(line)
                }
                continue
            }

            for stamp in timestamps {
                // The `[offset:]` tag is in milliseconds and shifts the
                // lyrics *earlier* for a positive value — the same
                // convention FFmpeg's LRC demuxer uses
                // (`sub->pts = ts_start - ts_offset`, `libavformat/lrcdec.c`).
                synced.append(LyricLine(timestamp: stamp - offsetSeconds, text: text))
            }
        }

        synced.sort { $0.timestamp < $1.timestamp }

        if !synced.isEmpty {
            return Lyrics(lines: synced, trackID: trackID)
        }
        if !plainLines.isEmpty {
            return Lyrics(plainText: plainLines.joined(separator: "\n"), trackID: trackID)
        }
        return Lyrics(trackID: trackID)
    }

    /// Splits a line into its timestamps and the text that follows them.
    /// A line without any timestamp yields an empty timestamp list.
    static func split(_ line: String) -> (timestamps: [TimeInterval], text: String) {
        var timestamps: [TimeInterval] = []
        var index = line.startIndex

        while index < line.endIndex, line[index] == "[" {
            guard let close = line[index...].firstIndex(of: "]") else { break }
            let content = String(line[line.index(after: index)..<close])
            guard let stamp = timestamp(content) else { break }
            timestamps.append(stamp)
            index = line.index(after: close)
        }

        let text = String(line[index...]).trimmingCharacters(in: .whitespaces)
        return (timestamps, text)
    }

    /// Parses one timestamp: `mm:ss`, `mm:ss.f`, `mm:ss.ff`, `mm:ss.fff`
    /// or `mm:ss:ff`.
    static func timestamp(_ content: String) -> TimeInterval? {
        let parts = content.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Double(parts[0]),
              let secondsValue = Double(parts[1]) else { return nil }
        guard minutes >= 0, secondsValue >= 0 else { return nil }

        var fraction: Double = 0
        if parts.count == 3 {
            // `mm:ss:ff` — the third field is centiseconds.
            guard let value = Double(parts[2]) else { return nil }
            fraction = value / 100
        } else if let dot = parts[1].firstIndex(of: ".") {
            let whole = parts[1][parts[1].startIndex..<dot]
            let decimals = parts[1][parts[1].index(after: dot)...]
            guard let value = Double(whole) else { return nil }
            fraction = scaledFraction(decimals)
            return minutes * 60 + value + fraction
        }
        return minutes * 60 + secondsValue + fraction
    }

    /// Fractional seconds: one digit = tenths, two = hundredths, three
    /// = thousandths.
    private static func scaledFraction(_ digits: Substring) -> Double {
        guard let value = Double(digits) else { return 0 }
        switch digits.count {
        case 0: return 0
        case 1: return value / 10
        case 2: return value / 100
        default: return value / 1000
        }
    }

    /// A metadata tag (`[ar:Artist]`) as key/value, or nil when the
    /// bracketed text is not a tag.
    static func metadata(_ line: String) -> (key: String, value: String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let content = String(line[line.index(after: line.startIndex)..<close])
        guard let colon = content.firstIndex(of: ":") else { return nil }
        let key = String(content[content.startIndex..<colon])
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        let value = String(content[content.index(after: colon)...])
        return (key, value)
    }
}
