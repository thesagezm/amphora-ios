//
//  Scrobbler.swift
//  Amphora
//
//  Last.fm scrobbling for the app target — the PandoraCore
//  `LastFmClient` with BitChord's playback semantics (adopted
//  2026-11-19):
//
//  - `nowPlaying` when a track starts, unless the now-playing switch
//    is off.
//  - one `track.scrobble` when the *playing* position crosses the
//    track's threshold — min(delayPercent × duration, maxDelaySeconds)
//    of the song, the default 50 % or 180 s — so the scrobble goes
//    out while the song is still playing, the way BitChord's
//    pause-aware timer does. The position advances only while the
//    player plays, so a paused song never crosses; the song's
//    *start* time is the Last.fm timestamp either way.
//
//  The session key is a secret — Keychain only, never UserDefaults.
//  The enable preference is a non-secret and lives in `Preferences`
//  (the store owns the write; this class exposes the flag).
//
//  Scrobbling must never disturb playback (Priority 1): failures log
//  and, when Last.fm rejects the session (error 9 — or error 4, which
//  is how a dead key surfaces on the scrobble methods), the state
//  becomes `.needsAuth` — the user signs in again from Settings. The
//  credentials sentence ("rejected that username or password") is the
//  sign-in form's answer only; playback-time rejections are session
//  failures, not credential failures.
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
    /// BitChord's "scrobble tracks" switch — the account can stay
    /// connected while no scrobble is submitted (now-playing only).
    var scrobbleTracks = true
    /// BitChord's "now playing" switch.
    var nowPlayingEnabled = true
    /// BitChord's "primary artist only" switch — joint credits are
    /// stripped to the first artist ("Alice, Bob" → "Alice"), for
    /// services that mishandle them. Off by default: the split is
    /// faithful to BitChord, so "Simon & Garfunkel" becomes "Simon"
    /// when it is on.
    var primaryArtistOnly = false
    /// The rule knobs (BitChord's sliders). The defaults are theirs: a
    /// song of 30 s or longer, scrobbled once it has been *played* for
    /// min(50 % of it, 180 s).
    var minDuration: TimeInterval = 30
    var delayPercent: Double = 0.5
    var maxDelaySeconds: TimeInterval = 180
    /// Fires when the scrobbler itself flips the enable flag (sign-in
    /// enables it, a rejected session key or sign-out disables it).
    /// `AppStore` persists the preference here — without it, a fresh
    /// sign-in enabled scrobbling only in memory and the preference
    /// read back on the next launch was still `false`.
    var onEnabledChanged: ((Bool) -> Void)?
    /// True while an `auth.getMobileSession` round trip is in flight.
    private(set) var isAuthenticating = false
    /// The last authentication failure, for the Settings sheet.
    private(set) var authError: String?

    /// What the scrobbler last did, for the Settings status line —
    /// "Now playing: …" / "Scrobbled …" / the last error. Without this
    /// the user cannot tell a working connection from a silently
    /// failing one (scrobble failures deliberately never interrupt
    /// playback, so the Settings row is the only place they surface).
    private(set) var lastActivity: String?
    /// True when `lastActivity` is an error rather than a success.
    private(set) var lastActivityIsError = false

    /// The track whose scrobble is still pending, the playing position
    /// at which it earns one, and when it started playing. `nil` when
    /// nothing is pending (radio, a cleared queue, or the scrobble
    /// already went out).
    private var pendingTrack: Track?
    private var pendingThreshold: TimeInterval?
    private var pendingStartedAt: Date?
    private var didScrobble = false

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
            onEnabledChanged?(true)
            lastActivity = "Signed in. Play a track to scrobble."
            lastActivityIsError = false
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
        onEnabledChanged?(false)
        authError = nil
        lastActivity = nil
        lastActivityIsError = false
        AppLog.info("last.fm: signed out")
    }

    /// Clears a stale sign-in failure. The message must answer the
    /// attempt that caused it, not sit under the form forever — the
    /// fields' edits call this, so the error disappears the moment the
    /// user starts typing a corrected entry.
    func clearAuthError() {
        authError = nil
    }

    // MARK: - Playback hooks

    /// A track started playing: arms the pending scrobble (the
    /// threshold from the current settings) and — when the switch is
    /// on — pushes the "now playing" line to the profile.
    ///
    /// The threshold is the crossing point of BitChord's rule: the
    /// scrobble goes out *during* the song, not when it ends.
    func trackStarted(_ track: Track, startedAt: Date) {
        pendingTrack = track
        pendingStartedAt = startedAt
        didScrobble = false
        pendingThreshold = ScrobblePolicy.scrobbleThreshold(
            duration: TimeInterval(track.duration),
            isAdvertisement: track.isAdvertisement,
            minDuration: minDuration,
            delayPercent: delayPercent,
            maxDelaySeconds: maxDelaySeconds
        )
        guard nowPlayingEnabled else { return }
        updateNowPlaying(track)
    }

    /// The current track is gone (stop, station switch, an emptied
    /// queue): the pending scrobble is dropped — a track that never
    /// crossed its threshold earns nothing.
    func trackCleared() {
        pendingTrack = nil
        pendingThreshold = nil
        pendingStartedAt = nil
        didScrobble = false
    }

    /// A playback tick (about twice a second of playing time). When
    /// the position crosses the pending track's threshold, the
    /// scrobble goes out — BitChord's pause-aware timer, expressed as
    /// a comparison: the position advances only while the player
    /// plays, so a paused song never crosses.
    func playbackTick(position: TimeInterval) {
        guard isReady, scrobbleTracks, !didScrobble else { return }
        guard let track = pendingTrack, let threshold = pendingThreshold else { return }
        guard position >= threshold else { return }
        submit(track: track, startedAt: pendingStartedAt)
    }

    /// The track stopped being current (natural end, skip, station
    /// switch). The crossing check has normally fired long before;
    /// this is the fallback for a threshold the song only reaches at
    /// its very end (a 100 % delay on a short song).
    func trackFinished(track: Track, reachedPosition: TimeInterval) {
        defer { trackCleared() }
        guard isReady, scrobbleTracks, !didScrobble else { return }
        guard let pending = pendingTrack, pending.trackToken == track.trackToken else { return }
        guard let threshold = pendingThreshold else { return }
        guard reachedPosition >= threshold else {
            AppLog.debug(
                "last.fm: not scrobbling \"\(track.title)\" (threshold \(Int(threshold))s not reached)",
                .playback
            )
            return
        }
        submit(track: track, startedAt: pendingStartedAt)
    }

    /// `track.updateNowPlaying` for a track that just started. Never
    /// blocks or disturbs playback.
    private func updateNowPlaying(_ track: Track) {
        guard isReady, !track.isAdvertisement else { return }
        let key = sessionKey()
        guard !key.isEmpty else { return }
        AppLog.info("last.fm: now playing \"\(track.title)\" — \(track.artist)")
        Task {
            do {
                try await client.updateNowPlaying(
                    sessionKey: key,
                    artist: scrobbleArtist(track),
                    track: track.title,
                    album: track.album,
                    duration: TimeInterval(track.duration)
                )
                self.lastActivity = "Now playing on Last.fm: \(track.title)"
                self.lastActivityIsError = false
            } catch {
                self.handle(error, while: track.title)
            }
        }
    }

    /// `track.scrobble` — one scrobble, carrying the song's *start*
    /// time as the timestamp (Last.fm wants the start, not the
    /// crossing). One attempt per song: a failure surfaces in the
    /// Settings status line rather than being retried in a loop.
    private func submit(track: Track, startedAt: Date?) {
        guard let startedAt else { return }
        let key = sessionKey()
        guard !key.isEmpty else { return }
        didScrobble = true
        let timestamp = Int(startedAt.timeIntervalSince1970)
        AppLog.info("last.fm: scrobbling \"\(track.title)\" — \(track.artist)")
        Task {
            do {
                try await client.scrobble(
                    sessionKey: key,
                    artist: scrobbleArtist(track),
                    track: track.title,
                    album: track.album,
                    timestamp: timestamp,
                    duration: TimeInterval(track.duration)
                )
                self.lastActivity = "Scrobbled: \(track.title)"
                self.lastActivityIsError = false
            } catch {
                self.handle(error, while: track.title)
            }
        }
    }

    /// The artist to scrobble: with BitChord's "primary artist only"
    /// switch on, joint credits are stripped to the first artist.
    private func scrobbleArtist(_ track: Track) -> String {
        primaryArtistOnly ? ScrobblePolicy.primaryArtist(track.artist) : track.artist
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

    /// Scrobble failures only log — except a rejected *session* (the
    /// key, error 9 — or error 4, which is how Last.fm reports a dead
    /// key on the scrobble/now-playing methods), which disables
    /// scrobbling until re-auth.
    private func handle(_ error: Error, while title: String) {
        if case LastFmError.invalidSessionKey = error {
            sessionEnded()
            return
        }
        // "Invalid username or password" during *playback* is not the
        // credentials sentence's business — the password is never
        // stored. Last.fm reports a dead session key as error 4 on
        // these methods, so the session failure gets the same
        // re-auth handling as error 9 (user report 2026-11-12: the
        // credentials sentence appeared in the status line and the
        // logs for what is a session ending).
        if case LastFmError.invalidCredentials = error {
            sessionEnded()
            return
        }
        lastActivity = "Last.fm error on \"\(title)\": \(Self.userMessage(for: error))"
        lastActivityIsError = true
        AppLog.error("last.fm: update failed for \"\(title)\": \(String(describing: error))", .playback)
    }

    /// The stored session is no longer valid: drop it, disable
    /// scrobbling and put the sign-in form back.
    private func sessionEnded() {
        AppLog.error("last.fm: session rejected — scrobbling paused")
        authState = .needsAuth(message: "Last.fm session ended. Sign in again.")
        isEnabled = false
        onEnabledChanged?(false)
        try? keychain.remove(Self.keychainAccount)
        lastActivity = "Last.fm session ended. Sign in again."
        lastActivityIsError = true
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
