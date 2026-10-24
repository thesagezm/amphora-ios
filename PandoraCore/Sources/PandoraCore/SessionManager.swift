//
//  SessionManager.swift
//  PandoraCore
//
//  Auth lifecycle for the legacy JSON API (v5), mirroring
//  `pithos.pandora.Pandora.connect()` plus automatic re-auth:
//
//    partner login (plain body) → decrypt syncTime → time offset
//      → user login (Blowfish body) → tokens + store
//    on fault 1001 (invalid auth token): transparent re-login, replay the
//      failed call exactly once, then surface the typed error.
//
//  An actor so login/re-auth/replay are serialized — concurrent callers can
//  never interleave two partner logins. Credential/token persistence is
//  injected (`SessionStore`); PandoraCore stays free of Apple-only APIs
//  (Keychain lands in the app target) and free of UI/AVFoundation.
//

import Foundation

// MARK: - Records

/// Established session tokens (all values the client needs to stamp later
/// requests). Codable so any store can persist it as-is.
public struct SessionTokens: Codable, Sendable, Equatable {
    public let partnerId: String
    public let partnerAuthToken: String
    public let userId: String
    public let userAuthToken: String
    /// `pandora_time − local_time`, fixed at partner login; drives syncTime.
    public let timeOffset: TimeInterval

    public init(
        partnerId: String,
        partnerAuthToken: String,
        userId: String,
        userAuthToken: String,
        timeOffset: TimeInterval
    ) {
        self.partnerId = partnerId
        self.partnerAuthToken = partnerAuthToken
        self.userId = userId
        self.userAuthToken = userAuthToken
        self.timeOffset = timeOffset
    }
}

public struct Credentials: Codable, Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// What a session store persists: tokens plus the credentials needed for
/// transparent re-auth and next-launch auto-login.
public struct SessionRecord: Codable, Sendable, Equatable {
    public let credentials: Credentials
    public let tokens: SessionTokens
    public let isSubscriber: Bool

    public init(credentials: Credentials, tokens: SessionTokens, isSubscriber: Bool) {
        self.credentials = credentials
        self.tokens = tokens
        self.isSubscriber = isSubscriber
    }
}

// MARK: - Store

/// Persistence seam. Apple-side implementation (Keychain) lives in the app
/// target; `InMemorySessionStore` serves tests and fallback.
public protocol SessionStore: Sendable {
    func save(_ record: SessionRecord) throws
    func load() -> SessionRecord?
    func clear() throws
}

public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record: SessionRecord?

    public init(record: SessionRecord? = nil) {
        self.record = record
    }

    public func save(_ record: SessionRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        self.record = record
    }

    public func load() -> SessionRecord? {
        lock.lock()
        defer { lock.unlock() }
        return record
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        record = nil
    }
}

// MARK: - Errors

public enum SessionManagerError: Error, Equatable, Sendable {
    /// No credentials/session — the app must show login first.
    case notAuthenticated
    /// A session field was missing or undecodable in an otherwise-ok response.
    case malformedSession(detail: String)
}

// MARK: - SessionManager

public actor SessionManager {
    private let client: LegacyPandoraClient
    private let modes: PandoraModesClient
    private let store: (any SessionStore)?
    private let now: @Sendable () -> Date

    private var credentials: Credentials?
    private var tokens: SessionTokens?
    private var subscriber = false

    public init(
        client: LegacyPandoraClient = LegacyPandoraClient(),
        modes: PandoraModesClient = PandoraModesClient(),
        store: (any SessionStore)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.modes = modes
        self.store = store
        self.now = now
    }

    /// Current session, nil when signed out.
    public var session: SessionTokens? { tokens }

    public var isSubscriber: Bool { subscriber }

    public var hasSession: Bool { tokens != nil }

    // MARK: Login

    /// Full connect flow (pithos `Pandora.connect`): partner login →
    /// syncTime decode → user login → store. Resets any prior session first,
    /// exactly like the reference implementation.
    public func login(username: String, password: String) async throws -> SessionTokens {
        // Reset — a failed re-auth must not leave a half-live session.
        credentials = nil
        tokens = nil
        subscriber = false
        client.context = URLBuilder.Context()

        // 1. Partner login — plain JSON body (no Blowfish), no auth query.
        let partner = try await client.request(
            method: PandoraAPI.Method.partnerLogin,
            parameters: [
                "username": .string(PandoraAPI.partnerUsername),
                "password": .string(PandoraAPI.partnerPassword),
                "deviceModel": .string(PandoraAPI.partnerDeviceModel),
                "version": .string(PandoraAPI.version)
            ],
            encrypt: false,
            now: now()
        )
        let partnerId = try idField(partner, "partnerId")
        let partnerToken = try partner.string("partnerAuthToken")
        let syncTimeHex = try partner.string("syncTime")

        let localNow = now()
        let offset = try Self.timeOffset(
            encryptedSyncTime: syncTimeHex,
            localTime: localNow
        )

        client.context = URLBuilder.Context(
            partnerId: partnerId,
            partnerAuthToken: partnerToken,
            timeOffset: offset
        )

        // 2. User login — Blowfish body; syncTime + partnerAuthToken are
        //    stamped in by URLBuilder from the context.
        let user = try await client.request(
            method: PandoraAPI.Method.userLogin,
            parameters: [
                "username": .string(username),
                "password": .string(password),
                "loginType": .string("user"),
                "returnIsSubscriber": .bool(true)
            ],
            encrypt: true,
            now: now()
        )
        let userId = try idField(user, "userId")
        let userToken = try user.string("userAuthToken")
        let isSubscriber = try user.bool("isSubscriber")

        let newTokens = SessionTokens(
            partnerId: partnerId,
            partnerAuthToken: partnerToken,
            userId: userId,
            userAuthToken: userToken,
            timeOffset: offset
        )
        client.context = URLBuilder.Context(
            partnerId: partnerId,
            partnerAuthToken: partnerToken,
            userId: userId,
            userAuthToken: userToken,
            timeOffset: offset
        )

        let newCredentials = Credentials(username: username, password: password)
        credentials = newCredentials
        tokens = newTokens
        subscriber = isSubscriber
        try store?.save(
            SessionRecord(credentials: newCredentials, tokens: newTokens, isSubscriber: isSubscriber)
        )
        return newTokens
    }

    /// Restores a stored session into memory without a network round trip —
    /// the fast path for warm launch. If the token is already expired, the
    /// first `authenticatedRequest` triggers 1001 → transparent re-login.
    @discardableResult
    public func restore() -> Bool {
        guard let record = store?.load() else { return false }
        credentials = record.credentials
        tokens = record.tokens
        subscriber = record.isSubscriber
        client.context = URLBuilder.Context(
            partnerId: record.tokens.partnerId,
            partnerAuthToken: record.tokens.partnerAuthToken,
            userId: record.tokens.userId,
            userAuthToken: record.tokens.userAuthToken,
            timeOffset: record.tokens.timeOffset
        )
        return true
    }

    // MARK: Authenticated requests

    /// Encrypted request under the current session. On fault 1001 (session
    /// expired) re-logins with the in-memory credentials and replays exactly
    /// once; a second 1001 (or any other error) is surfaced as-is.
    public func authenticatedRequest(
        _ method: String,
        parameters: [String: JSONValue] = [:]
    ) async throws -> [String: AnyJSON] {
        guard let credentials, tokens != nil else {
            throw SessionManagerError.notAuthenticated
        }
        do {
            return try await client.request(
                method: method,
                parameters: parameters,
                encrypt: true,
                now: now()
            )
        } catch let error as PandoraAPIError where error.isSessionExpired {
            _ = try await login(
                username: credentials.username,
                password: credentials.password
            )
            // Retry once — a second 1001 lands here and propagates.
            return try await client.request(
                method: method,
                parameters: parameters,
                encrypt: true,
                now: now()
            )
        }
    }

    // MARK: Stations

    /// The user's station list: `user.getStationList` with
    /// `returnAllStations=true` (pithos `get_stations`) and
    /// `includeStationArtUrl=true` (pydora `get_all_stations`) under the
    /// current session — 1001 → transparent re-login, replay once.
    public func getStationList() async throws -> StationList {
        let result = try await authenticatedRequest(
            PandoraAPI.Method.getStationList,
            parameters: [
                "returnAllStations": .bool(true),
                "includeStationArtUrl": .bool(true)
            ]
        )
        return try StationList(result: result)
    }

    /// Create from an artist/seed token (pithos `add_station_by_music_id`).
    /// The reply is a full station dict — same shape as list entries.
    public func createStation(musicToken: String) async throws -> Station {
        let result = try await authenticatedRequest(
            PandoraAPI.Method.createStation,
            parameters: ["musicToken": .string(musicToken)]
        )
        return try Station(result: result)
    }

    /// Create seeded from a song (pithos `add_station_by_track_token`).
    /// `musicType` is the seed's type tag from the search reply
    /// (e.g. `"song"` / `"track"` — the value the API returned, not a
    /// guessed literal).
    public func createStation(trackToken: String, musicType: String) async throws -> Station {
        let result = try await authenticatedRequest(
            PandoraAPI.Method.createStation,
            parameters: [
                "trackToken": .string(trackToken),
                "musicType": .string(musicType)
            ]
        )
        return try Station(result: result)
    }

    /// Rename (pithos `Station.rename`): a shared station must first be
    /// transformed into a personal one (`station.transformSharedStation`,
    /// pithos `transformIfShared`) or the rename is rejected.
    public func renameStation(_ station: Station, to newName: String) async throws {
        guard newName != station.name else { return }
        if station.isShared {
            _ = try await authenticatedRequest(
                PandoraAPI.Method.transformSharedStation,
                parameters: ["stationToken": .string(station.token)]
            )
        }
        _ = try await authenticatedRequest(
            PandoraAPI.Method.renameStation,
            parameters: [
                "stationToken": .string(station.token),
                "stationName": .string(newName)
            ]
        )
    }

    /// Delete (pithos `delete_station` — station list membership only;
    /// the API does not delete the account-level seed).
    public func deleteStation(_ station: Station) async throws {
        _ = try await authenticatedRequest(
            PandoraAPI.Method.deleteStation,
            parameters: ["stationToken": .string(station.token)]
        )
    }

    /// Search artists / songs / genre stations for the add-station flow.
    /// Params match pithos `Pandora.search()` exactly; scoring/filtering/
    /// ordering happen in `MusicSearchResult.searchResults(from:)`.
    public func search(_ query: String) async throws -> [MusicSearchResult] {
        let result = try await authenticatedRequest(
            PandoraAPI.Method.musicSearch,
            parameters: [
                "includeGenreStations": .bool(true),
                "includeNearMatches": .bool(true),
                "searchText": .string(query)
            ]
        )
        return MusicSearchResult.searchResults(from: result)
    }

    // MARK: Playback

    /// Fetch a station's playlist (pithos `Station.get_playlist`).
    /// Requests track lengths and both extra stream formats so the client
    /// can always pick the highest available quality (see `Track.variants`).
    public func getPlaylist(for station: Station) async throws -> Playlist {
        let result = try await authenticatedRequest(
            PandoraAPI.Method.getPlaylist,
            parameters: [
                "stationToken": .string(station.token),
                "includeTrackLength": .bool(true),
                "additionalAudioUrl": .string(PandoraAPI.additionalAudioURLs)
            ]
        )
        return Playlist(tracks: Track.tracks(from: result), fetchedAt: now())
    }

    // MARK: Advertisements

    /// Resolves an advertisement entry (pydora `get_ad_item`):
    /// `ad.getAdMetadata` with `returnAdTrackingTokens=true` and
    /// `supportAudioAds=true` under the current session.
    public func getAdMetadata(adToken: String) async throws -> Advertisement {
        let result = try await authenticatedRequest(
            PandoraAPI.Method.getAdMetadata,
            parameters: [
                "adToken": .string(adToken),
                "returnAdTrackingTokens": .bool(true),
                "supportAudioAds": .bool(true)
            ]
        )
        return Advertisement(adToken: adToken, result: result)
    }

    /// Registers an ad impression (pydora `register_ad`): `ad.registerAd`
    /// with the station id and the tracking tokens from the metadata
    /// reply. Refuses empty token lists before any network (pydora
    /// `ParameterMissing`).
    public func registerAd(stationId: String, trackingTokens: [String]) async throws {
        guard !trackingTokens.isEmpty else {
            throw AdvertisementError.missingTrackingTokens
        }
        _ = try await authenticatedRequest(
            PandoraAPI.Method.registerAd,
            parameters: [
                "stationId": .string(stationId),
                "adTrackingTokens": .array(trackingTokens.map(JSONValue.string))
            ]
        )
    }

    /// Resolve + register in one step (pydora `AdItem.prepare_playback`):
    /// metadata is required, registration is best-effort. Deviation from
    /// pydora documented: pydora propagates register errors out of
    /// `prepare_playback`, Amphora swallows them — a failed impression
    /// registration must never block playback (Priority 1). Call
    /// `registerAd` directly for the strict contract. With no tracking
    /// tokens in the reply, registration is skipped entirely (pydora
    /// catches its own `ParameterMissing` in the same situation).
    public func prepareAd(_ ad: Track, stationId: String? = nil) async throws -> Advertisement {
        guard ad.isAdvertisement, let adToken = ad.adToken else {
            throw AdvertisementError.notAnAdvertisement
        }
        let metadata = try await getAdMetadata(adToken: adToken)
        let targetStation = stationId ?? ad.stationId
        if !metadata.trackingTokens.isEmpty, !targetStation.isEmpty {
            try? await registerAd(stationId: targetStation, trackingTokens: metadata.trackingTokens)
        }
        return metadata
    }

    // MARK: Station tuning (listening modes)

    /// The station's listening modes ("My Mix", "Deep Cuts", …) from the
    /// modern `interactiveradio` web API, authenticated with the legacy
    /// session's user token (see `PandoraModesClient`). The station's
    /// numeric `stationId` is the identifier both API generations share
    /// (pandoCast passes it as `stationId`).
    ///
    /// 401/403 (the modern API's session-expiry signal) → transparent
    /// re-login, retry once — the same contract as `authenticatedRequest`.
    public func getStationModes(for station: Station) async throws -> StationModes {
        guard let authToken = tokens?.userAuthToken else {
            throw SessionManagerError.notAuthenticated
        }
        do {
            return try await modes.getModes(userAuthToken: authToken, stationId: station.id)
        } catch StationModesError.unauthorized {
            try await reloginAfterUnauthorized()
            guard let fresh = tokens?.userAuthToken else {
                throw SessionManagerError.notAuthenticated
            }
            return try await modes.getModes(userAuthToken: fresh, stationId: station.id)
        }
    }

    /// Select a listening mode. Refuses the call without touching the
    /// network when the mode is not offered for the station, or when it is
    /// premium-only and the account is free (panedora gates both ways).
    /// Changing the mode changes what the *next* playlist fetch returns —
    /// "changing modes starts a new song".
    public func setStationMode(
        _ mode: StationMode,
        for station: Station,
        previousModeID: Int? = nil
    ) async throws -> StationModes {
        guard mode.isAvailable else { throw StationModesError.modeNotOffered }
        if mode.isPremiumOnly && !subscriber {
            throw StationModesError.notEntitled
        }
        guard let authToken = tokens?.userAuthToken else {
            throw SessionManagerError.notAuthenticated
        }
        do {
            return try await modes.setMode(
                userAuthToken: authToken,
                stationId: station.id,
                modeId: mode.id,
                previousModeId: previousModeID
            )
        } catch StationModesError.unauthorized {
            try await reloginAfterUnauthorized()
            guard let fresh = tokens?.userAuthToken else {
                throw SessionManagerError.notAuthenticated
            }
            return try await modes.setMode(
                userAuthToken: fresh,
                stationId: station.id,
                modeId: mode.id,
                previousModeId: previousModeID
            )
        }
    }

    private func reloginAfterUnauthorized() async throws {
        guard let credentials else { throw SessionManagerError.notAuthenticated }
        _ = try await login(username: credentials.username, password: credentials.password)
    }

    // MARK: Feedback

    /// Rate a track (thumbs up / thumbs down).
    ///
    /// `station.addFeedback` with `trackToken`, `stationToken` and
    /// `isPositive` (pithos `Pandora.add_feedback` + libpiano's
    /// `PIANO_REQUEST_ADD_FEEDBACK`). The reply carries the
    /// `feedbackId` needed to undo the rating.
    public func addFeedback(
        trackToken: String,
        stationToken: String,
        rating: FeedbackRating
    ) async throws -> FeedbackReceipt {
        guard rating != .none else {
            throw PandoraAPIError(code: 0, message: "cannot add a 'none' rating")
        }
        let result = try await authenticatedRequest(
            PandoraAPI.Method.addFeedback,
            parameters: [
                "trackToken": .string(trackToken),
                "stationToken": .string(stationToken),
                "isPositive": .bool(rating.isPositive)
            ]
        )
        return try FeedbackReceipt(result: result)
    }

    /// Remove a rating (thumbs up/down → unrated).
    /// `station.deleteFeedback` with `feedbackId` and `stationToken`
    /// (pithos `Pandora.delete_feedback`; libpiano sends only the id).
    public func deleteFeedback(feedbackId: String, stationToken: String) async throws {
        _ = try await authenticatedRequest(
            PandoraAPI.Method.deleteFeedback,
            parameters: [
                "feedbackId": .string(feedbackId),
                "stationToken": .string(stationToken)
            ]
        )
    }

    /// Hide a track for the next few hours (`user.sleepSong`, pithos
    /// `Song.set_tired`).
    public func sleepSong(trackToken: String) async throws {
        _ = try await authenticatedRequest(
            PandoraAPI.Method.sleepSong,
            parameters: ["trackToken": .string(trackToken)]
        )
    }

    // MARK: Bookmarks

    /// The user's bookmarks (`user.getBookmarks`, pydora
    /// `APIClient.get_bookmarks`).
    public func getBookmarks() async throws -> [Bookmark] {
        let result = try await authenticatedRequest(PandoraAPI.Method.getBookmarks)
        return Bookmark.bookmarks(from: result)
    }

    /// Bookmark a song (`bookmark.addSongBookmark`, pithos
    /// `Song.bookmark`).
    public func addSongBookmark(trackToken: String) async throws {
        _ = try await authenticatedRequest(
            PandoraAPI.Method.addSongBookmark,
            parameters: ["trackToken": .string(trackToken)]
        )
    }

    /// Bookmark the artist of a track (`bookmark.addArtistBookmark`,
    /// pithos `Song.bookmark_artist`).
    public func addArtistBookmark(trackToken: String) async throws {
        _ = try await authenticatedRequest(
            PandoraAPI.Method.addArtistBookmark,
            parameters: ["trackToken": .string(trackToken)]
        )
    }

    /// Remove a song bookmark (`bookmark.deleteSongBookmark`, pydora
    /// `delete_song_bookmark`).
    public func deleteSongBookmark(bookmarkToken: String) async throws {
        _ = try await authenticatedRequest(
            PandoraAPI.Method.deleteSongBookmark,
            parameters: ["bookmarkToken": .string(bookmarkToken)]
        )
    }

    /// Remove an artist bookmark (`bookmark.deleteArtistBookmark`, pydora
    /// `delete_artist_bookmark`).
    public func deleteArtistBookmark(bookmarkToken: String) async throws {
        _ = try await authenticatedRequest(
            PandoraAPI.Method.deleteArtistBookmark,
            parameters: ["bookmarkToken": .string(bookmarkToken)]
        )
    }

    // MARK: Helpers

    /// partnerId/userId arrive as either JSON string or number depending on
    /// the endpoint (pithos formats with `%s`, accepting both).
    private func idField(_ result: [String: AnyJSON], _ key: String) throws -> String {
        if let string = result[key]?.stringValue { return string }
        if let number = result[key]?.intValue { return String(number) }
        throw SessionManagerError.malformedSession(detail: "missing id field \(key)")
    }

    /// `offset = pandora_time − local_time`, where pandora_time is the
    /// decrypted syncTime's bytes[4..<14] (pithos: `pandora_decrypt(...)[4:14]`).
    static func timeOffset(encryptedSyncTime hex: String, localTime: Date) throws -> TimeInterval {
        let decrypted = try PandoraCrypto.decryptHexField(hex)
        guard decrypted.count >= 14 else {
            throw SessionManagerError.malformedSession(detail: "syncTime too short after decrypt")
        }
        let stampData = decrypted[4..<14]
        guard let stamp = Int(String(decoding: stampData, as: UTF8.self)) else {
            throw SessionManagerError.malformedSession(detail: "syncTime digits unparsable")
        }
        return TimeInterval(stamp) - localTime.timeIntervalSince1970
    }
}
