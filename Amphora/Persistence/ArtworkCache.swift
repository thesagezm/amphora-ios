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
//  - **The disk tier is bounded.** The memory tier evicts under pressure;
//    the disk tier had no bound at all, so a long session grew
//    `Caches/Amphora/Artwork/` without limit. The rule itself lives in
//    `PandoraCore` (`DiskCacheBounds` — pure Foundation, unit-tested
//    there): expired files go first, then the oldest files until the
//    cache is back under its ceiling. The actor keeps a running byte
//    total, so the directory is only swept when the cache has actually
//    outgrown its bounds — never on every write.
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

    /// The disk tier's ceiling: 128 MB of artwork bytes.
    ///
    /// The memory tier is bounded by `NSCache` (120 images / 64 MB) and
    /// evicts under pressure; the disk tier had no bound at all, so a
    /// long session — Station Thumb, a few hundred stations, hours of
    /// radio — grew `Caches/Amphora/Artwork/` without limit. 128 MB
    /// holds a very large library of covers while still putting a floor
    /// under the disk the app may take.
    static let diskByteLimit = 128 * 1024 * 1024

    /// Artwork older than this is dropped on the next sweep (30 days).
    /// Stale covers are never worth the space.
    static let diskMaxAge: TimeInterval = 30 * 24 * 60 * 60

    /// Decoded images, keyed by URL string. NSCache evicts under pressure
    /// — the disk tier still has the bytes, so a re-decode is cheap.
    private let memory = NSCache<NSString, UIImage>()

    /// Disk cache directory (Caches — the OS may purge it).
    private let directory: URL

    /// In-flight fetches, so N concurrent requests for the same URL cause
    /// one download.
    private var inFlight: [String: Task<(UIImage, Data)?, Never>] = [:]

    /// What the disk tier holds: every file's name, size and write date.
    ///
    /// The index is what keeps the write path free of directory
    /// listings — the ceiling is checked against the running byte total,
    /// and only a cache that has actually outgrown its bounds is swept.
    private var diskIndex: [String: DiskCacheBounds.Entry] = [:]

    /// The disk tier's running total, in bytes.
    private var diskBytes = 0

    /// The write date of the oldest file in the index — the age rule's
    /// trigger.
    private var oldestDiskDate: Date?

    /// Whether the index has been read from the directory yet.
    private var didIndexDisk = false

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
            guard let (image, _) = await task.value else { return nil }
            memory.setObject(image, forKey: key as NSString, cost: Self.imageCost(image))
            return image
        }

        // The task runs on the actor; the download suspends it while it
        // waits, so other requests keep flowing.
        let task = Task<(UIImage, Data)?, Never> {
            await Self.fetchImage(from: candidates)
        }
        inFlight[key] = task
        let fetched = await task.value
        inFlight[key] = nil
        guard let (image, data) = fetched else { return nil }
        Self.writeToDisk(data: data, key: key, directory: directory)
        // The disk tier keeps its own bounds: the write is counted, and
        // a cache that has outgrown them is swept (oldest first).
        recordDiskWrite(name: Self.fileName(for: key), byteCount: data.count)
        memory.setObject(image, forKey: key as NSString, cost: Self.imageCost(image))
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
    ///
    /// The directory is read fresh here (the Settings row asks rarely);
    /// the file system is the truth — the OS may purge `Caches/` between
    /// launches.
    func diskUsage() -> Int {
        indexDiskFromDirectory()
        return diskBytes
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
        ) else {
            diskIndex = [:]
            diskBytes = 0
            oldestDiskDate = nil
            didIndexDisk = true
            return
        }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
        diskIndex = [:]
        diskBytes = 0
        oldestDiskDate = nil
        didIndexDisk = true
        AppLog.info("artwork cache cleared", .artwork)
    }

    // MARK: - The disk tier's bounds

    /// Reads the cache directory into the index — once per launch. The
    /// index is what keeps the write path free of directory listings.
    private func indexDiskIfNeeded() {
        guard !didIndexDisk else { return }
        indexDiskFromDirectory()
    }

    /// Reads the cache directory into the index: every file's name, size
    /// and write date, plus the running byte total and the oldest date.
    private func indexDiskFromDirectory() {
        didIndexDisk = true
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        ) else {
            diskIndex = [:]
            diskBytes = 0
            oldestDiskDate = nil
            return
        }
        var index: [String: DiskCacheBounds.Entry] = [:]
        var total = 0
        var oldest: Date?
        for url in contents {
            let values = try? url.resourceValues(forKeys: keys)
            let name = url.lastPathComponent
            let size = values?.fileSize ?? 0
            let date = values?.contentModificationDate ?? Date.distantPast
            index[name] = DiskCacheBounds.Entry(
                name: name,
                byteCount: size,
                modifiedAt: date
            )
            total += size
            if let current = oldest {
                oldest = min(current, date)
            } else {
                oldest = date
            }
        }
        diskIndex = index
        diskBytes = total
        oldestDiskDate = oldest
    }

    /// Records a file just written to the disk tier, then checks whether
    /// the tier has outgrown its bounds.
    private func recordDiskWrite(name: String, byteCount: Int) {
        indexDiskIfNeeded()
        let date = Date()
        if let previous = diskIndex[name] {
            diskBytes -= previous.byteCount
        }
        diskIndex[name] = DiskCacheBounds.Entry(
            name: name,
            byteCount: byteCount,
            modifiedAt: date
        )
        diskBytes += byteCount
        if let oldest = oldestDiskDate {
            oldestDiskDate = min(oldest, date)
        } else {
            oldestDiskDate = date
        }
        sweepDiskIfNeeded()
    }

    /// Sweeps the disk tier when it has outgrown its bounds. The trigger
    /// is cheap — the running byte total and the oldest file's date — so
    /// the common case (a cache well inside its bounds) costs no
    /// file-system work at all.
    private func sweepDiskIfNeeded() {
        let bounds = DiskCacheBounds(
            byteLimit: Self.diskByteLimit,
            maxAge: Self.diskMaxAge
        )
        guard bounds.needsSweep(
            totalBytes: diskBytes,
            oldestModifiedAt: oldestDiskDate
        ) else { return }
        sweepDisk(using: bounds)
    }

    /// Deletes the files the rule names, oldest first.
    ///
    /// The rule itself lives in `PandoraCore` (`DiskCacheBounds`) — pure
    /// Foundation, so it is unit-tested there; this is the I/O half.
    private func sweepDisk(using bounds: DiskCacheBounds) {
        // The index is the trigger; the file system is the truth (the OS
        // may have purged files while the app was not running).
        indexDiskFromDirectory()
        let plan = bounds.evictionPlan(entries: Array(diskIndex.values))
        guard !plan.isEmpty else { return }
        var reclaimed = 0
        for entry in plan {
            let url = directory.appendingPathComponent(entry.name, isDirectory: false)
            do {
                try FileManager.default.removeItem(at: url)
                reclaimed += entry.byteCount
            } catch {
                // Already gone (the OS purged it) — nothing to reclaim.
            }
            diskIndex.removeValue(forKey: entry.name)
        }
        diskBytes = max(0, diskBytes - reclaimed)
        recomputeOldestDiskDate()
        AppLog.info(
            "artwork cache swept: \(plan.count) file(s), \(reclaimed) bytes reclaimed",
            .artwork
        )
    }

    /// Recomputes the oldest file's date after a sweep.
    private func recomputeOldestDiskDate() {
        oldestDiskDate = diskIndex.values.map(\.modifiedAt).min()
    }
}
