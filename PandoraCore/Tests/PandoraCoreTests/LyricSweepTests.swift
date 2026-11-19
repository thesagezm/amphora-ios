//
//  LyricSweepTests.swift
//  PandoraCoreTests
//
//  The swept line's math: word-exact windows, the interpolated
//  fallback (byte-for-byte the division the UI's first sweep used),
//  and the per-letter progress the swell rides.
//

import PandoraCore
import XCTest

final class LyricSweepTests: XCTestCase {
    // MARK: - Word-exact regime

    func testExactWordsCrossingWordIsPartial() {
        // Words at 10.0, 12.0, 14.0 within a line window 10.0...16.0.
        let words = [
            LyricWord(timestamp: 10, text: "one"),
            LyricWord(timestamp: 12, text: "two"),
            LyricWord(timestamp: 14, text: "three"),
        ]
        let states = LyricSweep.wordStates(
            words: words, text: "one two three", at: 12.5,
            window: 10.0...16.0
        )
        XCTAssertEqual(states.count, 3)
        // The first word is long done.
        XCTAssertEqual(states[0].sungFraction, 1)
        // The second word is halfway through its 12→14 window.
        XCTAssertEqual(states[1].sungFraction, 0.25, accuracy: 0.0001)
        // The third has not begun.
        XCTAssertEqual(states[2].sungFraction, 0)
        XCTAssertEqual(states[1].text, "two")
    }

    func testExactWordsLastWordRunsToWindowEnd() {
        let words = [
            LyricWord(timestamp: 10, text: "one"),
            LyricWord(timestamp: 12, text: "two"),
        ]
        let states = LyricSweep.wordStates(
            words: words, text: "one two", at: 14, window: 10.0...16.0
        )
        // The last word owns 12→16 and is 50% crossed at 14.
        XCTAssertEqual(states[1].sungFraction, 0.5, accuracy: 0.0001)
    }

    func testExactWordsBeforeFirstWord() {
        let words = [LyricWord(timestamp: 10, text: "one")]
        let states = LyricSweep.wordStates(
            words: words, text: "one", at: 5, window: 10.0...14.0
        )
        XCTAssertEqual(states[0].sungFraction, 0)
    }

    func testExactWordsDegenerateWindowCompletesOnReach() {
        // Equal timestamps (a doubled word) — no span for the first
        // word, so it is complete the moment its moment arrives. The
        // last word still owns its window to the line's end and has
        // not begun.
        let words = [
            LyricWord(timestamp: 10, text: "one"),
            LyricWord(timestamp: 10, text: "one"),
        ]
        let states = LyricSweep.wordStates(
            words: words, text: "one one", at: 10, window: 10.0...14.0
        )
        XCTAssertEqual(states[0].sungFraction, 1)
        XCTAssertEqual(states[1].sungFraction, 0)
    }

    func testExactWordsNeverEscapeTheLineWindow() {
        // A word stamped before the line's window starts (bad data) is
        // clamped to the window — the wavefront never runs backwards.
        let words = [LyricWord(timestamp: 8, text: "one")]
        let states = LyricSweep.wordStates(
            words: words, text: "one", at: 9, window: 10.0...14.0
        )
        XCTAssertEqual(states[0].sungFraction, 0)
    }

    // MARK: - Interpolated fallback

    func testInterpolatedFallbackMatchesTheOriginalDivision() {
        // "hello world": tokens ["hello", "world"] with weights 5 and
        // 5 over 10 — the line window divides evenly across the words,
        // exactly what the UI's first sweep did.
        let states = LyricSweep.wordStates(
            words: nil, text: "hello world", at: 5, window: 0.0...10.0
        )
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states[0].text, "hello")
        // The boundary lands exactly at the half: the first word is
        // done, the second has not begun.
        XCTAssertEqual(states[0].sungFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(states[1].text, "world")
        XCTAssertEqual(states[1].sungFraction, 0, accuracy: 0.0001)
    }

    func testInterpolatedFallbackSeparatorTokenOnDoubleSpace() {
        // Consecutive separators leave an empty token; it is rendered
        // as a space and owns a character-weighted slice like any
        // other token — the mapping the UI's first sweep applied.
        let states = LyricSweep.wordStates(
            words: nil, text: "hello  world", at: 0, window: 0.0...11.0
        )
        XCTAssertEqual(states.count, 3)
        XCTAssertEqual(states[1].text, " ")
        XCTAssertEqual(states[1].sungFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(states[2].text, "world")
    }

    func testInterpolatedFallbackMidWord() {
        // Weights 5 and 5 over a 10 s window: "world" occupies
        // 0.5→1.0. At 7.5 s it is halfway crossed.
        let states = LyricSweep.wordStates(
            words: nil, text: "hello world", at: 7.5, window: 0.0...10.0
        )
        XCTAssertEqual(states[1].sungFraction, 0.5, accuracy: 0.0001)
    }

    func testInterpolatedFallbackLongWordsHoldTheWavefront() {
        // "aaaaaaaaaa b" — the long token owns 10/11 of the window.
        let states = LyricSweep.wordStates(
            words: nil, text: "aaaaaaaaaa b", at: 5, window: 0.0...11.0
        )
        XCTAssertEqual(states[0].sungFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(states[1].sungFraction, 0)
    }

    func testNilAndEmptyWordsBothFallBack() {
        let line = "one two"
        let a = LyricSweep.wordStates(words: nil, text: line, at: 1, window: 0.0...2.0)
        let b = LyricSweep.wordStates(words: [], text: line, at: 1, window: 0.0...2.0)
        XCTAssertEqual(a, b)
    }

    // MARK: - Letters

    func testLetterProgressReachesAcrossTheWord() {
        // Five letters: at word-sung 0.5 the third letter is halfway.
        let progress = LyricSweep.letterProgress(wordSung: 0.5, letterIndex: 2, letterCount: 5)
        XCTAssertEqual(progress, 0.5, accuracy: 0.0001)
    }

    func testLetterProgressClamps() {
        XCTAssertEqual(LyricSweep.letterProgress(wordSung: 0, letterIndex: 1, letterCount: 5), 0)
        XCTAssertEqual(LyricSweep.letterProgress(wordSung: 1, letterIndex: 0, letterCount: 5), 1)
        // Out-of-range letters never swell.
        XCTAssertEqual(LyricSweep.letterProgress(wordSung: 1, letterIndex: 5, letterCount: 5), 0)
        XCTAssertEqual(LyricSweep.letterProgress(wordSung: 0.5, letterIndex: -1, letterCount: 5), 0)
    }

    // MARK: - Model round trip

    func testLyricLineWithWordsCodableRoundTrip() throws {
        let line = LyricLine(
            timestamp: 10,
            text: "one two",
            words: [
                LyricWord(timestamp: 10, text: "one"),
                LyricWord(timestamp: 11, text: "two"),
            ]
        )
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(LyricLine.self, from: data)
        XCTAssertEqual(decoded, line)
        XCTAssertEqual(decoded.words?.count, 2)
    }

    func testLyricLinePayloadWithoutWordsDecodesAsNil() throws {
        // A cached payload written before `words` existed must decode.
        let json = #"{"timestamp":10,"text":"one two"}"#
        let decoded = try JSONDecoder().decode(LyricLine.self, from: Data(json.utf8))
        XCTAssertNil(decoded.words)
    }
}
