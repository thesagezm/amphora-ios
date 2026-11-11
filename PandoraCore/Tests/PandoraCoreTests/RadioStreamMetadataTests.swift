import XCTest
@testable import PandoraCore

/// The ICY now-playing metadata: the byte state machine that finds the
/// metadata blocks in a live stream, and the "Artist - Title" split.
///
/// The byte fixtures are the real thing — the block below is what
/// Europe 1 answered with when the stream was probed live.
final class RadioStreamMetadataTests: XCTestCase {

    /// Builds the byte flow a stream produces: `interval` bytes of
    /// audio, one length byte (in blocks of 16), then the metadata.
    private func streamBytes(
        interval: Int,
        metadata: String
    ) -> Data {
        var data = Data(repeating: 0x41, count: interval)
        let padded = metadata.padding(toLength: ((metadata.utf8.count + 15) / 16) * 16, withPad: "\0", startingAt: 0)
        data.append(UInt8(padded.utf8.count / 16))
        data.append(contentsOf: Array(padded.utf8))
        return data
    }

    // MARK: - The byte state machine

    func testTheMetadataBlockIsFoundAfterTheInterval() {
        var parser = ICYMetadataParser()
        parser.setMetadataInterval(8)

        let blocks = parser.consume(
            streamBytes(interval: 8, metadata: "StreamTitle='Europe 1 - La radio libre';StreamUrl='';")
        )

        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].hasPrefix("StreamTitle='Europe 1 - La radio libre';"))
    }

    func testTheBlockIsFoundWhenItArrivesInPieces() {
        // The stream delivers whatever it likes: the audio, the length
        // byte and the block can be split across any number of reads.
        var parser = ICYMetadataParser()
        parser.setMetadataInterval(4)
        let bytes = streamBytes(
            interval: 4,
            metadata: "StreamTitle='Artist - Title';StreamUrl='';"
        )

        var blocks: [String] = []
        for byte in bytes {
            blocks += parser.consume(Data([byte]))
        }

        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].hasPrefix("StreamTitle='Artist - Title';"))
    }

    func testAZeroLengthMeansNothingChanged() {
        // A length byte of 0 is the server saying "same as before" —
        // no block, and the parser stays in step with the audio.
        var parser = ICYMetadataParser()
        parser.setMetadataInterval(4)

        var data = Data(repeating: 0x41, count: 4)
        data.append(0)
        let blocks = parser.consume(data)

        XCTAssertTrue(blocks.isEmpty)
        XCTAssertEqual(parser.state, .audio(remaining: 4))
    }

    func testTwoBlocksInOneRead() {
        var parser = ICYMetadataParser()
        parser.setMetadataInterval(4)

        var data = streamBytes(interval: 4, metadata: "StreamTitle='A - One';")
        data.append(streamBytes(interval: 4, metadata: "StreamTitle='B - Two';"))

        let blocks = parser.consume(data)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[0].contains("A - One"))
        XCTAssertTrue(blocks[1].contains("B - Two"))
    }

    func testAStreamWithoutAnIntervalNeverReportsMetadata() {
        var parser = ICYMetadataParser()
        parser.setMetadataInterval(0)

        let blocks = parser.consume(Data(repeating: 0x41, count: 64))

        XCTAssertTrue(blocks.isEmpty)
        XCTAssertFalse(parser.isSupported)
        XCTAssertEqual(parser.state, .idle)
    }

    func testTheIntervalIsReadFromTheHeaders() {
        // Servers spell the header every way there is.
        XCTAssertEqual(
            ICYMetadataParser.metadataInterval(in: ["icy-metaint": "16000"]),
            16000
        )
        XCTAssertEqual(
            ICYMetadataParser.metadataInterval(in: ["Icy-MetaInt": "1024"]),
            1024
        )
        XCTAssertEqual(
            ICYMetadataParser.metadataInterval(in: ["ICY-METAINT": " 8192 "]),
            8192
        )
        XCTAssertNil(ICYMetadataParser.metadataInterval(in: ["content-type": "audio/mpeg"]))
        XCTAssertNil(ICYMetadataParser.metadataInterval(in: ["icy-metaint": "0"]))
        XCTAssertNil(ICYMetadataParser.metadataInterval(in: ["icy-metaint": "nonsense"]))
    }

    // MARK: - The announcement

    func testTheStreamTitleIsExtracted() {
        let block = "StreamTitle='Europe 1 - La radio libre';StreamUrl='';"

        XCTAssertEqual(
            RadioStreamMetadata.streamTitle(in: block),
            "Europe 1 - La radio libre"
        )
    }

    func testAnEmptyStreamTitleIsNoSong() {
        XCTAssertNil(RadioStreamMetadata.streamTitle(in: "StreamTitle='';StreamUrl='1';"))
        XCTAssertNil(RadioStreamMetadata.streamTitle(in: "StreamUrl='1';"))
    }

    func testTheArtistAndTitleAreSplit() {
        let nowPlaying = RadioStreamMetadata.nowPlaying(
            fromStreamTitle: "Daft Punk - Around the World"
        )

        XCTAssertEqual(nowPlaying?.artist, "Daft Punk")
        XCTAssertEqual(nowPlaying?.title, "Around the World")
        XCTAssertEqual(nowPlaying?.lookupQuery, "Daft Punk Around the World")
    }

    func testATitleWithoutAnArtistIsKeptWhole() {
        let nowPlaying = RadioStreamMetadata.nowPlaying(fromStreamTitle: "Around the World")

        XCTAssertNil(nowPlaying?.artist)
        XCTAssertEqual(nowPlaying?.title, "Around the World")
        XCTAssertEqual(nowPlaying?.lookupQuery, "Around the World")
    }

    func testOnlyTheFirstSeparatorSplits() {
        // "Artist - Title - Live" must not lose its tail.
        let nowPlaying = RadioStreamMetadata.nowPlaying(
            fromStreamTitle: "Nina Simone - Feeling Good - Live At Montreux"
        )

        XCTAssertEqual(nowPlaying?.artist, "Nina Simone")
        XCTAssertEqual(nowPlaying?.title, "Feeling Good - Live At Montreux")
    }

    func testAnApostropheInTheTitleSurvives() {
        let nowPlaying = RadioStreamMetadata.nowPlaying(
            fromStreamTitle: "Celine Dion - J'ai tout oublié pour toi"
        )

        XCTAssertEqual(nowPlaying?.artist, "Celine Dion")
        XCTAssertEqual(nowPlaying?.title, "J'ai tout oublié pour toi")
    }

    func testABareHyphenIsNotASeparator() {
        // A hyphen without spaces is part of the title far more often
        // than it separates an artist from a title.
        let nowPlaying = RadioStreamMetadata.nowPlaying(
            fromStreamTitle: "Love-Hate"
        )

        XCTAssertNil(nowPlaying?.artist)
        XCTAssertEqual(nowPlaying?.title, "Love-Hate")
    }

    func testASpacedHyphenDoesSeparate() {
        let nowPlaying = RadioStreamMetadata.nowPlaying(
            fromStreamTitle: "Love - Hate"
        )

        XCTAssertEqual(nowPlaying?.artist, "Love")
        XCTAssertEqual(nowPlaying?.title, "Hate")
    }

    func testTheSongIsReadStraightFromABlock() {
        let nowPlaying = RadioStreamMetadata.nowPlaying(
            in: "StreamTitle='Europe 1 - La radio libre';StreamUrl='';"
        )

        XCTAssertEqual(nowPlaying?.artist, "Europe 1")
        XCTAssertEqual(nowPlaying?.title, "La radio libre")
    }
}
