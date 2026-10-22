//
//  Errors.swift
//  PandoraCore
//
//  Typed errors mapped from Pandora's fault codes. The code table and the
//  human-facing messages are transcribed from `pithos.pandora.ApiError`
//  (`pithos/pandora/pandora.py`), the reference implementation.
//
//  Never crash on an API error; everything the server can say lands here.
//

import Foundation

/// A fault returned in a `{"stat":"fail"}` response envelope.
public struct PandoraAPIError: Error, Sendable, Equatable, Codable {
    /// Pandora's numeric fault code (e.g. 1001 invalid auth token).
    public let code: Int
    /// The server's message string, verbatim.
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    // MARK: - Fault codes (pithos `ApiError`)

    public enum Code: Int, Sendable {
        case internalError = 0
        case maintenanceMode = 1
        case urlParamMissingMethod = 2
        case urlParamMissingAuthToken = 3
        case urlParamMissingPartnerId = 4
        case urlParamMissingUserId = 5
        case secureProtocolRequired = 6
        case certificateRequired = 7
        case parameterTypeMismatch = 8
        case parameterMissing = 9
        case parameterValueInvalid = 10
        case apiVersionNotSupported = 11
        case countryNotSupported = 12
        case insufficientConnectivity = 13
        case unknownMethodName = 14
        case wrongProtocol = 15

        case readOnlyMode = 1000
        case invalidAuthToken = 1001
        case invalidLogin = 1002
        case listenerNotAuthorized = 1003
        case userNotAuthorized = 1004
        case maxStationsReached = 1005
        case stationDoesNotExist = 1006
        case complimentaryPeriodAlreadyInUse = 1007
        case callNotAllowed = 1008
        case deviceNotFound = 1009
        case partnerNotAuthorized = 1010
        case invalidUsername = 1011
        case invalidPassword = 1012
        case usernameAlreadyExists = 1013
        case deviceAlreadyAssociatedToAccount = 1014
        case upgradeDeviceModelInvalid = 1015
        case explicitPinIncorrect = 1018
        case explicitPinMalformed = 1020
        case deviceModelInvalid = 1023
        case zipCodeInvalid = 1024
        case birthYearInvalid = 1025
        case birthYearTooYoung = 1026
        case deviceDisabled = 1034
        case dailyTrialLimitReached = 1035
        case invalidSponsor = 1036
        case userAlreadyUsedTrial = 1037
        case playlistExceeded = 1039
    }

    /// `true` when the session token must be refreshed (re-login + retry).
    public var isSessionExpired: Bool { code == Code.invalidAuthToken.rawValue }

    /// `true` when credentials were rejected — do not retry automatically.
    public var isInvalidCredentials: Bool {
        code == Code.invalidLogin.rawValue
            || code == Code.invalidUsername.rawValue
            || code == Code.invalidPassword.rawValue
    }

    /// Human-facing summary, preferring pithos' curated copy over the raw
    /// server message (pithos `ApiError.sub_message` / `.title`).
    public var localizedDescription: String {
        guard let known = Code(rawValue: code) else {
            return "Pandora error \(code): \(message)"
        }
        if let friendly = Self.friendlyMessages[known] {
            return friendly
        }
        return "Pandora error \(code) (\(Self.name(of: known))): \(message)"
    }

    private static func name(of code: Code) -> String {
        // .invalidAuthToken → "invalidAuthToken" is fine for logs; the
        // friendly table covers the user-visible cases.
        String(describing: code)
    }

    /// Curated copy lifted from pithos (`ApiError.sub_message`), adapted
    /// for an Amphora user (no Pithos-specific references).
    private static let friendlyMessages: [Code: String] = [
        .maintenanceMode: "Pandora is performing maintenance. Try again later.",
        .countryNotSupported: "Pandora is not available in your country.",
        .insufficientConnectivity: "Out of sync. Check your system's clock.",
        .readOnlyMode: "Pandora is in read-only mode. Try again later.",
        .invalidLogin: "Invalid username or password.",
        .listenerNotAuthorized: "A Pandora One subscription is required for this feature.",
        .maxStationsReached: "You have reached the maximum number of stations.",
        .partnerNotAuthorized: "Invalid Pandora partner keys — the client may need updating.",
        .deviceModelInvalid: "Invalid Pandora device model — the client may need updating.",
        .playlistExceeded: "Too many playlist requests. Try again later."
    ]
}

/// Transport-level failure (offline, DNS, TLS, timeout).
public struct PandoraTransportError: Error, Sendable, Equatable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

/// The response body was not decodable JSON, or had no `stat`.
public struct PandoraMalformedResponseError: Error, Sendable, Equatable {
    public let detail: String
    public init(detail: String) { self.detail = detail }
}
