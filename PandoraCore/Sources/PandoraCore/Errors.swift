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

    // MARK: - Skip limit

    /// Pandora's fault message when a station's playlist simply ran out
    /// (Elpis `Libs/PandoraSharp/Station.cs:232` compares the exception
    /// message against this literal).
    public static let playlistEndMessage = "PLAYLIST_END"

    /// Pandora's fault message when the daily skip limit was reached and
    /// an explicit skip was refused (same reference).
    public static let dailySkipLimitMessage = "DAILY_SKIP_LIMIT_REACHED"

    /// `true` when the fault means Pandora's daily skip limit stopped
    /// the playlist.
    ///
    /// The legacy API signals this by **message**, not by a numeric
    /// fault code — the code table above has no entry for it, which is
    /// why it is matched on the server's text. The comparison is
    /// case-insensitive and tolerates surrounding whitespace; a message
    /// that merely contains the token counts too (the server may append
    /// a sentence).
    public var isSkipLimitReached: Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return text.contains(Self.playlistEndMessage)
            || text.contains(Self.dailySkipLimitMessage)
    }

    /// `true` when the fault is the playlist running out
    /// (`PLAYLIST_END`) rather than an explicit skip being refused
    /// (`DAILY_SKIP_LIMIT_REACHED`). Elpis treats the playlist-end fault
    /// as "skip limit reached" too — both stop the stream of tracks.
    public var isPlaylistEnd: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .contains(Self.playlistEndMessage)
    }

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

/// A playlist request Pandora refused for a station-specific reason.
public enum PlaylistError: Error, Sendable, Equatable {
    /// Pandora's daily skip limit was reached for the station: the
    /// server stops handing out tracks until the limit resets.
    ///
    /// This is **not** a transport failure and must not be retried in a
    /// loop — AGENTS.md: "Respect skip limits and rate limits. Never
    /// hammer the API."
    ///
    /// `playlistEnded` tells the two server signals apart:
    /// `PLAYLIST_END` (the playlist ran out) and
    /// `DAILY_SKIP_LIMIT_REACHED` (an explicit skip was refused).
    case skipLimitReached(playlistEnded: Bool)
}
