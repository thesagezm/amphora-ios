import XCTest
@testable import PandoraCore

/// The translation of a lyric set: the model changes (a plain-text
/// translation has to live somewhere), the pure apply helpers (they
/// refuse a misaligned answer rather than shifting every line), and
/// the translator's three outcomes — a translation, "already English"
/// and a failure — which the player shows to the user.
final class LyricsTranslationTests: XCTestCase {

    // MARK: - The model

    func testPlainTranslationIsStored() {
        let lyrics = Lyrics(plainText: "Je suis un chat")
            .applyingPlainTranslation("I am a cat")

        XCTAssertEqual(lyrics.plainTranslation, "I am a cat")
        XCTAssertTrue(lyrics.hasTranslation)
        XCTAssertEqual(lyrics.plainText, "Je suis un chat")
    }

    func testEmptyPlainTranslationIsRefused() {
        let original = Lyrics(plainText: "Je suis un chat")

        XCTAssertEqual(original.applyingPlainTranslation(nil), original)
        XCTAssertEqual(original.applyingPlainTranslation(""), original)
        XCTAssertFalse(original.hasTranslation)
    }

    func testSyncedTranslationFillsEveryLine() {
        let lyrics = Lyrics(lines: [
            LyricLine(timestamp: 0, text: "Je suis un chat"),
            LyricLine(timestamp: 5, text: "Chat noir")
        ]).applyingTranslation(["I am a cat", "Black cat"])

        XCTAssertEqual(lyrics.lines.map(\.translation), ["I am a cat", "Black cat"])
        XCTAssertTrue(lyrics.hasTranslation)
    }

    func testMisalignedTranslationIsRefused() {
        // One answer for two lines would shift the whole alignment —
        // every line would show the wrong words.
        let original = Lyrics(lines: [
            LyricLine(timestamp: 0, text: "Je suis un chat"),
            LyricLine(timestamp: 5, text: "Chat noir")
        ])

        let updated = original.applyingTranslation(["I am a cat"])

        XCTAssertEqual(updated, original)
        XCTAssertFalse(updated.hasTranslation)
    }

    func testTranslationOnPlainLyricsIsRefused() {
        // The line helper only applies to synchronised lyrics.
        let original = Lyrics(plainText: "Je suis un chat")

        XCTAssertEqual(original.applyingTranslation(["I am a cat"]), original)
    }

    func testHasTranslationIgnoresEmptyLineTranslations() {
        let lyrics = Lyrics(lines: [
            LyricLine(timestamp: 0, text: "Hello", translation: "")
        ])

        XCTAssertFalse(lyrics.hasTranslation)
    }

    func testDecodingALyricsPayloadWithoutThePlainTranslation() throws {
        // A payload written before `plainTranslation` existed must still
        // decode — a missing key must not throw the lyrics away.
        let json = Data("""
        {"lines":[],"plainText":"Je suis un chat","instrumental":false,"trackID":42}
        """.utf8)

        let lyrics = try JSONDecoder().decode(Lyrics.self, from: json)

        XCTAssertEqual(lyrics.plainText, "Je suis un chat")
        XCTAssertNil(lyrics.plainTranslation)
        XCTAssertEqual(lyrics.trackID, 42)
    }

    func testEncodingKeepsThePlainTranslation() throws {
        let lyrics = Lyrics(plainText: "Je suis un chat")
            .applyingPlainTranslation("I am a cat")

        let data = try JSONEncoder().encode(lyrics)
        let decoded = try JSONDecoder().decode(Lyrics.self, from: data)

        XCTAssertEqual(decoded, lyrics)
        XCTAssertEqual(decoded.plainTranslation, "I am a cat")
    }

    // MARK: - The translator's three answers

    func testTranslatorReportsTheTranslation() async {
        let response = Data("""
        [[["I am a cat","Je suis un chat",null,null,3]],null,"fr",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Je suis un chat"])

        XCTAssertEqual(outcome, .translated(["I am a cat"]))
    }

    func testTranslatorReportsEnglishLyrics() async {
        let response = Data("""
        [[["Hallelujah","Hallelujah",null,null,5]],null,"en",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Hallelujah"])

        XCTAssertEqual(outcome, .alreadyEnglish)
    }

    func testTranslatorReportsAFailure() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "network failure"))
        ])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Bonjour"])

        XCTAssertEqual(outcome, .failed(reason: "network failure"))
    }

    func testTranslatorReportsAMisalignedAnswerAsAFailure() async {
        // Two answers for one line: the alignment cannot be trusted.
        let response = Data("""
        [[["I am a cat","Je suis un chat",null,null,3],["Black cat","Chat noir",null,null,3]],null,"fr",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Je suis un chat"])

        XCTAssertEqual(outcome, .failed(reason: "unexpected response"))
    }
}
