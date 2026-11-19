//
//  BoundedCache.swift
//  PandoraCore
//
//  A bounded in-memory cache with least-recently-used eviction.
//
//  The lyrics cache was the last unbounded holder in the app: a plain
//  dictionary keyed by track token, one entry per song heard, nothing
//  ever evicting it — the same long-session growth the artwork cache's
//  disk tier had before `DiskCacheBounds`. This is the in-memory
//  counterpart: a count ceiling, the least recently used entry falling
//  off first. A read or an update counts as use, so the songs the user
//  actually revisits survive and the once-heard ones go.
//
//  Pure Foundation, no platform dependency — like `PlayHistory`'s trim,
//  portable to a future Android port. Deliberately simple: the ceiling
//  is small (hundreds), so the O(capacity) recency bookkeeping costs
//  nothing.
//

import Foundation

/// A bounded key-value cache that keeps the most recently used entries.
public struct BoundedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {

    /// The most entries the cache holds. An init ceiling below 1 is
    /// clamped to 1 — a cache that holds nothing is not a cache.
    public let capacity: Int

    /// The cached values.
    private var entries: [Key: Value] = [:]

    /// The keys, least recently used first.
    private var order: [Key] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// How many entries the cache holds.
    public var count: Int { entries.count }

    /// Whether the cache is empty.
    public var isEmpty: Bool { entries.isEmpty }

    /// Reads a value (counting as a use — the entry becomes the most
    /// recently used) and writes one (also counting as a use); `nil` on
    /// the write removes the entry, `Dictionary`-style.
    public subscript(key: Key) -> Value? {
        mutating get {
            guard let value = entries[key] else { return nil }
            touch(key)
            return value
        }
        set {
            guard let newValue else {
                removeValue(forKey: key)
                return
            }
            store(newValue, for: key)
        }
    }

    /// Empties the cache.
    public mutating func removeAll() {
        entries = [:]
        order = []
    }

    /// Stores a value, counting as a use, and evicts the least recently
    /// used entries until the cache fits its ceiling.
    public mutating func store(_ value: Value, for key: Key) {
        entries[key] = value
        touch(key)
        trim()
    }

    /// Removes one entry.
    public mutating func removeValue(forKey key: Key) {
        entries.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    /// Moves a key to the most recently used end.
    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    /// Evicts from the least recently used end until the cache fits.
    private mutating func trim() {
        while order.count > capacity {
            let oldest = order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}
