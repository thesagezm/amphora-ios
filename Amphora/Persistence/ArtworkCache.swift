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
//  Three details matter for real Pandora artwork URLs:
//
//  - **Decoding is bounded.** Song (`albumArtUrl`) and station art can be
//    served far larger than any slot shows them. Decoding at full size
//    built one multi-megabyte bitmap per consumer (mini player, full
//    player, lock screen, history rows) — on a device that memory spike
//    right after playback starts was enough to get the process killed.
//    Every image is decoded straight to a capped pixel size with ImageIO;
//    no full-size bitmap is ever built.
//  - **Every URL is tried in more than one form.** Pandora's artwork
//    URLs are sometimes scheme-less, and an internet-radio station's
//    favicon often lives on a host that serves nothing but plain HTTP.
//    The candidate list comes from `ArtworkURLCandidates` (PandoraCore):
//    the HTTPS-preferred form first, the URL exactly as it was given
//    second — so an HTTP-only favicon is actually attempted over HTTP.
//    (Before this, the "raw" URL was upgraded to HTTPS as well, which
//    made the fallback a no-op and left those stations without art.)
//    Every attempt is logged with the HTTP status so a missing artwork
//    is diagnosable from the log.
//  - **Disk file names are a SHA-256 digest**, not the base64 URL. A raw
//    base64 name can exceed the file-system name limit for long signed
//    image URLs (Amazon URLs carry a long `?token=`), which made every
//    write fail and forced a re-download on every appearance.
//

import CryptoKit
import Foundation
import ImageIO
import PandoraCore
import UIKit

/// Two-tier artwork cache: an in-memory NSCache of decoded images plus a
/// disk cache of the raw bytes.
actor ArtworkCache {
    static let shared = ArtworkCache()

    /// Cap on the decoded image's larger dimension. The full player shows
    /// artwork at up to ~400 pt (1200 px at 3×) — everything above that is
    /// waste.
    private static let maxPixelSize: CGFloat = 1200

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

    /// Returns the cached image for a raw artwork URL (Pandora's
    /// `albumArtUrl` / `artUrl` strings — normalization and fallback
    /// candidates are handled here). `nil` when the artwork cannot be
    /// loaded; callers fall back to a placeholder.
    func image(for rawArtworkURL: String) async -> UIImage? {
        let candidates = Self.candidateURLs(for: rawArtworkURL)
        // Key on the first (normalized) candidate so every consumer of
        // the same artwork shares one memory/disk/in-flight entry.
        guard let key = candidates.first?.absoluteString else {
            AppLog.debug("artwork URL unusable: \(rawArtworkURL.prefix(48))…", .artwork)
            return nil
        }

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let image = Self.readFromDisk(key: key, directory: directory) {
            memory.setObject(image, forKey: key as NSString, cost: Self.imageCost(image))
            return image
        }

        if let task = inFlight[key] {
            return await task.value
        }

        // The task runs on the actor; the download suspends it while it
        // waits, so other requests keep flowing.
        let task = Task<UIImage?, Never> { [directory] in
            guard let (image, data) = await Self.fetchImage(from: candidates) else { return nil }
            Self.writeToDisk(data: data, key: key, directory: directory)
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: Self.imageCost(image))
        }
        return image
    }

    /// Downloads and decodes one image, trying each candidate URL in
    /// order. A `User-Agent` is sent because some artwork CDNs reject
    /// requests without one.
    private static func fetchImage(from candidates: [URL]) async -> (UIImage, Data)? {
        for url in candidates {
            if Task.isCancelled { return nil }
            var request = URLRequest(url: url)
            // Same shared default as the core transports: without an
            // explicit interval a bare request can hang for days on a
            // connection that was accepted but never answers, and every
            // artwork surface (rows, mini player, full player, lock
            // screen) would sit on a placeholder with no route to a
            // retry.
            request.timeoutInterval = NetworkDefaults.requestTimeoutInterval
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            request.setValue("Amphora", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                guard (200..<300).contains(http.statusCode) else {
                    AppLog.debug(
                        "artwork HTTP \(http.statusCode) from \(AppLog.redactedURL(url))",
                        .artwork
                    )
                    continue
                }
                if let image = decodedImage(from: data) {
                    AppLog.info(
                        "artwork ok: \(AppLog.redactedURL(url)) "
                            + "(\(data.count) bytes → \(Int(image.size.width))×\(Int(image.size.height)))",
                        .artwork
                    )
                    return (image, data)
                }
                AppLog.debug(
                    "artwork did not decode from \(AppLog.redactedURL(url)) (\(data.count) bytes)",
                    .artwork
                )
            } catch {
                if Task.isCancelled { return nil }
                AppLog.debug(
                    "artwork fetch failed from \(AppLog.redactedURL(url)): \(String(describing: error))",
                    .artwork
                )
            }
        }
        AppLog.error("artwork unavailable from \(candidates.count) URL candidate(s)", .artwork)
        return nil
    }

    /// Decodes image data at a bounded pixel size (ImageIO thumbnail
    /// path): the bitmap is built at the target size, never at the
    /// source's full dimensions.
    private static func decodedImage(from data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - URL handling

    /// The URLs to try, best first: the HTTPS-preferred form of the raw
    /// string, then the string exactly as it was given (scheme
    /// preserved) — the last-resort candidate for radio favicons on
    /// hosts that serve nothing but cleartext.
    ///
    /// The list itself lives in `PandoraCore` (`ArtworkURLCandidates`),
    /// so every Amphora port builds the same candidates.
    static func candidateURLs(for raw: String) -> [URL] {
        ArtworkURLCandidates.candidates(for: raw)
    }

    // MARK: - Disk tier

    /// Stable, short file name for a URL (SHA-256 hex). Independent of
    /// the URL's length, its query string and its path separators.
    static func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileURL(for key: String, in directory: URL) -> URL {
        directory.appendingPathComponent(fileName(for: key), isDirectory: false)
    }

    private static func readFromDisk(key: String, directory: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(for: key, in: directory)) else { return nil }
        return decodedImage(from: data)
    }

    private static func writeToDisk(data: Data, key: String, directory: URL) {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL(for: key, in: directory), options: .atomic)
    }
    /// Approximate memory cost of an image (w × h × 4 bytes).
    private static func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    // MARK: - Housekeeping

    /// How many bytes the disk tier occupies. Reported in Settings so the
    /// user can see what the cache costs before clearing it.
    func diskUsage() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(into: 0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
    }

    /// Empties both tiers: the decoded images and the cached bytes on
    /// disk. In-flight downloads are cancelled, so the next request for
    /// an image fetches it again. Nothing else in the app depends on the
    /// cache — it is a pure accelerator.
    func clear() {
        memory.removeAllObjects()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
        AppLog.info("artwork cache cleared", .artwork)
    }
}
