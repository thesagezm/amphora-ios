//
//  DiskCacheBounds.swift
//  PandoraCore
//
//  The eviction rule for a disk cache — the bytes Amphora writes to
//  `Caches/` (today: artwork) and nothing ever removes.
//
//  A long session (Station Thumb, a few hundred stations, hours of
//  radio) grows such a directory without limit: the memory tier evicts
//  under pressure, the disk tier does not. This type is the missing
//  half — a *decision* about what to delete, with no file system and no
//  platform dependency, so it can be unit-tested here and reused by a
//  future Android port.
//
//  The rule is deliberately simple and deterministic:
//
//  1. **Age first.** A file older than `maxAge` is removed whatever its
//     size — stale artwork is never worth keeping.
//  2. **Size second.** While the cache is over `byteLimit`, the oldest
//     remaining files are removed until it is under the limit.
//
//  "Oldest" means the file's modification date (when it was written);
//  ties are broken by name, so the plan is reproducible.
//
//  The caller does the I/O: it keeps a running byte total so it does
//  not have to sweep the directory on every write, asks this type for a
//  plan when the total crosses the limit, and deletes the files the
//  plan names.
//

import Foundation

/// The bounds a disk cache is kept within, and the rule that decides
/// which of its files go when it outgrows them.
public struct DiskCacheBounds: Equatable, Sendable {

    /// One file in the cache.
    public struct Entry: Equatable, Sendable {
        /// The file's name (its key in the cache directory).
        public let name: String
        /// The file's size in bytes.
        public let byteCount: Int
        /// When the file was last written.
        public let modifiedAt: Date

        public init(name: String, byteCount: Int, modifiedAt: Date) {
            self.name = name
            self.byteCount = max(0, byteCount)
            self.modifiedAt = modifiedAt
        }
    }

    /// The ceiling for the cache's total size, in bytes. Zero (or less)
    /// means the cache is not bounded by size — the age rule alone applies.
    public let byteLimit: Int

    /// The ceiling for a file's age, in seconds. `nil` means files never
    /// expire by age.
    public let maxAge: TimeInterval?

    public init(byteLimit: Int, maxAge: TimeInterval? = nil) {
        self.byteLimit = max(0, byteLimit)
        self.maxAge = maxAge
    }

    /// The cache's total size in bytes.
    public static func totalBytes(of entries: [Entry]) -> Int {
        entries.reduce(into: 0) { total, entry in
            total += entry.byteCount
        }
    }

    /// Whether a file is past the age ceiling. A file exactly at
    /// `maxAge` is still in date; the ceiling is crossed, not reached.
    public func isExpired(_ entry: Entry, now: Date = Date()) -> Bool {
        guard let maxAge else { return false }
        return now.timeIntervalSince(entry.modifiedAt) > maxAge
    }

    /// The files to delete, oldest first.
    ///
    /// The plan removes every expired file, and then — while the cache
    /// is still over its size ceiling — the oldest remaining files, until
    /// the total is back under the limit. Files that survive are not
    /// in the plan.
    public func evictionPlan(entries: [Entry], now: Date = Date()) -> [Entry] {
        let ordered = entries.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
            return lhs.name < rhs.name
        }

        var doomed: [Entry] = []
        var remainingBytes = Self.totalBytes(of: ordered)

        for entry in ordered {
            if isExpired(entry, now: now) {
                doomed.append(entry)
                remainingBytes -= entry.byteCount
                continue
            }
            if byteLimit > 0, remainingBytes > byteLimit {
                doomed.append(entry)
                remainingBytes -= entry.byteCount
            }
        }
        return doomed
    }

    /// Whether the cache needs a sweep: it is over its size ceiling, or
    /// its oldest file is past the age ceiling.
    ///
    /// The caller uses this as the cheap trigger — it answers from the
    /// running byte total and the oldest file's date, so the common case
    /// (a cache comfortably inside its bounds) costs no file-system work.
    public func needsSweep(
        totalBytes: Int,
        oldestModifiedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        if byteLimit > 0, totalBytes > byteLimit { return true }
        if let oldestModifiedAt, let maxAge,
           now.timeIntervalSince(oldestModifiedAt) > maxAge {
            return true
        }
        return false
    }
}
