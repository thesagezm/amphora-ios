//
//  ArtworkCache.swift
//  Amphora
//
//  Decoded-artwork cache (memory + disk), per AGENTS.md performance rules:
//  "Cache decoded artwork (memory + disk); async image loading with
//  cancellation."
//
//  The cache is an actor, so concurrent requests for the same URL share
//  one fetch and one decode. Callers get a `UIImage` back; SwiftUI views
//  render it directly — no `AsyncImage` re-download per list render.
//

import Foundation
import UIKit

/// Two-tier artwork cache: an in-memory NSCache of decoded images plus a
/// disk cache of the raw bytes.
actor ArtworkCache {
    static let shared = ArtworkCache()

    /// Decoded images, keyed by URL string. NSCache evicts under pressure
    /// — the disk tier still has the bytes, so a re-decode is cheap.
    private let memory = NSCache<NSString, UIImage>()

    /// Disk cache directory (Caches — the OS may purge it).
    private let directory: URL

    /// In-flight fetches, so N concurrent requests for the same URL cause
    /// one download.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(directory: URL? = nil) {
        memory.countLimit = 120
        memory.totalCostLimit = 64 * 1024 * 1024
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = caches.appendingPathComponent("Amphora/Artwork", isDirectory: true)
        }
    }

    /// Returns the cached image for `url`, fetching it if needed.
    /// `nil` when the artwork cannot be loaded — callers fall back to a
    /// placeholder.
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let data = try? Data(contentsOf: fileURL(for: key)), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString, cost: data.count)
            return image
        }

        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task<UIImage?, Never> { [directory] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { return nil }
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try? data.write(to: Self.fileURL(for: key, in: directory), options: .atomic)
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image, let data = image.jpegData(compressionQuality: 0.9) {
            memory.setObject(image, forKey: key as NSString, cost: data.count)
        }
        return image
    }

    private func fileURL(for key: String) -> URL {
        Self.fileURL(for: key, in: directory)
    }

    /// Disk file name: a stable hash of the URL (no path separators, no
    /// query strings in the name).
    private static func fileURL(for key: String, in directory: URL) -> URL {
        let name = key.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name ?? "artwork", isDirectory: false)
    }
}
