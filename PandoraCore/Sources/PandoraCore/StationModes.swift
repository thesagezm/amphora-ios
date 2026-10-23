//
//  StationModes.swift
//  PandoraCore
//
//  Pandora "listening modes" — the station-tuning feature ("My Mix",
//  "Deep Cuts", "Crowd Faves", "Discovery", …) that Pandora's own apps
//  expose as "Tune your station".
//
//  These live on the *modern* web API, not the legacy JSON v5 host, and
//  the request bodies are plain JSON (no Blowfish):
//
//    POST https://www.pandora.com/api/v1/interactiveradio/getAvailableModesSimple
//         {"stationId": "<stationId>"}
//    POST https://www.pandora.com/api/v1/interactiveradio/setAndGetAvailableModes
//         {"stationId": "<stationId>", "modeId": <int>, "previousModeId": <int>}
//
//  Auth is the header `X-AuthToken: <userAuthToken>` — the *same* token the
//  legacy `auth.userLogin` returns. Verified against two independent
//  clients:
//
//  - pandoCast (`lennyxc/PandoCast`, `PandoCast.Core/PandoraRestApi.cs`)
//    logs in through the legacy v5 flow (`auth.partnerLogin` +
//    Blowfish `auth.userLogin`, android-generic device) and then drives
//    `v1/interactiveradio/*` — plus `v1/playlist/getFragment` — with that
//    `UserAuthToken`, using the numeric station id as `stationId`.
//  - Panedora (`MitchellBrovarnik/Panedora`, `pandora-api.js`) calls the
//    same two endpoints from a web session.
//
//  CSRF: the endpoints require `X-CsrfToken`. pandoCast bootstraps it by
//  requesting `https://www.pandora.com/` and reading the `csrftoken`
//  cookie (HEAD, then GET), retrying once with a fresh cookie on 401/403.
//
//  Free accounts: every mode the server marks available is usable —
//  "Deep Cuts" and friends are free features. Modes flagged
//  `isPremiumOnly` (e.g. id 5, "Artist Only") need a paid subscription;
//  both references gate them client-side (`isPremiumOnly === true`,
//  pandoCast adds `modeId 5` as a fallback), which is what
//  `StationMode.isSelectable(isSubscriber:)` implements.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation
#if canImport(FoundationNetworking)
// Linux (swift-corelibs-foundation): URLSession/HTTPCookie live here.
import FoundationNetworking
#endif

// MARK: - Models

/// One listening mode from `availableModes`.
public struct StationMode: Sendable, Equatable, Identifiable {
    /// `modeId` — the value `setAndGetAvailableModes` accepts. 5 is
    /// "Artist Only" (premium) when the server omits the flag.
    public let id: Int
    /// `modeName`, e.g. "My Mix" / "Deep Cuts".
    public let name: String
    /// `modeDescription` — the server's one-line blurb for the mode.
    public let modeDescription: String
    /// `isModeAvailable` — whether Pandora offers this mode for the station.
    public let isAvailable: Bool
    /// `isPremiumOnly` — requires a paid subscription.
    public let isPremiumOnly: Bool

    public init(
        id: Int,
        name: String,
        modeDescription: String = "",
        isAvailable: Bool = false,
        isPremiumOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.modeDescription = modeDescription
        self.isAvailable = isAvailable
        self.isPremiumOnly = isPremiumOnly
    }

    /// Whether the mode may be requested under this subscription
    /// (panedora: `isModeAvailable && (!premiumOnly || premiumAccess)`).
    public func isSelectable(isSubscriber: Bool) -> Bool {
        isAvailable && (!isPremiumOnly || isSubscriber)
    }
}

/// The `interactiveradio` reply: the station's offered modes plus the
/// currently selected one. `interactiveRadioAvailable` is `false` for
/// stations Pandora does not tune (e.g. QuickMix) — both references hide
/// their picker in that case.
public struct StationModes: Sendable, Equatable {
    public let isInteractiveRadioAvailable: Bool
    public let currentModeID: Int?
    public let modes: [StationMode]

    public init(
        isInteractiveRadioAvailable: Bool = true,
        currentModeID: Int? = nil,
        modes: [StationMode] = []
    ) {
        self.isInteractiveRadioAvailable = isInteractiveRadioAvailable
        self.currentModeID = currentModeID
        self.modes = modes
    }

    public func mode(id: Int) -> StationMode? {
        modes.first { $0.id == id }
    }

    public var currentMode: StationMode? {
        currentModeID.flatMap { mode(id: $0) }
    }

    /// Decodes the raw response body of either `interactiveradio` endpoint.
    /// `modeId`/`currentModeId` arrive as JSON number or digit string
    /// (panedora `modeId()` accepts both); entries without a usable id or
    /// name are dropped, duplicates by id keep the first (panedora `seen`).
    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(AnyJSON.self, from: data)
        guard let object = decoded.objectValue else {
            throw PandoraMalformedResponseError(detail: "station modes body was not a JSON object")
        }
        // panedora treats a present `errorCode` (or `stat: "fail"`) as a
        // failed reply even over HTTP 200.
        if let code = object["errorCode"], code != .null {
            throw PandoraMalformedResponseError(detail: "station modes request rejected (\(code))")
        }
        if object["stat"]?.stringValue == "fail" {
            throw PandoraMalformedResponseError(detail: "station modes request rejected (stat fail)")
        }
        try self.init(result: object)
    }

    /// Decodes from an already-parsed JSON object (also the test seam).
    public init(result: [String: AnyJSON]) throws {
        let interactiveRadioAvailable = result["interactiveRadioAvailable"]?.boolValue ?? true
        // panedora: an absent `availableModes` array is only valid when the
        // server said interactive radio is unavailable.
        guard let entries = result["availableModes"]?.arrayValue ?? (interactiveRadioAvailable ? nil : []) else {
            throw PandoraMalformedResponseError(detail: "station modes missing availableModes array")
        }

        var seen = Set<Int>()
        var parsed: [StationMode] = []
        for entry in entries {
            guard let object = entry.objectValue else { continue }
            guard let id = Self.modeID(object["modeId"]) else { continue }
            guard let name = object["modeName"]?.stringValue, !name.isEmpty else { continue }
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            parsed.append(
                StationMode(
                    id: id,
                    name: name,
                    modeDescription: object["modeDescription"]?.stringValue ?? "",
                    isAvailable: object["isModeAvailable"]?.boolValue ?? false,
                    isPremiumOnly: object["isPremiumOnly"]?.boolValue ?? false
                )
            )
        }
        self.init(
            isInteractiveRadioAvailable: interactiveRadioAvailable,
            currentModeID: Self.modeID(result["currentModeId"]),
            modes: parsed
        )
    }

    /// `modeId`/`currentModeId` are JSON number or digit string.
    private static func modeID(_ value: AnyJSON?) -> Int? {
        value?.intValue ?? value?.stringValue.flatMap(Int.init)
    }
}

// MARK: - Errors

public enum StationModesError: Error, Equatable, Sendable {
    /// 401/403 even after a fresh csrf token — the auth token was rejected;
    /// the caller should re-authenticate and retry once.
    case unauthorized
    /// The requested mode needs a paid subscription (free account).
    case notEntitled
    /// The server answered 200 but kept the old mode (panedora's
    /// post-set `currentModeId` check), or the mode is not offered.
    case modeNotOffered
    /// Any other non-2xx status.
    case httpStatus(Int)
}

// MARK: - Transport

/// A POST and its raw reply, *including* non-2xx statuses — the caller
/// distinguishes 401/403 (csrf refresh + retry) from other failures.
public struct ModesHTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol ModesTransport: Sendable {
    func post(url: URL, body: Data, headers: [String: String]) async throws -> ModesHTTPResponse
}

/// `URLSession`-backed transport. `URLSession` is thread-safe; Linux's
/// corelibs type just lacks the `Sendable` conformance, so it is boxed.
public struct URLSessionModesTransport: ModesTransport {
    private final class SessionBox: @unchecked Sendable {
        let session: URLSession
        init(_ session: URLSession) { self.session = session }
    }

    private let box: SessionBox

    public init(session: URLSession = .shared) {
        self.box = SessionBox(session)
    }

    public func post(url: URL, body: Data, headers: [String: String]) async throws -> ModesHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body
        do {
            let (data, response) = try await box.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PandoraTransportError(reason: "non-HTTP response")
            }
            return ModesHTTPResponse(statusCode: http.statusCode, body: data)
        } catch let error as PandoraTransportError {
            throw error
        } catch {
            throw PandoraTransportError(reason: "network failure")
        }
    }
}

// MARK: - CSRF

/// Supplies the `X-CsrfToken` header value. `refresh()` must return a
/// *new* token — the client calls it once after a 401/403 and retries.
public protocol CSRFTokenProviding: Sendable {
    func token() async throws -> String
    func refresh() async throws -> String
}

/// Bootstraps Pandora's `csrftoken` cookie the way pandoCast does
/// (`EnsureCsrfTokenAsync`): request `https://www.pandora.com/` — HEAD,
/// then GET — and read the `csrftoken` cookie the response set.
/// `URLSession` stores Set-Cookie replies in `HTTPCookieStorage.shared`.
public final class CookieCSRFProvider: CSRFTokenProviding, @unchecked Sendable {
    public static let webRootURL = URL(string: "https://www.pandora.com/")!

    private final class SessionBox: @unchecked Sendable {
        let session: URLSession
        init(_ session: URLSession) { self.session = session }
    }

    private let box: SessionBox
    private let lock = NSLock()
    private var cached: String?

    public init(session: URLSession = .shared) {
        self.box = SessionBox(session)
    }

    public func token() async throws -> String {
        if let cached = read() { return cached }
        // A cookie from an earlier run may still be valid — try storage
        // before the network.
        if let existing = Self.csrfCookie()?.value {
            store(existing)
            return existing
        }
        return try await bootstrap()
    }

    public func refresh() async throws -> String {
        clear()
        return try await bootstrap()
    }

    private func bootstrap() async throws -> String {
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: Self.webRootURL)
            request.httpMethod = method
            request.setValue("Amphora", forHTTPHeaderField: "User-Agent")
            if let (_, response) = try? await box.session.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let value = Self.csrfCookie()?.value {
                store(value)
                return value
            }
        }
        throw PandoraTransportError(reason: "Pandora did not provide a csrftoken cookie")
    }

    /// The `csrftoken` cookie for the web root — server sets it on
    /// `.pandora.com` (host-only `www.pandora.com` also accepted).
    private static func csrfCookie() -> HTTPCookie? {
        let host = webRootURL.host ?? "www.pandora.com"
        return HTTPCookieStorage.shared.cookies?.first { cookie in
            cookie.name == "csrftoken"
                && (cookie.domain == host
                    || cookie.domain == ".pandora.com"
                    || cookie.domain.hasSuffix(".pandora.com"))
        }
    }

    // NSLock.lock/unlock are noasync — touch state only in sync helpers.
    private func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    private func store(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        cached = value
    }

    private func clear() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }
}

// MARK: - Client

/// The `interactiveradio` client. Stateless and `Sendable`; the session's
/// user token is passed per call so re-auth stays in `SessionManager`.
public struct PandoraModesClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://www.pandora.com/api/")!
    public static let getModesEndpoint = "v1/interactiveradio/getAvailableModesSimple"
    public static let setModeEndpoint = "v1/interactiveradio/setAndGetAvailableModes"

    private let transport: any ModesTransport
    private let csrf: any CSRFTokenProviding
    /// The endpoints sit behind Pandora's web player, so the client
    /// identifies itself browser-like (pandoCast sends a Chrome UA).
    private let userAgent: String

    public init(
        transport: any ModesTransport = URLSessionModesTransport(),
        csrf: any CSRFTokenProviding = CookieCSRFProvider(),
        userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 Amphora"
    ) {
        self.transport = transport
        self.csrf = csrf
        self.userAgent = userAgent
    }

    /// The station's offered modes (pandoCast
    /// `GetAvailableStationModesAsync` — payload `{"stationId": …}`).
    public func getModes(userAuthToken: String, stationId: String) async throws -> StationModes {
        let body = try await post(
            endpoint: Self.getModesEndpoint,
            parameters: ["stationId": .string(stationId)],
            userAuthToken: userAuthToken
        )
        return try StationModes(data: body)
    }

    /// Select a mode (pandoCast `SetStationModeAsync` —
    /// `{"stationId": …, "modeId": …, "previousModeId": …}`; panedora omits
    /// `previousModeId`, so it is optional here). Fails with
    /// `.modeNotOffered` when the reply's `currentModeId` did not move to
    /// the requested mode (pandora can answer 200 while keeping the old
    /// mode — panedora re-checks).
    public func setMode(
        userAuthToken: String,
        stationId: String,
        modeId: Int,
        previousModeId: Int?
    ) async throws -> StationModes {
        var parameters: [String: JSONValue] = [
            "stationId": .string(stationId),
            "modeId": .int(modeId)
        ]
        if let previousModeId {
            parameters["previousModeId"] = .int(previousModeId)
        }
        let body = try await post(
            endpoint: Self.setModeEndpoint,
            parameters: parameters,
            userAuthToken: userAuthToken
        )
        let modes = try StationModes(data: body)
        if let current = modes.currentModeID, current != modeId {
            throw StationModesError.modeNotOffered
        }
        return modes
    }

    private func post(
        endpoint: String,
        parameters: [String: JSONValue],
        userAuthToken: String
    ) async throws -> Data {
        let url = Self.defaultBaseURL.appendingPathComponent(endpoint)
        let body = JSONValue.encoded(parameters)
        let csrfToken = try await csrf.token()
        var response = try await send(url: url, body: body, userAuthToken: userAuthToken, csrfToken: csrfToken)
        if response.statusCode == 401 || response.statusCode == 403 {
            // pandoCast: re-bootstrap the csrf cookie, retry once.
            let fresh = try await csrf.refresh()
            response = try await send(url: url, body: body, userAuthToken: userAuthToken, csrfToken: fresh)
        }
        switch response.statusCode {
        case 200...299:
            return response.body
        case 401, 403:
            throw StationModesError.unauthorized
        default:
            throw StationModesError.httpStatus(response.statusCode)
        }
    }

    private func send(url: URL, body: Data, userAuthToken: String, csrfToken: String) async throws -> ModesHTTPResponse {
        try await transport.post(url: url, body: body, headers: [
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "X-AuthToken": userAuthToken,
            "X-CsrfToken": csrfToken,
            "Origin": "https://www.pandora.com",
            "Referer": "https://www.pandora.com/",
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": userAgent
        ])
    }
}
