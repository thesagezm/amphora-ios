//
//  PreferencesStore.swift
//  Amphora
//
//  Small Codable-to-disk store for user preferences that are not secrets:
//  the station order, the last played station and the sleep-timer
//  preference. One JSON file in Application Support.
//
//  (Credentials and session tokens live in the Keychain — never here.)
//

import Foundation
import PandoraCore

/// The app's non-secret preferences.
struct Preferences: Codable, Equatable {
    /// The user's station ordering.
    var stationOrder = StationOrder()
    /// The station that was playing when the app was last used.
    var lastStationId: String?
    /// The sleep timer preference (off by default).
    var sleepTimer = SleepTimer.off
    /// Whether scrobbling to Last.fm is enabled (only meaningful while a
    /// Last.fm session key exists in the Keychain).
    var scrobblingEnabled = false
    /// Starred radio stations (Shortwave's favorites), device-local.
    var radioFavorites: [RadioStation] = []
    /// Recently played radio stations, most recent first.
    var radioRecents: [RadioStation] = []
    /// User-added custom stations (a name + a raw stream URL), device-local.
    var radioCustomStations: [RadioStation] = []
    /// The app's playback volume (0...1). Optional on purpose: a
    /// preferences file written before this key existed must still
    /// decode — a missing key is an error for a synthesized `Decodable`,
    /// and that error would silently reset every other preference.
    /// `nil` means "full volume".
    var playbackVolume: Float? = nil
    /// The lyrics timing offset in seconds (BitChord's offset sheet —
    /// a provider's sync can run slightly ahead of or behind the
    /// audio). Optional on purpose like `playbackVolume`: a file
    /// written before the key existed must still decode. `nil` means
    /// "no offset".
    var lyricsOffset: TimeInterval? = nil
    /// The user's playback speed (0.5…2). Optional on purpose like
    /// `playbackVolume`: a file written before the key existed must
    /// still decode. `nil` means "normal speed". Live streams never
    /// carry it (the player pins them to 1×) — a live edge cannot be
    /// outpaced.
    var playbackRate: Float? = nil
    /// Whether scrobbles are submitted (BitChord's "scrobble tracks"
    /// switch, separate from the account being connected). Optional on
    /// purpose: `nil` means "yes" — the behaviour before the switch
    /// existed.
    var scrobbleTracks: Bool? = nil
    /// Whether the "now playing" line is pushed to the profile
    /// (BitChord's switch). Optional on purpose: `nil` means "yes".
    var scrobbleNowPlaying: Bool? = nil
    /// Whether only the first credited artist is scrobbled (BitChord's
    /// "primary artist only" — joint credits stripped). Optional on
    /// purpose: `nil` means "no".
    var scrobblePrimaryArtistOnly: Bool? = nil
    /// The shortest song that earns a scrobble, in seconds (BitChord's
    /// slider, 15…120; default 30). Optional on purpose: `nil` means
    /// 30.
    var scrobbleMinDuration: Int? = nil
    /// The share of the song that earns a scrobble (BitChord's slider,
    /// 0.1…1.0; default 0.5). Optional on purpose: `nil` means 0.5.
    var scrobbleDelayPercent: Double? = nil
    /// The cap on the scrobble delay, in seconds (BitChord's slider,
    /// 30…300; default 180). Optional on purpose: `nil` means 180.
    var scrobbleMaxDelaySeconds: Int? = nil
}

/// Reads and writes `Preferences` as JSON in Application Support.
struct PreferencesStore {
    static let fileName = "preferences.json"

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("Amphora", isDirectory: true)
        }
    }

    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Loads the preferences; a missing or unreadable file yields the
    /// defaults (fail closed, never crash).
    func load() -> Preferences {
        guard let data = try? Data(contentsOf: fileURL) else { return Preferences() }
        guard let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return preferences
    }

    /// Saves the preferences; failures are ignored (best-effort).
    func save(_ preferences: Preferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
