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
//  Two details matter for real Pandora artwork URLs:
//
//  - **Plain HTTP is upgraded to HTTPS.** Pandora's playlist entries carry
//    `albumArtUrl` values that are sometimes `http://` (pithos' own mock
//    API uses `http://…` too). iOS blocks cleartext HTTP by default (ATS),
//    so those images would silently fail to load *and* never be cached.
//    Upgrading the scheme lets the same host serve over TLS.
//  - **Disk file names are a SHA-256 digest**, not the base64 URL. A raw
//    base64 name can exceed the file-system name limit for long signed
//    image URLs (Amazon URLs carry a long `?token=`), which made every
//    write fail and forced a re-download on every appearance.
//

import CryptoKit
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
        let request = Self.upgradedToHTTPS(url)
        let key = request.absoluteString

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

        // The task runs on the cooperative pool (the actor's executor),
        // never on the main thread; the download suspends the actor while
        // it waits.
        let task = Task<UIImage?, Never> { [directory] in
            guard let (image, data) = await Self.fetchImage(from: request) else { return nil }
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

    /// Downloads and decodes one image. A `User-Agent` is sent because
    /// some artwork CDNs reject requests without one, and the response
    /// is only accepted when it is a successful HTTP reply with image
    /// bytes.
    private static func fetchImage(from url: URL) async -> (UIImage, Data)? {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("Amphora", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else { return nil }
        return (image, data)
    }

    // MARK: - URL handling

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
        guard let data = try? Data(contentsOf: fileURL(for: key, in: directory)),
              let image = UIImage(data: data) else { return nil }
        return image
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
