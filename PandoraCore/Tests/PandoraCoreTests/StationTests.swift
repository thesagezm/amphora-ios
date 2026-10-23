//
//  StationTests.swift
//  PandoraCoreTests
//
//  Model decoding for `user.getStationList` results from captured-shape
//  fixtures: full pithos-required + pydora-optional fields, sparse
//  minimal stations, string-or-number ids, and envelope-level errors.
//

import XCTest
@testable import PandoraCore

final class StationTests: XCTestCase {

    /// Full station as the API returns it: pithos' required set plus
    /// pydora's optional set.
    private let fullStationJSON =
        #"{"stationId":"123456","stationToken":"ST123","stationName":"Weezer Radio","#
        + #","isShared":false,"isQuickMix":false,"isThumbprint":false,"isGenreStation":false,"#
        + #""artUrl":"https://art.example/s.png","allowAddMusic":true,"allowDelete":true,"#
        + #""allowRename":true,"thumbCount":7}"#

    func testDecodesFullStationFields() throws {
        let json = #"{"stations":[\#(fullStationJSON)],"checksum":"abc"}"#
        let list = try StationList(result: try result(json))

        XCTAssertEqual(list.stations.count, 1)
        XCTAssertEqual(list.checksum, "abc")
        let s = try XCTUnwrap(list.stations.first)
        XCTAssertEqual(s.id, "123456")
        XCTAssertEqual(s.token, "ST123")
        XCTAssertEqual(s.name, "Weezer Radio")
        XCTAssertFalse(s.isShared)
        XCTAssertFalse(s.isQuickMix)
        XCTAssertFalse(s.isThumbprint)
        XCTAssertFalse(s.isGenreStation)
        XCTAssertEqual(s.artUrl, "https://art.example/s.png")
        XCTAssertEqual(s.quickMixStationIds, [])
    }

    func testDecodesMinimalStationWithDefaults() throws {
        // pithos' required set only — everything else defaults.
        let json = #"{"stations":[{"stationId":99,"stationToken":"T9","stationName":"Shared Mix","isShared":true,"isQuickMix":false}]}"#
        let list = try StationList(result: try result(json))
        let s = try XCTUnwrap(list.stations.first)
        // Numeric wire ids decode to the string form.
        XCTAssertEqual(s.id, "99")
        XCTAssertEqual(s.token, "T9")
        XCTAssertTrue(s.isShared)
        XCTAssertFalse(s.isQuickMix)
        XCTAssertNil(s.artUrl)
        XCTAssertNil(list.checksum)
    }

    func testDecodesQuickMixStationIds() throws {
        let json = #"{"stations":[{"stationId":"q","stationToken":"Q","stationName":"QuickMix","isShared":false,"isQuickMix":true,"quickMixStationIds":["1","2"]}]}"#
        let list = try StationList(result: try result(json))
        let q = try XCTUnwrap(list.stations.first)
        XCTAssertTrue(q.isQuickMix)
        XCTAssertEqual(q.quickMixStationIds, ["1", "2"])
    }

    func testMissingStationsArrayIsTypedError() {
        XCTAssertThrowsError(
            try StationList(result: ["checksum": .string("c")])
        ) { error in
            XCTAssertTrue(error is PandoraMalformedResponseError, "got \(error)")
        }
    }

    func testStationListRequiresSession() async {
        let subject = makeManager()
        do {
            _ = try await subject.getStationList()
            XCTFail("expected notAuthenticated")
        } catch let error as SessionManagerError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - Helpers

    private func result(_ objectJSON: String) throws -> [String: AnyJSON] {
        let envelope = Data(#"{"stat":"ok","result":\#(objectJSON)}"#.utf8)
        return try ResponseEnvelope.result(from: envelope)
    }

    private func makeManager() -> SessionManager {
        SessionManager(
            client: LegacyPandoraClient(transport: MockTransport(responses: [])),
            store: nil,
            now: { Date(timeIntervalSince1970: 1_000_000_000) }
        )
    }
}
