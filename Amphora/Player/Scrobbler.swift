//
//  Scrobbler.swift
//  Amphora
//
//  Last.fm scrobbling for the app target — composition of the
//  PandoraCore `LastFmClient` with the pithos playback semantics:
//
//  - `nowPlaying` when a track starts (pithos `_on_song_changed`).
//  - one `track.scrobble` when a track stops being the current one
//    (natural end, skip, station switch), if pithos's rule
//    (`ScrobblePolicy`) says it was earned (pithos `_on_song_ended`).
//
//  The session key is a secret — Keychain only, never UserDefaults.
//  The enable preference is a non-secret and lives in `Preferences`
//  (the store owns the write; this class exposes the flag).
//
//  Scrobbling must never disturb playback (Priority 1): failures log
//  and, when Last.fm rejects the session key (error 9), the state
//  becomes `.needsAuth` — the user signs in again from Settings.
//

import Foundation
import Observation
import PandoraCore

@MainActor
@Observable
final class Scrobbler {

    enum AuthState: Equatable {
        case signedOut
        case signedIn(username: String)
        /// Last.fm rejected the stored session key (error 9) — the user
        /// must sign in again; the dead key is discarded.
        case needsAuth(message: String)
    }

    private static let keychainAccount = "lastfm.session"

    private let client = LastFmClient()
    private let keychain: KeychainStore

    private(set) var authState: AuthState = .signedOut
    /// Master switch, persisted via `AppStore`'s preferences. Only
    /// meaningful while signed in.
    var isEnabled = false
    /// True while an `auth.getMobileSession` round trip is in flight.
    private(set) var isAuthenticating = false
    /// The last authentication failure, for the Settings sheet.
    private(set) var authError: String?

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        if let session = Self.loadSession(from: keychain) {
            authState = .signedIn(username: session.username)
        }
    }

    // MARK: - Authentication

    /// Exchanges Last.fm credentials for a session key (`auth.
    /// getMobileSession`) and stores it in the Keychain. The password is
    /// never persisted. Enabling follows automatically — pithos
    /// scrobbles as soon as the account is authorized.
    func authenticate(username: String, password: String) async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            authError = "Enter your Last.fm username and password."
            return
        }
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }
        do {
            let session = try await client.authenticate(username: user, password: password)
            let data = try JSONEncoder().encode(session)
            try keychain.set(data, for: Self.keychainAccount)
            authState = .signedIn(username: session.username)
            isEnabled = true
            AppLog.info("last.fm: signed in as \(session.username)")
        } catch {
            AppLog.error("last.fm: sign-in failed (\(String(describing: error)))")
            authError = Self.userMessage(for: error)
        }
    }

    /// Discards the session key and turns scrobbling off.
    func signOut() {
        try? keychain.remove(Self.keychainAccount)
        authState = .signedOut
        isEnabled = false
        authError = nil
        AppLog.info("last.fm: signed out")
    }

    // MARK: - Playback hooks

    /// `track.updateNowPlaying` for a track that just started. Never
    /// blocks or disturbs playback.
    func nowPlaying(_ track: Track) {
        guard isReady, !track.isAdvertisement else { return }
        let key = sessionKey()
        guard !key.isEmpty else { return }
        AppLog.info("last.fm: now playing \"\(track.title)\" — \(track.artist)")
        Task {
            do {
                try await client.updateNowPlaying(
                    sessionKey: key,
                    artist: track.artist,
                    track: track.title,
                    album: track.album,
                    duration: TimeInterval(track.duration)
                )
            } catch {
                self.handle(error, while: track.title)
            }
        }
    }

    /// Scrobbles the track that just stopped being current (natural end,
    /// skip, station switch) if pithos's rule says it was earned.
    /// `startedAt` is when the track began playing — Last.fm wants the
    /// start time, not the scrobble time.
    func scrobbleIfEarned(track: Track, reachedPosition: TimeInterval, startedAt: Date) {
        guard isReady else { return }
        let duration = TimeInterval(track.duration)
        guard ScrobblePolicy.shouldScrobble(
            duration: duration,
            position: reachedPosition,
            isAdvertisement: track.isAdvertisement
        ) else {
            AppLog.debug(
                "last.fm: not scrobbling \"\(track.title)\" (rule not met, reached \(Int(reachedPosition))s)",
                .playback
            )
            return
        }
        let key = sessionKey()
        guard !key.isEmpty else { return }
        let timestamp = Int(startedAt.timeIntervalSince1970)
        AppLog.info("last.fm: scrobbling \"\(track.title)\" — \(track.artist)")
        Task {
            do {
                try await client.scrobble(
                    sessionKey: key,
                    artist: track.artist,
                    track: track.title,
                    album: track.album,
                    timestamp: timestamp,
                    duration: duration
                )
            } catch {
                self.handle(error, while: track.title)
            }
        }
    }

    // MARK: - Internals

    private var isReady: Bool {
        isEnabled && authState != .signedOut
    }

    /// Reads the session key; `.needsAuth` state has no key to send.
    /// Empty string means "skip the network call".
    private func sessionKey() -> String {
        if case .needsAuth = authState { return "" }
        guard let session = Self.loadSession(from: keychain) else {
            authState = .needsAuth(message: "Last.fm session lost. Sign in again.")
            return ""
        }
        return session.key
    }

    /// Scrobble failures only log — except a rejected session key
    /// (error 9), which disables scrobbling until re-auth.
    private func handle(_ error: Error, while title: String) {
        if case LastFmError.invalidSessionKey = error {
            AppLog.error("last.fm: session key rejected — scrobbling paused")
            authState = .needsAuth(message: "Last.fm session ended. Sign in again.")
            isEnabled = false
            try? keychain.remove(Self.keychainAccount)
            return
        }
        AppLog.error("last.fm: update failed for \"\(title)\": \(String(describing: error))", .playback)
    }

    private static func userMessage(for error: Error) -> String {
        switch error as? LastFmError {
        case .invalidCredentials:
            return "Last.fm rejected that username or password."
        case .rateLimited:
            return "Last.fm is rate limiting. Wait a moment and try again."
        case .invalidApiKey, .invalidSignature, .malformed:
            return "Last.fm sent an unexpected response. Try again."
        case .rejected(_, let message) where !message.isEmpty:
            return "Last.fm: \(message)"
        case .httpStatus:
            return "Couldn't reach Last.fm. Try again."
        case .transport:
            return "Couldn't reach Last.fm. Check your connection."
        default:
            return "Sign-in failed. Try again."
        }
    }

    private static func loadSession(from keychain: KeychainStore) -> LastFmSession? {
        guard let data = try? keychain.data(for: keychainAccount) else { return nil }
        return try? JSONDecoder().decode(LastFmSession.self, from: data)
    }
}
