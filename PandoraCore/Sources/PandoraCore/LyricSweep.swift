//
//  LyricSweep.swift
//  PandoraCore
//
//  The pure math behind the swept lyric line: where the wavefront is
//  inside each word (and each letter) at a moment. No UI, no platform
//  types — the app renders the states, and a future Android port
//  derives an identical wavefront from the same function.
//
//  Two regimes, chosen by the data:
//
//  - **Word-exact** — the line carries `[LyricWord]` (a rich-sync
//    source): each word's window is its own timestamp to the next
//    word's start, and the wavefront follows real timings.
//  - **Interpolated** — line-timed data only: the line's window is
//    divided across the words weighted by character counts, so longer
//    words hold the wavefront longer. The division is identical to
//    what the UI's first sweep did, down to the separator-space
//    tokens, so the fallback looks the same as it always did.
//
//  In both regimes, letters inside a word are interpolated across the
//  word's own progress (a provider that carries sub-word timings can
//  replace this later without touching the UI).
//

import Foundation

/// The sweep state of a lyric line at one moment.
public enum LyricSweep {
    /// One word of the line: its display text and how far the
    /// wavefront has crossed it (0…1).
    public struct WordState: Equatable, Sendable {
        public let text: String
        public let sungFraction: Double

        public init(text: String, sungFraction: Double) {
            self.text = text
            self.sungFraction = sungFraction
        }
    }

    /// The per-word sweep states at `now` inside the line's window
    /// (`window` spans the line's start to the next line's start).
    /// Words before `now` are fully sung, words after it not begun.
    /// Word-exact timings win whenever the line carries them;
    /// line-timed data interpolates.
    public static func wordStates(
        words: [LyricWord]?, text: String, at now: TimeInterval,
        window: ClosedRange<TimeInterval>
    ) -> [WordState] {
        if let words, !words.isEmpty {
            return exactStates(words: words, at: now, window: window)
        }
        return interpolatedStates(text: text, at: now, window: window)
    }

    /// The word-exact regime. Each word's window runs from its own
    /// timestamp to the next word's start (the line's window end for
    /// the last word); a degenerate window (equal timestamps) reads as
    /// "complete once reached".
    private static func exactStates(
        words: [LyricWord], at now: TimeInterval, window: ClosedRange<TimeInterval>
    ) -> [WordState] {
        words.enumerated().map { index, word in
            let start = max(word.timestamp, window.lowerBound)
            let end = index + 1 < words.count
                ? words[index + 1].timestamp
                : window.upperBound
            let span = end - start
            let sung: Double
            if span <= 0 {
                sung = now >= start ? 1 : 0
            } else {
                sung = min(1, max(0, (now - start) / span))
            }
            return WordState(text: word.text.isEmpty ? " " : word.text, sungFraction: sung)
        }
    }

    /// The interpolated regime — line-timed data. The line's window is
    /// divided across the space-separated tokens weighted by character
    /// counts (`max(count, 1)` so separator spaces still own a slice),
    /// the same division the UI's first sweep used.
    private static func interpolatedStates(
        text: String, at now: TimeInterval, window: ClosedRange<TimeInterval>
    ) -> [WordState] {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false)
            .map(String.init)
        let weights = tokens.map { Double(max($0.count, 1)) }
        let total = max(weights.reduce(0, +), 1)
        let progress = min(
            1, max(0, (now - window.lowerBound) / max(window.upperBound - window.lowerBound, 0.3))
        )

        var before = 0.0
        return tokens.map { token in
            let weight = Double(max(token.count, 1))
            let start = before / total
            before += weight
            let end = before / total
            let sung = min(
                1, max(0, (progress - start) / max(end - start, 0.001))
            )
            return WordState(text: token.isEmpty ? " " : token, sungFraction: sung)
        }
    }

    /// How far the wavefront has crossed letter `index` of a word
    /// whose own sweep is at `wordSung` (0…1) — letters divide the
    /// word's progress equally, so the letter swell pops in reading
    /// order. 0 before the letter's slice, 1 after it.
    public static func letterProgress(
        wordSung: Double, letterIndex: Int, letterCount: Int
    ) -> Double {
        guard letterCount > 0, letterIndex >= 0, letterIndex < letterCount else { return 0 }
        let width = 1.0 / Double(letterCount)
        let start = Double(letterIndex) * width
        return min(1, max(0, (wordSung - start) / width))
    }
}
