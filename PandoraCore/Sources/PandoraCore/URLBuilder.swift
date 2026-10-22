//
//  URLBuilder.swift
//  PandoraCore
//
//  Builds the legacy JSON API (v5) request URL and body, mirroring
//  `pithos.pandora.Pandora.json_call` exactly:
//
//  - Query string order: partner_id, user_id, auth_token, method.
//    `auth_token` prefers the user token, falling back to the partner token.
//  - Body: caller's parameters, plus `syncTime` when a time offset is known,
//    plus `userAuthToken`/`partnerAuthToken` (user preferred), matching
//    pithos' if/elif chain.
//  - Body encryption is opt-in per call (`encrypt:`), because
//    `auth.partnerLogin` is sent as plain JSON in pithos while
//    `auth.userLogin` and everything after are Blowfish-ECB hex.
//
//  No networking here — this only assembles bytes. URLSession lives above.
//

import Foundation

public enum URLBuilderError: Error, Equatable, Sendable {
    case urlConstructionFailed
}

public struct URLBuilder: Sendable {

    /// Session-derived fields threaded into later requests, updated by
    /// `SessionManager` as auth progresses.
    public struct Context: Sendable, Equatable {
        public var partnerId: String?
        public var partnerAuthToken: String?
        public var userId: String?
        public var userAuthToken: String?
        /// `pandora_time - local_time` at partner login; nil until known.
        public var timeOffset: TimeInterval?

        public init(
            partnerId: String? = nil,
            partnerAuthToken: String? = nil,
            userId: String? = nil,
            userAuthToken: String? = nil,
            timeOffset: TimeInterval? = nil
        ) {
            self.partnerId = partnerId
            self.partnerAuthToken = partnerAuthToken
            self.userId = userId
            self.userAuthToken = userAuthToken
            self.timeOffset = timeOffset
        }
    }

    public let baseURL: URL
    public var context: Context

    public init(baseURL: URL = PandoraAPI.baseURL, context: Context = Context()) {
        self.baseURL = baseURL
        self.context = context
    }

    // MARK: - URL

    /// Query-string URL for `method`, in pithos' parameter order.
    public func endpointURL(method: String) throws -> URL {
        var items: [(String, String)] = []
        if let partnerId = context.partnerId {
            items.append(("partner_id", partnerId))
        }
        if let userId = context.userId {
            items.append(("user_id", userId))
        }
        if let token = context.userAuthToken ?? context.partnerAuthToken {
            items.append(("auth_token", token))
        }
        items.append(("method", method))

        var components: URLComponents
        guard let parsed = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLBuilderError.urlConstructionFailed
        }
        components = parsed
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else {
            throw URLBuilderError.urlConstructionFailed
        }
        return url
    }

    // MARK: - Body

    /// Assembles the request body for `method`: `parameters` plus session
    /// fields (see file header), encoded as deterministic JSON — and, when
    /// `encrypt` is true, Blowfish-ECB hex using `PandoraAPI.encryptKey`.
    ///
    /// - Parameters:
    ///   - parameters: caller-supplied fields for the method.
    ///   - encrypt: false for `auth.partnerLogin` (plain JSON, per pithos);
    ///     true for `auth.userLogin` and everything else.
    ///   - now: injection point for deterministic `syncTime` in tests.
    public func requestBody(
        parameters: [String: JSONValue],
        encrypt: Bool,
        now: Date = Date()
    ) throws -> Data {
        var merged = parameters
        if let offset = context.timeOffset {
            merged["syncTime"] = .int(Int(now.timeIntervalSince1970 + offset))
        }
        if let userToken = context.userAuthToken {
            merged["userAuthToken"] = .string(userToken)
        } else if let partnerToken = context.partnerAuthToken {
            merged["partnerAuthToken"] = .string(partnerToken)
        }

        let json = JSONValue.encoded(merged)
        return encrypt ? Data(try PandoraCrypto.encryptRequestBody(json).utf8) : json
    }
}
