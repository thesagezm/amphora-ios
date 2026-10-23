//
//  LyricsTests.swift
//  PandoraCoreTests
//
//  The LRC parser: timestamps, multiple stamps per line, metadata tags,
//  plain lyrics, and the "which line is playing?" lookup.
//

import XCTest
@testable import PandoraCore

final class LyricsTests: XCTestCase {

    // MARK: - Parsing

    func testParsesTimestampedLines() {
        let raw = """
        [00:12.00] First line
        [00:15.30] Second line
        """
        let lyrics = LRC.parse(raw)
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines[0].timestamp, 12.0, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[0].text, "First line")
        XCTAssertEqual(lyrics.lines[1].timestamp, 15.3, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[1].text, "Second line")
    }

    func testParsesMinutesAndHours() throws {
        XCTAssertEqual(try XCTUnwrap(LRC.timestamp("01:30")), 90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LRC.timestamp("10:00")), 600, accuracy: 0.001)
    }

    func testParsesFractionalSeconds() throws {
        XCTAssertEqual(try XCTUnwrap(LRC.timestamp("01:23.4")), 83.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LRC.timestamp("01:23.45")), 83.45, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LRC.timestamp("01:23.456")), 83.456, accuracy: 0.001)
        // `mm:ss:ff` — the third field is centiseconds.
        XCTAssertEqual(try XCTUnwrap(LRC.timestamp("01:23:45")), 83.45, accuracy: 0.001)
    }

    func testRejectsInvalidTimestamps() {
        XCTAssertNil(LRC.timestamp("abc"))
        XCTAssertNil(LRC.timestamp("1:2:3:4"))
        XCTAssertNil(LRC.timestamp("xx:yy"))
    }

    func testMultipleTimestampsOnOneLine() {
        let raw = "[00:10.00][01:10.00] chorus"
        let lyrics = LRC.parse(raw)
        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines[0].timestamp, 10, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[1].timestamp, 70, accuracy: 0.001)
        XCTAssertTrue(lyrics.lines.allSatisfy { $0.text == "chorus" })
    }

    func testMetadataTagsAreNotLyrics() {
        let raw = """
        [ar:The Artist]
        [ti:The Title]
        [al:The Album]
        [by:Someone]
        [00:05.00] A real line
        """
        let lyrics = LRC.parse(raw)
        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertEqual(lyrics.lines[0].text, "A real line")
    }

    func testOffsetTagShiftsTimestamps() {
        let raw = """
        [offset:500]
        [00:10.00] shifted
        """
        let lyrics = LRC.parse(raw)
        // A positive offset shifts the lyrics *earlier* by 500 ms.
        XCTAssertEqual(lyrics.lines.first?.timestamp ?? 0, 9.5, accuracy: 0.001)
    }

    func testPlainLyricsAreKeptAsText() {
        let raw = """
        Just some words
        on two lines
        """
        let lyrics = LRC.parse(raw)
        XCTAssertFalse(lyrics.isSynced)
        XCTAssertEqual(lyrics.plainText, "Just some words\non two lines")
    }

    func testLinesAreSortedByTimestamp() {
        let raw = """
        [00:30.00] later
        [00:10.00] earlier
        [00:20.00] middle
        """
        let lyrics = LRC.parse(raw)
        XCTAssertEqual(lyrics.lines.map(\.text), ["earlier", "middle", "later"])
    }

    func testEmptyDocument() {
        let lyrics = LRC.parse("")
        XCTAssertTrue(lyrics.isEmpty)
        XCTAssertFalse(lyrics.isSynced)
    }

    // MARK: - Playback lookup

    private func sampleLyrics() -> Lyrics {
        LRC.parse("""
        [00:00.00] one
        [00:10.00] two
        [00:20.00] three
        """)
    }

    func testActiveLineAtTime() {
        let lyrics = sampleLyrics()
        XCTAssertNil(lyrics.activeLine(at: -1))
        XCTAssertEqual(lyrics.activeLine(at: 0)?.text, "one")
        XCTAssertEqual(lyrics.activeLine(at: 9.99)?.text, "one")
        XCTAssertEqual(lyrics.activeLine(at: 10)?.text, "two")
        XCTAssertEqual(lyrics.activeLine(at: 25)?.text, "three")
    }

    func testNextLine() {
        let lyrics = sampleLyrics()
        XCTAssertEqual(lyrics.nextLine(after: 0)?.text, "two")
        XCTAssertEqual(lyrics.nextLine(after: 15)?.text, "three")
        XCTAssertNil(lyrics.nextLine(after: 25))
    }

    func testProgressRunsFromZeroToOne() {
        let lyrics = sampleLyrics()
        XCTAssertEqual(lyrics.progress(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(lyrics.progress(at: 5), 0.5, accuracy: 0.001)
        XCTAssertEqual(lyrics.progress(at: 10), 0, accuracy: 0.001)
    }

    func testTranslationFallsBackToOriginalText() {
        let plain = LyricLine(timestamp: 0, text: "Bonjour")
        XCTAssertEqual(plain.displayText, "Bonjour")
        let translated = LyricLine(timestamp: 0, text: "Bonjour", translation: "Hello")
        XCTAssertEqual(translated.displayText, "Hello")
    }
}
