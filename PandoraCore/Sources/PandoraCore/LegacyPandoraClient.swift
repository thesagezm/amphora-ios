//
//  LegacyPandoraClient.swift
//  PandoraCore
//
//  JSON API v5 transport: assembles URL + body with `URLBuilder`, performs
//  the POST via an injected `HTTPTransport`, unwraps the response envelope.
//  Session lifecycle (partner → user → re-auth) lives in `SessionManager`.
//
//  Derived from `pithos.pandora.Pandora.json_call`. No UI, no AVFoundation.
//

import Foundation

/// POSTs a request body and returns the raw response body.
/// Injected so tests never touch the network.
public protocol HTTPTransport: Sendable {
    func post(url: URL, body: Data, contentType: String) async throws -> Data
}

/// `URLSession`-backed transport. `session.send` already suspends, so
/// nothing blocks a thread while waiting on the socket.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "Amphora") {
        self.session = session
        self.userAgent = userAgent
    }

    public func post(url: URL, body: Data, contentType: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PandoraTransportError(reason: "non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw PandoraTransportError(reason: "HTTP \(http.statusCode)")
            }
            return data
        } catch let error as PandoraTransportError {
            throw error
        } catch {
            // No `.localizedDescription` re-inspection: message carries no
            // URL/token material either way, and the detail is already
            // sanitized (transport layer never sees response bodies here).
            throw PandoraTransportError(reason: "network failure")
        }
    }
}

public final class LegacyPandoraClient: PandoraAPIClient, @unchecked Sendable {
    private let transport: HTTPTransport
    private var builder: URLBuilder   // var: context mutates after SessionManager auth steps
    private let stateLock = NSLock()

    public init(transport: HTTPTransport = URLSessionTransport(), builder: URLBuilder = URLBuilder()) {
        self.transport = transport
        self.builder = builder
    }

    /// Current session fields (partner id, tokens, time offset). Readable by
    /// `SessionManager`; writes happen only through the setters below.
    public var context: URLBuilder.Context {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return builder.context
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            builder.context = newValue
        }
    }

    /// - Parameters:
    ///   - method: e.g. `auth.partnerLogin`.
    ///   - parameters: JSON-encodable fields (nested values pass through).
    ///   - encrypt: Blowfish-ECB body encryption; see `URLBuilder` — false
    ///     only for `auth.partnerLogin`.
    ///   - now: clock injection for deterministic `syncTime` in tests.
    public func request(
        method: String,
        parameters: [String: JSONValue] = [:],
        encrypt: Bool = true,
        now: Date = Date()
    ) async throws -> [String: AnyJSON] {
        let url = try builder.endpointURL(method: method)
        let body = try builder.requestBody(
            parameters: parameters,
            encrypt: encrypt,
            now: now
        )

        // pithos sends text/plain for the encrypted-body form.
        let contentType = encrypt ? "text/plain" : "application/json"
        let payload = try await transport.post(url: url, body: body, contentType: contentType)
        return try ResponseEnvelope.result(from: payload)
    }

    // MARK: - PandoraAPIClient

    public func request(
        method: String,
        parameters: [String: JSONValue]
    ) async throws -> [String: AnyJSON] {
        try await request(method: method, parameters: parameters, encrypt: true)
    }
}

// MARK: - Typed field helpers (fixture-decodable, no Any casts at call sites)

public extension Dictionary where Key == String, Value == AnyJSON {
    func string(_ key: String) throws -> String {
        guard let value = self[key]?.stringValue else {
            throw PandoraMalformedResponseError(detail: "missing string field \(key)")
        }
        return value
    }

    func int(_ key: String) throws -> Int {
        guard let value = self[key]?.intValue else {
            throw PandoraMalformedResponseError(detail: "missing int field \(key)")
        }
        return value
    }

    func bool(_ key: String) throws -> Bool {
        guard let value = self[key]?.boolValue else {
            throw PandoraMalformedResponseError(detail: "missing bool field \(key)")
        }
        return value
    }
}
