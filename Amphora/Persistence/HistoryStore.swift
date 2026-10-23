//
//  HistoryStore.swift
//  Amphora
//
//  Codable-to-disk persistence for the playback history (AGENTS.md:
//  "SwiftData or Codable-to-disk for preferences, station order, history").
//  The file lives in Application Support — no secret ever goes here.
//

import Foundation
import PandoraCore

/// Reads and writes `PlayHistory` as JSON in Application Support.
struct HistoryStore {
    /// File name inside the history directory.
    static let fileName = "history.json"

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

    /// Loads the history; a missing or unreadable file yields an empty
    /// history (fail closed, never crash).
    func load() -> PlayHistory {
        guard let data = try? Data(contentsOf: fileURL) else {
            return PlayHistory()
        }
        guard let history = try? JSONDecoder().decode(PlayHistory.self, from: data) else {
            return PlayHistory()
        }
        return history
    }

    /// Saves the history; failures are ignored (history is best-effort).
    func save(_ history: PlayHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
