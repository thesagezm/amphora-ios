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
