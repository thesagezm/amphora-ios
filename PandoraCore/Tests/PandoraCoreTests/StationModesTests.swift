//
//  StationModesTests.swift
//  PandoraCoreTests
//
//  Listening modes: wire decoding (modeId number-or-string, sparse
//  entries, unavailable stations), the exact request shape of both
//  `interactiveradio` endpoints, the 401 → csrf-refresh → retry-once
//  contract, and the SessionManager facade (premium gate on a free
//  account, 401 → re-login → retry, not-authenticated).
//
//  Swift 6 notes: recorded request arrays are hoisted out of XCT*
//  autoclosures (no `await` inside an autoclosure); NSLock calls live in
//  sync helpers only.
//

import XCTest
@testable import PandoraCore

// MARK: - Mocks

private final class MockModesTransport: ModesTransport, @unchecked Sendable {
    struct Call {
        let url: URL
        let body: Data
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let responses: [Result<ModesHTTPResponse, Error>]
    private var next = 0

    init(responses: [Result<ModesHTTPResponse, Error>]) {
        self.responses = responses
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func post(url: URL, body: Data, headers: [String: String]) async throws -> ModesHTTPResponse {
        let index = record(url: url, body: body, headers: headers)
        guard index < responses.count else {
            throw PandoraTransportError(reason: "mock exhausted at request \(index)")
        }
        return try responses[index].get()
    }

    private func record(url: URL, body: Data, headers: [String: String]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(Call(url: url, body: body, headers: headers))
        let index = next
        next += 1
        return index
    }
}

private final class MockCSRF: CSRFTokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens = 0
    private var refreshes = 0

    var tokenCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tokens
    }

    var refreshCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return refreshes
    }

    func token() async throws -> String {
        bumpTokens()
        return "csrf-token"
    }

    func refresh() async throws -> String {
        bumpRefreshes()
        return "csrf-refreshed"
    }

    // NSLock calls may not run in an async frame — sync helpers only.
    private func bumpTokens() {
        lock.lock()
        defer { lock.unlock() }
        tokens += 1
    }

    private func bumpRefreshes() {
        lock.lock()
        defer { lock.unlock() }
        refreshes += 1
    }
}

// MARK: - Decoding tests

final class StationModesDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> StationModes {
        try StationModes(data: Data(json.utf8))
    }

    func testFullReplyDecodes() throws {
        let modes = try decode("""
        {
          "interactiveRadioAvailable": true,
          "currentModeId": 1,
          "availableModesHeader": "Available modes",
          "hasTakeoverModes": false,
          "availableModes": [
            {"modeId":1,"modeName":"My Mix","modeDescription":"A blend of your stations",
             "isModeAvailable":true,"isPremiumOnly":false},
            {"modeId":2,"modeName":"Deep Cuts","modeDescription":"More obscure tracks",
             "isModeAvailable":true,"isPremiumOnly":false},
            {"modeId":5,"modeName":"Artist Only","modeDescription":"Just the artist",
             "isModeAvailable":true,"isPremiumOnly":true}
          ]
        }
        """)
        XCTAssertTrue(modes.isInteractiveRadioAvailable)
        XCTAssertEqual(modes.currentModeID, 1)
        XCTAssertEqual(modes.modes.map(\.id), [1, 2, 5])
        XCTAssertEqual(modes.modes[1].name, "Deep Cuts")
        XCTAssertEqual(modes.modes[1].modeDescription, "More obscure tracks")
        XCTAssertTrue(modes.modes[1].isAvailable)
        XCTAssertFalse(modes.modes[1].isPremiumOnly)
        XCTAssertEqual(modes.currentMode?.name, "My Mix")
        XCTAssertTrue(modes.mode(id: 5)?.isPremiumOnly ?? false)
    }

    func testModeIdAsDigitString() throws {
        let modes = try decode("""
        {"currentModeId":"3","availableModes":[
          {"modeId":"3","modeName":"Discovery","isModeAvailable":true}]}
        """)
        XCTAssertEqual(modes.currentModeID, 3)
        XCTAssertEqual(modes.modes.first?.id, 3)
        XCTAssertEqual(modes.currentMode?.name, "Discovery")
    }

    func testSparseFlagsDefault() throws {
        // No isModeAvailable/isPremiumOnly/interactiveRadioAvailable at all.
        let modes = try decode("""
        {"availableModes":[{"modeId":7,"modeName":"Mystery Mode"}]}
        """)
        XCTAssertEqual(modes.modes.count, 1)
        let mode = try XCTUnwrap(modes.modes.first)
        XCTAssertFalse(mode.isAvailable)
        XCTAssertFalse(mode.isPremiumOnly)
        XCTAssertEqual(mode.modeDescription, "")
    }

    func testUnusableEntriesAreDropped() throws {
        let modes = try decode("""
        {"availableModes":[
          {"modeName":"No id"},
          {"modeId":2,"modeName":""},
          {"modeId":"x","modeName":"Bad id"},
          {"modeId":3,"modeName":"First"},
          {"modeId":3,"modeName":"Duplicate"}
        ]}
        """)
        XCTAssertEqual(modes.modes.map(\.name), ["First"])
    }

    func testUnavailableStationDecodesWithoutModes() throws {
        let modes = try decode("""
        {"interactiveRadioAvailable":false}
        """)
        XCTAssertFalse(modes.isInteractiveRadioAvailable)
        XCTAssertTrue(modes.modes.isEmpty)
        XCTAssertNil(modes.currentModeID)
    }

    func testMissingModesArrayOnAvailableStationIsMalformed() {
        XCTAssertThrowsError(try decode(#"{"interactiveRadioAvailable":true}"#)) { error in
            XCTAssertTrue(error is PandoraMalformedResponseError)
        }
    }

    func testErrorCodeBodyIsMalformed() {
        XCTAssertThrowsError(try decode(#"{"errorCode":1023,"message":"bad"}"#)) { error in
            XCTAssertTrue(error is PandoraMalformedResponseError)
        }
    }

    func testStatFailBodyIsMalformed() {
        XCTAssertThrowsError(try decode(#"{"stat":"fail","code":1001}"#)) { error in
            XCTAssertTrue(error is PandoraMalformedResponseError)
        }
    }

    func testSelectableGate() {
        let free = StationMode(id: 5, name: "Artist Only", isAvailable: true, isPremiumOnly: true)
        XCTAssertTrue(free.isSelectable(isSubscriber: true))
        XCTAssertFalse(free.isSelectable(isSubscriber: false))
        let plain = StationMode(id: 2, name: "Deep Cuts", isAvailable: true)
        XCTAssertTrue(plain.isSelectable(isSubscriber: false))
        let unoffered = StationMode(id: 9, name: "Elsewhere", isAvailable: false)
        XCTAssertFalse(unoffered.isSelectable(isSubscriber: true))
    }
}

// MARK: - Client tests

final class StationModesClientTests: XCTestCase {

    private func ok(_ json: String) -> Result<ModesHTTPResponse, Error> {
        .success(ModesHTTPResponse(statusCode: 200, body: Data(json.utf8)))
    }

    private func status(_ code: Int) -> Result<ModesHTTPResponse, Error> {
        .success(ModesHTTPResponse(statusCode: code, body: Data("{}".utf8)))
    }

    private func makeClient(
        _ responses: [Result<ModesHTTPResponse, Error>],
        csrf: MockCSRF = MockCSRF()
    ) -> (PandoraModesClient, MockModesTransport, MockCSRF) {
        let transport = MockModesTransport(responses: responses)
        let client = PandoraModesClient(transport: transport, csrf: csrf)
        return (client, transport, csrf)
    }

    private static let modesReply = """
    {"currentModeId":1,"availableModes":[
      {"modeId":1,"modeName":"My Mix","isModeAvailable":true}]}
    """

    /// A reply for a successful switch to mode 3 (stale-mode guard passes).
    private static let setReply = """
    {"currentModeId":3,"availableModes":[
      {"modeId":3,"modeName":"Deep Cuts","isModeAvailable":true}]}
    """

    func testGetModesRequestShape() async throws {
        let (client, transport, _) = makeClient([ok(Self.modesReply)])
        _ = try await client.getModes(userAuthToken: "U-TOKEN", stationId: "123")

        let calls = transport.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(
            call.url.absoluteString,
            "https://www.pandora.com/api/v1/interactiveradio/getAvailableModesSimple"
        )
        XCTAssertEqual(String(decoding: call.body, as: UTF8.self), "{\"stationId\":\"123\"}")
        XCTAssertEqual(call.headers["Content-Type"], "application/json")
        XCTAssertEqual(call.headers["Accept"], "application/json, text/plain, */*")
        XCTAssertEqual(call.headers["X-AuthToken"], "U-TOKEN")
        XCTAssertEqual(call.headers["X-CsrfToken"], "csrf-token")
        XCTAssertEqual(call.headers["Origin"], "https://www.pandora.com")
        XCTAssertEqual(call.headers["Referer"], "https://www.pandora.com/")
        XCTAssertEqual(call.headers["X-Requested-With"], "XMLHttpRequest")
        XCTAssertFalse(call.headers["User-Agent"]?.isEmpty ?? true)
    }

    func testSetModeRequestShape() async throws {
        // Reply carries currentModeId 3 so the stale-mode guard passes.
        let (client, transport, _) = makeClient([ok(Self.setReply)])
        _ = try await client.setMode(userAuthToken: "U-TOKEN", stationId: "123", modeId: 3, previousModeId: 1)

        let call = try XCTUnwrap(transport.calls.first)
        XCTAssertEqual(
            call.url.absoluteString,
            "https://www.pandora.com/api/v1/interactiveradio/setAndGetAvailableModes"
        )
        XCTAssertEqual(
            String(decoding: call.body, as: UTF8.self),
            "{\"modeId\":3,\"previousModeId\":1,\"stationId\":\"123\"}"
        )
    }

    func testSetModeOmitsAbsentPreviousMode() async throws {
        let (client, transport, _) = makeClient([ok(Self.setReply)])
        _ = try await client.setMode(userAuthToken: "U-TOKEN", stationId: "123", modeId: 3, previousModeId: nil)

        let call = try XCTUnwrap(transport.calls.first)
        XCTAssertEqual(
            String(decoding: call.body, as: UTF8.self),
            "{\"modeId\":3,\"stationId\":\"123\"}"
        )
    }

    func testUnauthorizedRefreshesCsrfAndRetriesOnce() async throws {
        let (client, transport, csrf) = makeClient([status(401), ok(Self.modesReply)])
        let modes = try await client.getModes(userAuthToken: "U-TOKEN", stationId: "123")
        XCTAssertEqual(modes.currentModeID, 1)

        XCTAssertEqual(csrf.tokenCount, 1)
        XCTAssertEqual(csrf.refreshCount, 1)
        let calls = transport.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first?.headers["X-CsrfToken"], "csrf-token")
        XCTAssertEqual(calls.last?.headers["X-CsrfToken"], "csrf-refreshed")
    }

    func testUnauthorizedAfterRetrySurfaces() async {
        let (client, _, _) = makeClient([status(401), status(403)])
        do {
            _ = try await client.getModes(userAuthToken: "U-TOKEN", stationId: "123")
            XCTFail("expected unauthorized")
        } catch let error as StationModesError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testOtherStatusSurfaces() async {
        let (client, _, _) = makeClient([status(500)])
        do {
            _ = try await client.getModes(userAuthToken: "U-TOKEN", stationId: "123")
            XCTFail("expected httpStatus(500)")
        } catch let error as StationModesError {
            XCTAssertEqual(error, .httpStatus(500))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSetModeServerKeptOldModeFails() async {
        // 200 reply but currentModeId did not move to the requested mode.
        let (client, _, _) = makeClient([ok(Self.modesReply)])
        do {
            _ = try await client.setMode(userAuthToken: "U-TOKEN", stationId: "123", modeId: 3, previousModeId: nil)
            XCTFail("expected modeNotOffered")
        } catch let error as StationModesError {
            XCTAssertEqual(error, .modeNotOffered)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSetModeWithoutCurrentModeIdSucceeds() async throws {
        let (client, _, _) = makeClient([ok(#"{"availableModes":[{"modeId":3,"modeName":"Deep Cuts","isModeAvailable":true}]}"#)])
        let modes = try await client.setMode(userAuthToken: "U-TOKEN", stationId: "123", modeId: 3, previousModeId: nil)
        XCTAssertEqual(modes.mode(id: 3)?.name, "Deep Cuts")
    }
}

// MARK: - SessionManager facade tests

final class StationModesSessionTests: XCTestCase {

    private static let clock: @Sendable () -> Date = {
        Date(timeIntervalSince1970: 1_000_000_000)
    }

    /// Encrypted syncTime fixture (decryptKey) — plaintext
    /// "PNDS1760000000PADPAD!!", same vector as SessionManagerTests.
    private static let syncTimeMain =
        "ac7b93e6a3c44c45258042bca01c9f6f40befffb546dee73"

    private static let station = Station(
        id: "123",
        token: "S123",
        name: "Test Station",
        isShared: false,
        isQuickMix: false
    )

    private static let modesReply = """
    {"currentModeId":1,"availableModes":[
      {"modeId":1,"modeName":"My Mix","isModeAvailable":true,
       "isPremiumOnly":false},
      {"modeId":5,"modeName":"Artist Only","isModeAvailable":true,
       "isPremiumOnly":true}]}
    """

    private func ok(_ resultObjectJSON: String) -> Result<Data, Error> {
        .success(Data("{\"stat\":\"ok\",\"result\":\(resultObjectJSON)}".utf8))
    }

    private func partnerOK() -> Result<Data, Error> {
        ok(#"{"partnerId":"77","partnerAuthToken":"P-TOKEN","syncTime":"\#(Self.syncTimeMain)"}"#)
    }

    private func userOK(isSubscriber: Bool) -> Result<Data, Error> {
        ok("{\"userId\":\"u-1\",\"userAuthToken\":\"U-TOKEN\",\"isSubscriber\":\(isSubscriber)}")
    }

    private func makeManager(
        legacyResponses: [Result<Data, Error>],
        modesResponses: [Result<ModesHTTPResponse, Error>]
    ) -> (SessionManager, MockModesTransport, MockCSRF) {
        let legacy = MockTransport(responses: legacyResponses)
        let modesTransport = MockModesTransport(responses: modesResponses)
        let csrf = MockCSRF()
        let manager = SessionManager(
            client: LegacyPandoraClient(transport: legacy),
            modes: PandoraModesClient(transport: modesTransport, csrf: csrf),
            store: nil,
            now: Self.clock
        )
        return (manager, modesTransport, csrf)
    }

    private func login(_ manager: SessionManager) async throws {
        _ = try await manager.login(username: "me@example.com", password: "hunter2")
    }

    func testGetModesWithoutSessionFails() async {
        let (manager, _, _) = makeManager(legacyResponses: [], modesResponses: [])
        do {
            _ = try await manager.getStationModes(for: Self.station)
            XCTFail("expected notAuthenticated")
        } catch let error as SessionManagerError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testGetModesPassesSessionAndStation() async throws {
        let (manager, modesTransport, _) = makeManager(
            legacyResponses: [partnerOK(), userOK(isSubscriber: false)],
            modesResponses: [.success(ModesHTTPResponse(statusCode: 200, body: Data(Self.modesReply.utf8)))]
        )
        try await login(manager)

        let modes = try await manager.getStationModes(for: Self.station)
        XCTAssertEqual(modes.modes.count, 2)
        XCTAssertEqual(modes.currentModeID, 1)

        let call = try XCTUnwrap(modesTransport.calls.first)
        XCTAssertEqual(call.headers["X-AuthToken"], "U-TOKEN")
        XCTAssertEqual(String(decoding: call.body, as: UTF8.self), "{\"stationId\":\"123\"}")
    }

    func testPremiumModeOnFreeAccountIsRefusedWithoutNetwork() async throws {
        let (manager, modesTransport, _) = makeManager(
            legacyResponses: [partnerOK(), userOK(isSubscriber: false)],
            modesResponses: []
        )
        try await login(manager)

        let artistOnly = StationMode(id: 5, name: "Artist Only", isAvailable: true, isPremiumOnly: true)
        do {
            _ = try await manager.setStationMode(artistOnly, for: Self.station)
            XCTFail("expected notEntitled")
        } catch let error as StationModesError {
            XCTAssertEqual(error, .notEntitled)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        // The gate must trip before any HTTP traffic.
        let calls = modesTransport.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testFreeAccountCanSetOrdinaryMode() async throws {
        let (manager, _, _) = makeManager(
            legacyResponses: [partnerOK(), userOK(isSubscriber: false)],
            modesResponses: [.success(ModesHTTPResponse(statusCode: 200, body: Data(Self.modesReply.utf8)))]
        )
        try await login(manager)

        let deepCuts = StationMode(id: 1, name: "My Mix", isAvailable: true, isPremiumOnly: false)
        let modes = try await manager.setStationMode(deepCuts, for: Self.station, previousModeID: nil)
        XCTAssertEqual(modes.currentModeID, 1)
    }

    func testUnofferedModeIsRefusedWithoutNetwork() async throws {
        let (manager, modesTransport, _) = makeManager(
            legacyResponses: [partnerOK(), userOK(isSubscriber: true)],
            modesResponses: []
        )
        try await login(manager)

        let unoffered = StationMode(id: 9, name: "Elsewhere", isAvailable: false)
        do {
            _ = try await manager.setStationMode(unoffered, for: Self.station)
            XCTFail("expected modeNotOffered")
        } catch let error as StationModesError {
            XCTAssertEqual(error, .modeNotOffered)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let calls = modesTransport.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testUnauthorizedTriggersReLoginThenRetry() async throws {
        // First getModes: 401 → csrf refresh → 401 again → the client gives
        // up with .unauthorized → SessionManager re-logins (legacy partner +
        // user fixtures 3 and 4) → retries getModes → 200.
        let (manager, modesTransport, csrf) = makeManager(
            legacyResponses: [
                partnerOK(), userOK(isSubscriber: false),
                partnerOK(), userOK(isSubscriber: false)
            ],
            modesResponses: [
                .success(ModesHTTPResponse(statusCode: 401, body: Data())),
                .success(ModesHTTPResponse(statusCode: 401, body: Data())),
                .success(ModesHTTPResponse(statusCode: 200, body: Data(Self.modesReply.utf8)))
            ]
        )
        try await login(manager)

        let modes = try await manager.getStationModes(for: Self.station)
        XCTAssertEqual(modes.currentModeID, 1)

        let calls = modesTransport.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(csrf.refreshCount, 1)
        // The retried call carries the re-issued session token.
        XCTAssertEqual(calls.first?.headers["X-AuthToken"], "U-TOKEN")
        XCTAssertEqual(calls.last?.headers["X-AuthToken"], "U-TOKEN")
    }
}
