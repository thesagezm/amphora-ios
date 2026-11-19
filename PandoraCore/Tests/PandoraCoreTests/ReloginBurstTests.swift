//
//  ReloginBurstTests.swift
//  PandoraCoreTests
//
//  Session expiry on a slow link. Several requests that expire together
//  — exactly what a slow network produces, with requests already in
//  flight when the session dies — must cost ONE re-login, not one per
//  request: the actor would otherwise serialize N full partner+user
//  logins back to back, minutes of waiting on a bad link. These tests
//  pin the burst contract: concurrent 1001s share the in-flight login,
//  a straggler inside the freshness window replays without a login, a
//  straggler after it may login again, a failed re-login propagates as
//  the real transport error and leaves the stale session retryable, a
//  call arriving mid-re-login waits instead of sending, and a sign-out
//  cancels the login still running so it cannot re-persist the session.
//
//  The transport answers per method, Pandora-style — the stale token is
//  refused (1001) until a fresh userLogin has landed, the auth methods
//  answer as themselves — so concurrent callers may interleave however
//  the actor schedules them and the assertions stay true regardless.
//

import XCTest
@testable import PandoraCore

final class ReloginBurstTests: XCTestCase {

    /// Fixed local clock (2001-09-09) — the freshness window never
    /// expires under it, since every read returns the same instant.
    private static let clock: @Sendable () -> Date = {
        Date(timeIntervalSince1970: 1_000_000_000)
    }

    /// A clock the test can advance — for the window-expiry scenario.
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 1_000_000_000)

        var date: Date {
            lock.lock()
            defer { lock.unlock() }
            return current
        }

        func advance(by interval: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            current = current.addingTimeInterval(interval)
        }
    }

    // MARK: - Fixtures

    private func makeManager(
        transport: SlowLinkTransport,
        clock: @escaping @Sendable () -> Date = ReloginBurstTests.clock
    ) -> SessionManager {
        SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: InMemorySessionStore(record: expiredRecord()),
            now: clock
        )
    }

    private func expiredRecord() -> SessionRecord {
        SessionRecord(
            credentials: Credentials(username: "me@example.com", password: "hunter2"),
            tokens: SessionTokens(
                partnerId: "77",
                partnerAuthToken: "P-TOKEN",
                userId: "u-1",
                userAuthToken: "U-EXPIRED",
                timeOffset: 760_000_000
            ),
            isSubscriber: false
        )
    }

    // MARK: - The burst

    func testConcurrentExpiredCallsShareOneRelogin() async throws {
        let transport = SlowLinkTransport()
        let subject = makeManager(transport: transport)
        await subject.restore()

        async let first: StationList = subject.getStationList()
        async let second: StationList = subject.getStationList()
        _ = try await (first, second)

        XCTAssertEqual(transport.attempts("auth.partnerLogin"), 1)
        XCTAssertEqual(transport.attempts("auth.userLogin"), 1)
    }

    func testAStragglerInsideTheFreshnessWindowReplaysWithoutALogin() async throws {
        // Attempt 3 is the straggler: the second call's first request,
        // already on the wire carrying the stale token when the session
        // died — refused once, and its replay served by the freshness
        // window (the fixed clock never expires it).
        let transport = SlowLinkTransport(refusedStationListAttempts: [3])
        let subject = makeManager(transport: transport)
        await subject.restore()

        _ = try await subject.getStationList()
        _ = try await subject.getStationList()
        _ = try await subject.getStationList()

        XCTAssertEqual(transport.attempts("auth.partnerLogin"), 1,
                       "a straggler inside the window must not trigger a second login")
        XCTAssertEqual(transport.attempts("auth.userLogin"), 1)
    }

    func testAStragglerAfterTheFreshnessWindowLoginsAgain() async throws {
        let clock = TestClock()
        let transport = SlowLinkTransport(refusedStationListAttempts: [3])
        let subject = makeManager(transport: transport) { clock.date }
        await subject.restore()

        _ = try await subject.getStationList()
        // Past the window: the landed re-login no longer serves a
        // straggler, so the next expiry costs a full login again.
        clock.advance(by: SessionManager.reloginFreshnessWindow + 1)
        _ = try await subject.getStationList()

        XCTAssertEqual(transport.attempts("auth.partnerLogin"), 2)
        XCTAssertEqual(transport.attempts("auth.userLogin"), 2)
    }

    func testAFailedReloginPropagatesAndKeepsTheSessionRetryable() async throws {
        let transport = SlowLinkTransport(failingPartnerAttempts: 1)
        let subject = makeManager(transport: transport)
        await subject.restore()

        // The shared login's partner call dies (a lost link): the real
        // transport error surfaces — not a generic unauthenticated
        // state — and the stale session stays in place.
        do {
            _ = try await subject.getStationList()
            XCTFail("the failed re-login must propagate")
        } catch let error as PandoraTransportError {
            XCTAssertEqual(error.reason, "connection lost")
        }
        let stillHasSession = await subject.hasSession
        XCTAssertTrue(stillHasSession, "a failed re-login must not wipe the stale session")

        // The next call retries the login — the network recovered.
        _ = try await subject.getStationList()
        XCTAssertEqual(transport.attempts("auth.partnerLogin"), 2)
        XCTAssertEqual(transport.attempts("auth.userLogin"), 1)
    }

    // MARK: - The slow link

    func testACallArrivingMidReloginWaitsInsteadOfSending() async throws {
        // The partner-login reply is held until the test releases it —
        // the stand-in for a login that takes tens of seconds.
        let transport = SlowLinkTransport(holdFirstPartnerLogin: true)
        let subject = makeManager(transport: transport)
        await subject.restore()

        async let first: StationList = subject.getStationList()
        // The login is now running, mid-network. A second call arrives:
        // it must wait for the shared login, not send mid-flight (the
        // attempt stamps the request context as it goes) and not fail.
        try await transport.waitForPartnerLogin()
        async let second: StationList = subject.getStationList()
        transport.release()

        _ = try await (first, second)

        XCTAssertEqual(transport.attempts("auth.partnerLogin"), 1)
        XCTAssertEqual(transport.attempts("auth.userLogin"), 1)
        XCTAssertEqual(transport.attempts("user.getStationList"), 3,
                       "the first call's 1001 + two replays; the second call never sent during the login")
    }

    func testSignOutCancelsAnInFlightRelogin() async throws {
        let transport = SlowLinkTransport(holdFirstPartnerLogin: true)
        let store = InMemorySessionStore(record: expiredRecord())
        let subject = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: store,
            now: Self.clock
        )
        await subject.restore()

        async let call: StationList = subject.getStationList()
        try await transport.waitForPartnerLogin()

        // The user gives up mid-login. The sign-out cancels the shared
        // login: it must not land afterwards and re-persist the session.
        await subject.signOut()
        transport.release()

        do {
            _ = try await call
            XCTFail("the cancelled re-login must not complete the call")
        } catch {
            // The cancellation surfaces as an error — any of them.
        }

        XCTAssertEqual(transport.attempts("auth.userLogin"), 0,
                       "the cancelled login must not proceed past its next request")
        XCTAssertNil(store.load(), "a sign-out must not be undone by the login it cancelled")
        let hasSession = await subject.hasSession
        XCTAssertFalse(hasSession)
    }

    // MARK: - The transport

    /// Answers per method, Pandora-style: the stale token is refused
    /// (1001) until a fresh `userLogin` has landed; the auth methods
    /// answer as themselves. Each landed login serves a limited number
    /// of station-list calls before the session "expires" again, so a
    /// test can walk the manager through several expiry cycles. The
    /// first partner login can be held — the slow link.
    private final class SlowLinkTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []
        private var partnerAttempts = 0
        private var freshLoginSeen = false
        private let failingPartnerAttempts: Int
        private let holdFirstPartnerLogin: Bool
        /// Station-list call attempts (initial calls and replays alike)
        /// the transport refuses outright — the stand-in for requests
        /// that were already on the wire carrying the stale token when
        /// the session died.
        private let refusedStationListAttempts: Set<Int>
        private var stationListAttempts = 0
        private var released = false
        private var continuation: CheckedContinuation<Data, Error>?

        init(
            failingPartnerAttempts: Int = 0,
            holdFirstPartnerLogin: Bool = false,
            refusedStationListAttempts: Set<Int> = []
        ) {
            self.failingPartnerAttempts = failingPartnerAttempts
            self.holdFirstPartnerLogin = holdFirstPartnerLogin
            self.refusedStationListAttempts = refusedStationListAttempts
        }

        func attempts(_ method: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return recorded.filter { $0 == method }.count
        }

        func release() {
            lock.lock()
            released = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: partnerReplyData)
        }

        func waitForPartnerLogin() async throws {
            for _ in 0..<500 {
                if attempts("auth.partnerLogin") > 0 { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("timed out waiting for the partner login to be sent")
        }

        private enum PartnerOutcome {
            case fail, gate, reply
        }

        func post(url: URL, body: Data, contentType: String) async throws -> Data {
            // The stand-in for URLSession's own cancellation handling.
            if Task.isCancelled { throw CancellationError() }
            let method = Self.method(of: url)
            if method == "auth.partnerLogin" {
                switch markPartnerAttempt() {
                case .fail:
                    throw PandoraTransportError(reason: "connection lost")
                case .gate:
                    return try await withCheckedThrowingContinuation { gate in
                        lock.lock()
                        if released {
                            lock.unlock()
                            gate.resume(returning: partnerReplyData)
                        } else {
                            continuation = gate
                            lock.unlock()
                        }
                    }
                case .reply:
                    return partnerReplyData
                }
            }
            return try respond(method)
        }

        /// Records the partner attempt and decides its reply.
        private func markPartnerAttempt() -> PartnerOutcome {
            lock.lock()
            defer { lock.unlock() }
            recorded.append("auth.partnerLogin")
            partnerAttempts += 1
            if partnerAttempts <= failingPartnerAttempts {
                return .fail
            }
            if holdFirstPartnerLogin && partnerAttempts == 1 && !released {
                return .gate
            }
            return .reply
        }

        private func respond(_ method: String) throws -> Data {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(method)
            switch method {
            case "auth.userLogin":
                freshLoginSeen = true
                return userOKData
            case "user.getStationList":
                stationListAttempts += 1
                if refusedStationListAttempts.contains(stationListAttempts) {
                    return fail1001Data
                }
                return freshLoginSeen ? stationsOKData : fail1001Data
            default:
                throw PandoraTransportError(reason: "unexpected method \(method)")
            }
        }

        // MARK: the fixture data

        private let partnerReplyData = Data(
            "{\"stat\":\"ok\",\"result\":{\"partnerId\":\"77\",\"partnerAuthToken\":\"P-TOKEN\",\"syncTime\":\"ac7b93e6a3c44c45258042bca01c9f6f40befffb546dee73\"}}".utf8
        )
        private let userOKData = Data(
            "{\"stat\":\"ok\",\"result\":{\"userId\":\"u-1\",\"userAuthToken\":\"U-FRESH\",\"isSubscriber\":true}}".utf8
        )
        private let stationsOKData = Data(
            "{\"stat\":\"ok\",\"result\":{\"stations\":[]}}".utf8
        )
        private let fail1001Data = JSONValue.encoded([
            "stat": .string("fail"),
            "code": .int(1001),
            "message": .string("Invalid auth token")
        ])

        private static func method(of url: URL) -> String {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "method" }?
                .value ?? url.absoluteString
        }
    }
}
