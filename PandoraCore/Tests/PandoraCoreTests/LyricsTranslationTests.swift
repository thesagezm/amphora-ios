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
        // Two lines in, but the answer carries no line breaks to
        // rebuild them from — the alignment cannot be trusted.
        let response = Data("""
        [[["I am a cat, and a black one","Je suis un chat, chat noir",null,null,3]],null,"fr",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Je suis un chat", "Chat noir"])

        XCTAssertEqual(outcome, .failed(reason: "unexpected response"))
    }

    func testASplitLineIsReassembledFromTheSegmentTexts() async {
        // The service splits a *long* line into several segments — the
        // pieces joined are the line's translation, and the answer is
        // not a misalignment.
        let response = Data("""
        [[["I am a ca","Je suis un ",null,null,3],["t","chat",null,null,3]],null,"fr",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [.success(response)])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Je suis un chat"])

        XCTAssertEqual(outcome, .translated(["I am a cat"]))
    }

    // MARK: - Empty lines and rate limits

    func testEmptyLinesAreNotSentAndMapBackEmpty() async {
        let transport = StubGETTransport(responses: [.success(Data("""
        [[["I walk alone","Je marche seul",null,null,3],["People I don't know","Des gens que je ne connais pas",null,null,3]],null,"fr",null,null,null,1]
        """.utf8))])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(
            of: ["Je marche seul", "", "Des gens que je ne connais pas"]
        )

        // The blank section separator gets "" — never a shifted answer.
        XCTAssertEqual(
            outcome,
            .translated(["I walk alone", "", "People I don't know"])
        )
        // The blank line never reaches the wire.
        let url = try? URLComponents(url: transport.requests[0].url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(url?.queryItems?.value(for: "q"), "Je marche seul\nDes gens que je ne connais pas")
    }

    func testRateLimitRetriesAndThenSucceeds() async {
        // The free endpoint 429s by IP; the client backs off and asks
        // again instead of reporting a failed translation.
        let response = Data("""
        [[["I am a cat","Je suis un chat",null,null,3]],null,"fr",null,null,null,1]
        """.utf8)
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 429")),
            .success(response),
        ])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Je suis un chat"])

        XCTAssertEqual(outcome, .translated(["I am a cat"]))
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRateLimitGivesUpAfterTwoRetries() async {
        let transport = StubGETTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 429")),
            .failure(PandoraTransportError(reason: "HTTP 429")),
            .failure(PandoraTransportError(reason: "HTTP 429")),
        ])
        let client = GoogleTranslateClient(transport: transport)

        let outcome = await client.englishTranslation(of: ["Bonjour"])

        XCTAssertEqual(outcome, .failed(reason: "HTTP 429"))
        XCTAssertEqual(transport.requests.count, 3)
    }
}

private extension [URLQueryItem] {
    func value(for name: String) -> String? {
        first { $0.name == name }?.value
    }
}
