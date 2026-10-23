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
//  - **Plain HTTP is upgraded to HTTPS, with a fallback.** Pandora's
//    artwork URLs are sometimes `http://` (ATS blocks cleartext) or
//    scheme-less. The normalized HTTPS URL is tried first; if it fails,
//    the raw URL is tried as-is. Every attempt is logged with the HTTP
//    status so a missing artwork is diagnosable from the log.
//  - **Disk file names are a SHA-256 digest**, not the base64 URL. A raw
//    base64 name can exceed the file-system name limit for long signed
//    image URLs (Amazon URLs carry a long `?token=`), which made every
//    write fail and forced a re-download on every appearance.
//

import CryptoKit
import Foundation
import ImageIO
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

    /// The URLs to try, best first: the normalized HTTPS form of the raw
    /// string, then the raw string itself when it is a distinct usable
    /// URL (normalization may have re-encoded something a CDN rejects).
    static func candidateURLs(for raw: String) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        func add(_ url: URL?) {
            guard let url, !seen.contains(url.absoluteString) else { return }
            seen.insert(url.absoluteString)
            urls.append(url)
        }
        add(normalizedURL(from: raw))
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http"), let direct = URL(string: trimmed) {
            add(upgradedToHTTPS(direct))
        }
        return urls
    }

    /// Turns a raw artwork URL string into a usable `URL`:
    ///
    /// - a missing scheme becomes `https://` (Pandora's `albumArtUrl`
    ///   values are not always absolute);
    /// - `http://` becomes `https://` — cleartext HTTP is blocked by ATS,
    ///   and every Pandora artwork host serves TLS;
    /// - characters a URL parser rejects (spaces, quotes) are
    ///   percent-encoded instead of making the whole URL unusable.
    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://" + trimmed
        }
        guard var components = URLComponents(string: withScheme) else {
            // The string contains characters `URLComponents` rejects
            // (spaces are the common one) — encode them and retry.
            let allowed = CharacterSet.urlHostAllowed
                .union(.urlPathAllowed)
                .union(.urlQueryAllowed)
                .union(.urlFragmentAllowed)
                .subtracting(CharacterSet(charactersIn: " "))
            guard let encoded = withScheme.addingPercentEncoding(withAllowedCharacters: allowed),
                  var retry = URLComponents(string: encoded) else { return nil }
            retry.scheme = "https"
            return retry.url
        }
        components.scheme = "https"
        if let host = components.host, host.isEmpty {
            return nil
        }
        return components.url
    }

    /// Upgrades `http://` to `https://` — cleartext HTTP is blocked by
    /// ATS, and every Pandora artwork host serves TLS.
    static func upgradedToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
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
}
