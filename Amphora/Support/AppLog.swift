//
//  AppLog.swift
//  Amphora
//
//  Process-wide logging. The app previously logged nothing at all, which
//  made a device-side crash ("the app disappears a few seconds after I
//  press play") impossible to diagnose — there was nothing to paste.
//  Everything now flows through here:
//
//  - **`os.Logger`** — the unified system log (Console.app / `log stream`),
//    one logger per category.
//  - **A bounded ring buffer** — the most recent lines in memory.
//  - **A log file** — the buffer mirrored to Application Support on a
//    short debounce, so a hard crash still leaves the last seconds of
//    lines on disk for the in-app Diagnostics screen.
//  - **A raw-memory crash tail** — the same tail mirrored into memory the
//    crash handler can write from (`CrashReporter`).
//
//  Redaction is part of the contract: nothing secret reaches the log.
//  URLs are reduced to scheme + host + path — Pandora's query strings
//  carry signed stream/image tokens; credentials and auth tokens are
//  never logged.
//

import Foundation
import os

enum AppLog {
    enum Category: String, CaseIterable {
        case app
        case playback
        case artwork
        case network
        case lyrics
    }

    private static let subsystem = "dev.personal.amphora"

    /// Seconds since launch, used to prefix each buffered line — after a
    /// crash, "crashed 4.2s after play" is exactly what we need.
    private static let startedAt = Date()

    private static let loggers: [Category: Logger] = Dictionary(
        uniqueKeysWithValues: Category.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        }
    )

    /// An informational line (also `notice` in the system log).
    static func info(_ message: String, _ category: Category = .app) {
        loggers[category]?.notice("\(message, privacy: .public)")
        LogBuffer.shared.append(level: "I", category: category, message: message)
    }

    /// A recoverable failure (also `error` in the system log).
    static func error(_ message: String, _ category: Category = .app) {
        loggers[category]?.error("\(message, privacy: .public)")
        LogBuffer.shared.append(level: "E", category: category, message: message)
    }

    /// A verbose line — kept in the buffer for the Diagnostics screen,
    /// `debug` in the system log (not persisted there by default).
    static func debug(_ message: String, _ category: Category = .app) {
        loggers[category]?.debug("\(message, privacy: .public)")
        LogBuffer.shared.append(level: "D", category: category, message: message)
    }

    /// The buffered log as one block of text (for copy/share).
    static func text() -> String {
        LogBuffer.shared.joinedText()
    }

    /// Forces the buffered lines to disk now (Diagnostics refresh).
    static func flushNow() {
        LogBuffer.shared.flushToDisk()
    }

    /// A URL reduced to scheme + host + path. Pandora's query strings
    /// carry signed tokens — the query never reaches the log.
    static func redactedURL(_ url: URL) -> String {
        let scheme = url.scheme ?? ""
        let host = url.host ?? ""
        return "\(scheme)://\(host)\(url.path)"
    }

    /// The same reduction for a raw URL string (returns the input's
    /// scheme/host/path only; unparseable strings become `<url>`).
    static func redactedURL(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return "<url>" }
        return redactedURL(url)
    }

    /// Seconds since launch, for log lines.
    static func elapsed() -> String {
        String(format: "%.1f", Date().timeIntervalSince(startedAt))
    }
}

/// The bounded in-memory log plus its disk mirror. All methods are
/// synchronous and take the lock inside sync helpers only (NSLock is
/// unavailable from async contexts — see the project's Swift 6 notes).
private final class LogBuffer: @unchecked Sendable {
    static let shared = LogBuffer()

    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity = 400
    private var dirty = false
    private var flushTask: Task<Void, Never>?

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Amphora", isDirectory: true)
            .appendingPathComponent("amphora.log", isDirectory: false)
    }()

    func append(level: String, category: AppLog.Category, message: String) {
        store(level: level, category: category, message: message)
        scheduleFlush()
    }

    func joinedText() -> String {
        snapshot().joined(separator: "\n")
    }

    func flushToDisk() {
        let text = snapshot().joined(separator: "\n")
        write(text)
    }

    // MARK: - Internals (sync, locked)

    private func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    private func store(level: String, category: AppLog.Category, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "[\(String(format: "%6.1f", Date().timeIntervalSince1970 - AppLog.startedAt.timeIntervalSince1970))] \(level)/\(category.rawValue): \(message)"
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        dirty = true
        // The crash tail only needs the most recent lines.
        let tail = lines.suffix(24).joined(separator: "\n")
        CrashReporter.setCrashTail(tail)
    }

    private func scheduleFlush() {
        lock.lock()
        if flushTask != nil {
            lock.unlock()
            return
        }
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(2))
            LogBuffer.shared.flushToDisk()
            LogBuffer.shared.clearFlushTask()
        }
        flushTask = task
        lock.unlock()
    }

    private func clearFlushTask() {
        lock.lock()
        dirty = false
        flushTask = nil
        lock.unlock()
    }

    private func write(_ text: String) {
        lock.lock()
        let isDirty = dirty
        lock.unlock()
        guard isDirty else { return }
        let directory = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? text.write(to: Self.fileURL, atomically: true, encoding: .utf8)
        lock.lock()
        dirty = false
        lock.unlock()
    }
}
