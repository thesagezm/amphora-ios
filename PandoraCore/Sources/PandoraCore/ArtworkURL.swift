//
//  ArtworkURL.swift
//  PandoraCore
//
//  Candidate URLs for one artwork reference.
//
//  Pandora and the internet-radio directory hand out artwork URLs from
//  very different worlds:
//
//  - Pandora's `albumArtUrl` / `artUrl` are HTTPS, but some entries
//    arrive scheme-less or with a stray space that the URL parser
//    rejects.
//  - A radio station's favicon lives on whatever host the station
//    happens to run — very often a plain-HTTP host that serves no TLS
//    at all (checked live against radio-browser: a good share of the
//    favicons are `http://`, and some stations have none).
//
//  The candidate list is therefore "HTTPS first, the URL exactly as
//  given second". The second candidate is the important one: an
//  HTTP-only favicon host fails the HTTPS attempt and only answers
//  the raw URL, so the raw form must be kept intact — upgrading it
//  to HTTPS as well would leave such stations with no artwork.
//
//  Pure Foundation, no UI — this is part of the portable surface the
//  Android port mirrors.
//

import Foundation
#if canImport(FoundationNetworking)
// Linux (swift-corelibs-foundation): URLSession/URLRequest live here.
import FoundationNetworking
#endif

/// Builds the ordered list of URLs to try for one artwork reference.
public enum ArtworkURLCandidates {

    /// The URLs to try, best first:
    ///
    /// 1. the HTTPS-preferred, percent-encoded form;
    /// 2. the URL exactly as the service gave it (scheme preserved),
    ///    so an `http://` favicon is actually attempted over HTTP.
    ///
    /// Duplicates are removed, so an already-HTTPS URL yields a single
    /// candidate and a scheme-less URL yields one candidate as well.
    public static func candidates(for raw: String) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []

        func add(_ url: URL?) {
            guard let url, !seen.contains(url.absoluteString) else { return }
            seen.insert(url.absoluteString)
            urls.append(url)
        }

        add(httpsPreferredURL(from: raw))
        add(rawURL(from: raw))
        return urls
    }

    /// The scheme-normalized, percent-encoded, HTTPS-preferred URL:
    ///
    /// - a missing scheme becomes `https://` (Pandora's artwork URLs
    ///   are not always absolute);
    /// - an `http://` URL is upgraded to `https://` — every Pandora
    ///   artwork host serves TLS, and cleartext is blocked by ATS
    ///   unless the app opts out;
    /// - characters a URL parser rejects (spaces, quotes) are
    ///   percent-encoded instead of making the whole URL unusable.
    public static func httpsPreferredURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        let hasScheme = lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
        let withScheme = hasScheme ? trimmed : "https://" + trimmed

        guard var components = URLComponents(string: withScheme) else {
            // The string contains characters `URLComponents` rejects
            // (spaces are the common one) — encode them and retry.
            guard let encoded = withScheme.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
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

    /// The URL exactly as provided, scheme preserved — `http://` stays
    /// `http://`. This is the last-resort candidate for radio favicons
    /// on hosts that serve nothing but cleartext. Nil when the string
    /// carries no scheme (there is nothing to preserve) or cannot be
    /// parsed even after encoding.
    public static func rawURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let isHTTP = lowercased.hasPrefix("http://")
        guard isHTTP || lowercased.hasPrefix("https://") else { return nil }

        guard var components = URLComponents(string: trimmed) else {
            guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
                  var retry = URLComponents(string: encoded) else { return nil }
            retry.scheme = isHTTP ? "http" : "https"
            return retry.url
        }
        components.scheme = isHTTP ? "http" : "https"
        if let host = components.host, host.isEmpty {
            return nil
        }
        return components.url
    }

    /// Host + path + query + fragment characters, minus the space that
    /// makes `URLComponents` reject the string outright. The percent
    /// sign is allowed explicitly so an already-escaped URL (`%20`,
    /// `%2F` — signed CDN paths carry them) is not encoded a second
    /// time when the space-repair path runs.
    private static let allowedCharacters: CharacterSet = {
        CharacterSet.urlHostAllowed
            .union(.urlPathAllowed)
            .union(.urlQueryAllowed)
            .union(.urlFragmentAllowed)
            .union(CharacterSet(charactersIn: "%"))
            .subtracting(CharacterSet(charactersIn: " "))
    }()
}
