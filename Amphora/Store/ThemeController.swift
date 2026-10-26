//
//  ThemeController.swift
//  Amphora
//
//  Owns the user's theme choices (background appearance + accent) and
//  persists them. The theme lives in its own file, deliberately outside
//  `Preferences` — `AppStore` round-trips the whole `Preferences` struct
//  on every save, so a second writer there would clobber whichever
//  saved last.
//

import Foundation
import Observation
import SwiftUI

/// The two user-selectable pieces, as one value so a change is a single
/// observable write.
struct ThemeSelection: Equatable, Sendable {
    var appearance: ThemeAppearance = .dark
    var accent: ThemeAccent = .gold
}

@MainActor
@Observable
final class ThemeController {
    static let shared = ThemeController()

    /// The user's choice, as stored. `appearance` may be `.system`, which
    /// is resolved against `systemIsLight` before the tokens are read.
    private(set) var selection: ThemeSelection

    /// Whether the device is currently in light mode. Written by the
    /// root view from SwiftUI's `colorScheme` environment value.
    private(set) var systemIsLight = false

    /// The concrete appearance behind the user's choice: `.system`
    /// resolves to Daylight (light) or Amphora Dark (dark).
    var resolvedAppearance: ThemeAppearance {
        guard selection.appearance == .system else { return selection.appearance }
        return systemIsLight ? .daylight : .dark
    }

    /// The selection with the appearance resolved.
    var resolvedSelection: ThemeSelection {
        ThemeSelection(appearance: resolvedAppearance, accent: selection.accent)
    }

    /// The color scheme the app's surfaces are built for. `nil` means
    /// "follow the system" — used when the user picked `.system`.
    var preferredColorScheme: ColorScheme? {
        guard selection.appearance != .system else { return nil }
        return resolvedAppearance.isLight ? .light : .dark
    }

    private let store: ThemeDiskStore

    private init(store: ThemeDiskStore = ThemeDiskStore()) {
        self.store = store
        self.selection = store.load()
    }

    func setAppearance(_ appearance: ThemeAppearance) {
        guard selection.appearance != appearance else { return }
        selection.appearance = appearance
        store.save(selection)
    }

    func setAccent(_ accent: ThemeAccent) {
        guard selection.accent != accent else { return }
        selection.accent = accent
        store.save(selection)
    }

    /// Records the device's current appearance. Called by the root view
    /// whenever SwiftUI's `colorScheme` environment value changes.
    func setSystemColorScheme(isLight: Bool) {
        guard systemIsLight != isLight else { return }
        systemIsLight = isLight
    }
}

/// `theme.json` in Application Support/Amphora — fail-closed to the
/// defaults on any read/decode problem, best-effort writes.
private struct ThemeDiskStore {
    private static let fileName = "theme.json"

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("Amphora", isDirectory: true)
        fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    private struct Stored: Codable {
        var appearance: String
        var accent: String
    }

    func load() -> ThemeSelection {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return ThemeSelection()
        }
        var selection = ThemeSelection()
        if let appearance = ThemeAppearance(rawValue: stored.appearance) {
            selection.appearance = appearance
        }
        if let accent = ThemeAccent(rawValue: stored.accent) {
            selection.accent = accent
        }
        return selection
    }

    func save(_ selection: ThemeSelection) {
        let stored = Stored(
            appearance: selection.appearance.rawValue,
            accent: selection.accent.rawValue
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
