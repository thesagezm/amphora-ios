//
//  MusixmatchLyricsTests.swift
//  PandoraCoreTests
//
//  The Musixmatch provider's pure surfaces, against captured wire
//  shapes: rich-sync ingestion (fragments → runs → words), the
//  distrustful scoring, the signed request shape (a known-answer HMAC
//  vector), the in-band auth refresh, and the line-timed fallback.
//

import XCTest
@testable import PandoraCore

final class MusixmatchLyricsTests: XCTestCase {
    // MARK: - Rich sync ingestion

    func testRichSyncLineBecomesWordsWithTimestamps() {
        let body = """
        [{"ts":10,"te":14,"x":"one two","l":[
            {"c":"one","o":0},
            {"c":" two","o":2}
        ]}]
        """
        let lines = MusixmatchLyricsProvider.parseRichSyncBody(body)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "one two")
        XCTAssertEqual(lines[0].timestamp, 10)
        let words = lines[0].words ?? []
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0].text, "one")
        XCTAssertEqual(words[0].timestamp, 10)
        // " two" starts with a space: it does not glue to the word in
        // hand, and its offset makes it start at 12.
        XCTAssertEqual(words[1].text, "two")
        XCTAssertEqual(words[1].timestamp, 12)
    }

    func testRichSyncSyllablesGlueIntoWords() {
        // "e" + "nough " + "now": no space after "e" glues it to
        // "nough"; the trailing space ends the word; "now" starts fresh.
        let body = """
        [{"ts":0,"te":6,"x":"","l":[
            {"c":"e","o":0},
            {"c":"nough ","o":1},
            {"c":"now","o":3}
        ]}]
        """
        let lines = MusixmatchLyricsProvider.parseRichSyncBody(body)
        XCTAssertEqual(lines.count, 1)
        // The line text falls back to the joined words when `x` is
        // empty.
        XCTAssertEqual(lines[0].text, "enough now")
        let words = lines[0].words ?? []
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0].text, "enough")
        XCTAssertEqual(words[0].timestamp, 0)
        XCTAssertEqual(words[1].text, "now")
        XCTAssertEqual(words[1].timestamp, 3)
    }

    func testRichSyncUnspacedScriptFragmentsStaySeparate() {
        // Han carries no spaces — every fragment is a word of its own,
        // glue never fires across it.
        let body = """
        [{"ts":0,"te":4,"x":"今日","l":[
            {"c":"今","o":0},
            {"c":"日","o":2}
        ]}]
        """
        let lines = MusixmatchLyricsProvider.parseRichSyncBody(body)
        let words = lines[0].words ?? []
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0].text, "今")
        XCTAssertEqual(words[1].text, "日")
    }

    func testRichSyncBlankFragmentEndsTheWord() {
        // A fragment whose text is only whitespace closes the word in
        // hand — the stamp between two words.
        let body = """
        [{"ts":0,"te":8,"x":"","l":[
            {"c":"one ","o":0},
            {"c":" ","o":2},
            {"c":"two","o":4}
        ]}]
        """
        let lines = MusixmatchLyricsProvider.parseRichSyncBody(body)
        let words = lines[0].words ?? []
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0].text, "one")
        XCTAssertEqual(words[1].text, "two")
    }

    func testRichSyncLinesSortByTimestamp() {
        let body = """
        [{"ts":20,"te":24,"x":"later","l":[]},
         {"ts":10,"te":14,"x":"earlier","l":[]}]
        """
        let lines = MusixmatchLyricsProvider.parseRichSyncBody(body)
        XCTAssertEqual(lines.map(\.text), ["earlier", "later"])
    }

    func testRichSyncMalformedBodyYieldsNothing() {
        XCTAssertTrue(MusixmatchLyricsProvider.parseRichSyncBody("not json").isEmpty)
    }

    // MARK: - Scoring

    func testScoreExactTitleAndDurationWins() {
        let exact = MusixmatchLyricsProvider.CandidateTrack(
            trackID: 1, trackName: "Tous les chemins", artistName: "Céline Dion",
            trackLength: 200, hasSubtitles: 1, hasRichSync: 1
        )
        let loose = MusixmatchLyricsProvider.CandidateTrack(
            trackID: 2, trackName: "Les chemins (Live)", artistName: "Olivier Dion",
            trackLength: 240, hasSubtitles: 1, hasRichSync: 0
        )
        let exactScore = MusixmatchLyricsProvider.score(
            exact, title: "Tous les chemins", artist: "Céline Dion", seconds: 200
        )
        let looseScore = MusixmatchLyricsProvider.score(
            loose, title: "Tous les chemins", artist: "Céline Dion", seconds: 200
        )
        XCTAssertGreaterThan(exactScore, looseScore)
    }

    func testScoreBelowTheFloorRefusesEverySignalFailed() {
        // No title match, no artist match, duration far off — the
        // candidate scores below 40 and the caller refuses it, never
        // guesses.
        let wrong = MusixmatchLyricsProvider.CandidateTrack(
            trackID: 1, trackName: "Something Else", artistName: "Someone Else",
            trackLength: 90, hasSubtitles: 1, hasRichSync: 1
        )
        let score = MusixmatchLyricsProvider.score(
            wrong, title: "Tous les chemins", artist: "Céline Dion", seconds: 200
        )
        XCTAssertLessThan(score, 40)
    }

    // MARK: - Track search decode

    func testTrackSearchDecode() {
        let body = """
        {"message":{"header":{"status_code":200},"body":{"track_list":[
            {"track":{"track_id":123,"track_name":"Song","artist_name":"Artist",
             "track_length":210,"has_subtitles":1,"has_richsync":1}}
        ]}}}
        """
        let candidates = MusixmatchLyricsProvider.decodeTrackSearch(body)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].trackID, 123)
        XCTAssertEqual(candidates[0].hasRichSync, 1)
    }

    // MARK: - Signed request

    func testSignatureKnownAnswerVector() {
        // HMAC-SHA256 over <normalized url><UTC date>, base64 — the
        // vector computed independently with hashlib.
        let url = "https://apic.musixmatch.com/ws/1.1/token.get"
            + "?app_id=mobile-app-v1.0&format=json&guid=ABC"
        let signed = MusixmatchLyricsProvider.sign(
            url: url, secret: "f09016176ba43a1cfd1031fbd6b3d26c", date: "20260119"
        )
        XCTAssertEqual(
            signed,
            url
                + "&signature=btDXaaaQxeUKXfNu010yPgvyhIB%2FOV8jyDR2lhe%2B37k%3D"
                + "&signature_protocol=sha256"
        )
    }

    func testSignNormalizesSpacesToPlus() {
        // The web client normalizes %20 and spaces to + before signing.
        let signed = MusixmatchLyricsProvider.sign(
            url: "https://apic.musixmatch.com/ws/1.1/x?q=a%20b c",
            secret: "s", date: "20260119"
        )
        XCTAssertTrue(signed.contains("q=a+b+c&"))
    }

    func testLooksUnauthorized() {
        XCTAssertTrue(
            MusixmatchLyricsProvider.looksUnauthorized(
                #"{"message":{"header":{"status_code":401},"body":{}}}"#
            )
        )
        XCTAssertTrue(
            MusixmatchLyricsProvider.looksUnauthorized(
                #"{"message":{"header":{"status_code":402},"body":{}}}"#
            )
        )
        XCTAssertFalse(
            MusixmatchLyricsProvider.looksUnauthorized(
                #"{"message":{"header":{"status_code":200},"body":{}}}"#
            )
        )
    }

    // MARK: - Line-timed fallback

    func testSubtitleBodyConvertsToLRCAndParses() {
        let body = """
        [{"text":"first line","time":{"total":10.5}},
         {"text":"second line","time":{"total":13}}]
        """
        let lrc = MusixmatchLyricsProvider.subtitleToLRC(body)
        XCTAssertTrue(lrc.contains("[00:10.500]first line"))
        XCTAssertTrue(lrc.contains("[00:13.000]second line"))
        let parsed = LRC.parse(lrc)
        XCTAssertEqual(parsed.lines.count, 2)
        XCTAssertEqual(parsed.lines[0].timestamp, 10.5, accuracy: 0.001)
    }

    func testSubtitleBodySkipsBlankLines() {
        let body = """
        [{"text":"","time":{"total":1}},
         {"text":"kept","time":{"total":2}}]
        """
        let lrc = MusixmatchLyricsProvider.subtitleToLRC(body)
        let parsed = LRC.parse(lrc)
        XCTAssertEqual(parsed.lines.count, 1)
        XCTAssertEqual(parsed.lines[0].text, "kept")
    }
}
