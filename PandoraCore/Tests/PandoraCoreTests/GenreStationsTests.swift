//
//  GenreStationsTests.swift
//  PandoraCoreTests
//
//  Decoding of `station.getGenreStations` from fixture JSON (tolerant
//  entry handling) and the SessionManager facade (request shape + decode
//  under a live session).
//

import XCTest
@testable import PandoraCore

final class GenreStationsTests: XCTestCase {

    // MARK: - Decoding

    func testDecodeFullCatalog() throws {
        let result: [String: AnyJSON] = try Self.parse(
            """
            {"categories": [
                {"categoryName": "Pop", "stations": [
                    {"stationId": 12345, "stationToken": "G123",
                     "stationName": "Today's Hits", "categoryName": "Pop",
                     "artUrl": "http://cont-1.p-cdn.com/pop.jpg"},
                    {"stationId": "12346", "stationToken": "G124",
                     "stationName": "90s Pop Hits", "categoryName": "Pop"}
                ]},
                {"categoryName": "Rock", "stations": [
                    {"stationToken": "G200", "stationName": "Classic Rock"}
                ]}
            ]}
            """
        )
        let catalog = try GenreStations(result: result)

        XCTAssertEqual(catalog.categories.map(\.name), ["Pop", "Rock"])
        XCTAssertEqual(catalog.categories[0].stations.count, 2)

        let hits = catalog.categories[0].stations[0]
        XCTAssertEqual(hits.token, "G123")
        XCTAssertEqual(hits.stationId, "12345")
        XCTAssertEqual(hits.name, "Today's Hits")
        XCTAssertEqual(hits.categoryName, "Pop")
        XCTAssertEqual(hits.artUrl, "http://cont-1.p-cdn.com/pop.jpg")

        // String-form stationId tolerated; artUrl absent → nil.
        let nineties = catalog.categories[0].stations[1]
        XCTAssertEqual(nineties.stationId, "12346")
        XCTAssertNil(nineties.artUrl)

        // An entry without its own categoryName inherits the category's.
        let classic = catalog.categories[1].stations[0]
        XCTAssertEqual(classic.categoryName, "Rock")
    }

    func testDecodeDropsUnusableEntriesAndDuplicates() throws {
        let result: [String: AnyJSON] = try Self.parse(
            """
            {"categories": [
                {"categoryName": "Pop", "stations": [
                    {"stationToken": "G1", "stationName": "Kept"},
                    {"stationName": "No token — dropped"},
                    {"stationToken": "", "stationName": "Empty token — dropped"},
                    {"stationToken": "G2"},
                    {"stationToken": "G1", "stationName": "Duplicate — dropped"}
                ]},
                {"categoryName": "Empty", "stations": []},
                {"categoryName": "No stations key"},
                {"stations": [{"stationToken": "G9", "stationName": "Unnamed category"}]}
            ]}
            """
        )
        let catalog = try GenreStations(result: result)

        XCTAssertEqual(catalog.categories.count, 1)
        XCTAssertEqual(catalog.categories[0].name, "Pop")
        XCTAssertEqual(catalog.categories[0].stations.map(\.token), ["G1"])
        XCTAssertEqual(catalog.categories[0].stations[0].name, "Kept")
    }

    func testMissingCategoriesArrayIsMalformed() throws {
        XCTAssertThrowsError(try GenreStations(result: [:]))
        let notArray: [String: AnyJSON] = try Self.parse(#"{"categories": "nope"}"#)
        XCTAssertThrowsError(try GenreStations(result: notArray))
    }

    func testEmptyCategoriesIsAllowed() throws {
        let catalog = try GenreStations(result: try Self.parse(#"{"categories": []}"#))
        XCTAssertTrue(catalog.categories.isEmpty)
    }

    // MARK: - SessionManager facade

    /// Fixed local clock for the whole scenario (same shape as
    /// SessionManagerTests — static + @Sendable).
    private static let clock: @Sendable () -> Date = {
        Date(timeIntervalSince1970: 1_000_000_000)
    }
    private static let syncTimeMain =
        "ac7b93e6a3c44c45258042bca01c9f6f40befffb546dee73"

    private func ok(_ resultObjectJSON: String) -> Result<Data, Error> {
        .success(Data("{\"stat\":\"ok\",\"result\":\(resultObjectJSON)}".utf8))
    }

    private func partnerOK() -> Result<Data, Error> {
        ok(#"{"partnerId":"77","partnerAuthToken":"P-TOKEN","syncTime":"\#(Self.syncTimeMain)"}"#)
    }

    private func userOK() -> Result<Data, Error> {
        ok(#"{"userId":"u-1","userAuthToken":"U-TOKEN","isSubscriber":false}"#)
    }

    func testGetGenreStationsCallsBareAndDecodes() async throws {
        let transport = MockTransport(responses: [
            partnerOK(),
            userOK(),
            ok(
                """
                {"categories": [
                    {"categoryName": "Country", "stations": [
                        {"stationToken": "G300", "stationName": "Country Hits",
                         "categoryName": "Country"}
                    ]}
                ]}
                """
            )
        ])
        let subject = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            now: Self.clock
        )

        _ = try await subject.login(username: "me@example.com", password: "hunter2")
        let categories = try await subject.getGenreStations()

        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories[0].stations[0].token, "G300")
        XCTAssertEqual(categories[0].stations[0].name, "Country Hits")

        // The method takes no parameters — request 3 goes out bare
        // (authenticated calls carry more query params after `method=`,
        // so match on the method pair, not the suffix).
        let requests = transport.requests
        XCTAssertEqual(requests.count, 3)
        let genreRequest = try XCTUnwrap(requests.last)
        XCTAssertTrue(genreRequest.url.absoluteString.contains("method=station.getGenreStations"))
    }

    func testGetGenreStationsWithoutSessionThrows() async {
        let transport = MockTransport(responses: [])
        let subject = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            now: Self.clock
        )

        do {
            _ = try await subject.getGenreStations()
            XCTFail("expected notAuthenticated")
        } catch {
            XCTAssertEqual(error as? SessionManagerError, .notAuthenticated)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Helpers

    private static func parse(_ json: String) throws -> [String: AnyJSON] {
        let decoded = try JSONDecoder().decode(AnyJSON.self, from: Data(json.utf8))
        guard let object = decoded.objectValue else {
            throw PandoraMalformedResponseError(detail: "fixture was not a JSON object")
        }
        return object
    }
}
