//
//  LyricsRomanizationTests.swift
//  PandoraCoreTests
//
//  The alphabet romanization of non-Latin-script lyrics (Google's
//  `dt=rm` mode), against scripted GET responses. No network in any
//  unit test.
//
//  The reply shapes are the ones the live endpoint returns (verified
//  against the real service: "사랑해" → "salanghae", "君の名は" →
//  "Kiminonaha"; Latin-script input answers with no segments).
//

import XCTest
@testable import PandoraCore

final class LyricsRomanizationTests: XCTestCase {

    private func romanizationReply(_ romanized: String, language: String = "ko") -> Data {
        // One segment per call; the text sits at index 3.
        Data("""
        [[[null,null,null,"\(romanized)"]],null,"\(language)",null,null,null,1]
        """.utf8)
    }

    // MARK: The endpoint

    func testRomanizesKoreanLine() async throws {
        let transport = StubGETTransport(responses: [
            .success(romanizationReply("salanghae"))
        ])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["사랑해"])

        XCTAssertEqual(romanized, ["salanghae"])
        let request = try XCTUnwrap(transport.requests.first)
        let url = request.url.absoluteString
        XCTAssertTrue(url.contains("dt=rm"), "the romanization mode must be requested")
        XCTAssertTrue(url.contains("sl=auto"))
        XCTAssertTrue(url.contains("q="))
        XCTAssertNotNil(request.headers["User-Agent"])
    }

    func testMultiLineReplyPreservesLineAlignment() async throws {
        // Verified live: the reply keeps the line breaks, so one segment
        // can carry several romanized lines.
        let transport = StubGETTransport(responses: [
            .success(romanizationReply("salanghae\\nannyeong"))
        ])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["사랑해", "안녕"])

        XCTAssertEqual(romanized, ["salanghae", "annyeong"])
    }

    func testOneSegmentPerLineAlsoAligns() async throws {
        // The service may also return one segment per line with no
        // embedded breaks.
        let response = Data("""
        [[[null,null,null,"salanghae"],[null,null,null,"annyeong"]],null,"ko",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["사랑해", "안녕"])

        XCTAssertEqual(romanized, ["salanghae", "annyeong"])
    }

    func testJapaneseRomanizesToAlphabet() async throws {
        let transport = StubGETTransport(responses: [
            .success(romanizationReply("Kiminonaha", language: "ja"))
        ])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["君の名は"])

        XCTAssertEqual(romanized, ["Kiminonaha"])
    }

    // MARK: The gates that keep the request count down

    func testLatinScriptSkipsTheRequestEntirely() async {
        let transport = StubGETTransport(responses: [])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["Hallelujah", "je t'aime"])

        XCTAssertNil(romanized)
        // English/French lyrics must cost zero extra Google requests —
        // the endpoint rate-limits probing IPs.
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testNoSegmentsReplyReturnsNil() async {
        // Latin-script input answers `[null,null,"en",…]` — no segments.
        // Even for non-Latin input the same shape means "nothing to do".
        let response = Data("""
        [null,null,"en",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["사랑해"])

        XCTAssertNil(romanized)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testMisalignedReplyIsNeverShown() async {
        // Two input lines but one romanized line — showing it would
        // shift every later line.
        let transport = StubGETTransport(responses: [
            .success(romanizationReply("salanghae"))
        ])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["사랑해", "안녕"])

        XCTAssertNil(romanized)
    }

    func testTransportFailureReturnsNil() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "network failure"))
        ])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: ["사랑해"])

        XCTAssertNil(romanized)
    }

    func testEmptyInputNeedsNoRequest() async {
        let transport = StubGETTransport(responses: [])
        let client = GoogleTranslateClient(transport: transport)

        let romanized = await client.romanization(of: [])

        XCTAssertNil(romanized)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: The script check

    func testNonLatinScriptsAreDetected() {
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("사랑해"))  // Hangul
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("君の名は"))  // kanji + kana
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("ひらがな"))  // hiragana
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("カタカナ"))  // katakana
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("我爱你"))  // CJK
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("สวัสดี"))  // Thai
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("Привет"))  // Cyrillic
    }

    func testLatinScriptIsNotDetected() {
        XCTAssertFalse(GoogleTranslateClient.containsNonLatinScript("Hallelujah"))
        XCTAssertFalse(GoogleTranslateClient.containsNonLatinScript("je t'aime déjà"))
        XCTAssertFalse(GoogleTranslateClient.containsNonLatinScript("Saudade coração"))
        XCTAssertFalse(GoogleTranslateClient.containsNonLatinScript("1234 — hey!"))
        XCTAssertFalse(GoogleTranslateClient.containsNonLatinScript(""))
    }

    func testMixedScriptIsDetected() {
        // A line with a single non-Latin word still needs romanization.
        XCTAssertTrue(GoogleTranslateClient.containsNonLatinScript("I love you, 사랑해"))
    }

    // MARK: The model

    func testLyricLineDecodesWithoutRomanization() throws {
        // A cached lyric line from an older build carries no romanization.
        let data = Data(#"{"timestamp":12.0,"text":"사랑해","translation":"love"}"#.utf8)
        let line = try JSONDecoder().decode(LyricLine.self, from: data)

        XCTAssertEqual(line.text, "사랑해")
        XCTAssertEqual(line.translation, "love")
        XCTAssertNil(line.romanization)
    }

    func testLyricLineRoundTripsWithRomanization() throws {
        let line = LyricLine(timestamp: 12, text: "사랑해", translation: "love", romanization: "salanghae")
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(LyricLine.self, from: data)

        XCTAssertEqual(decoded, line)
    }
}
