//
//  MusixmatchLyrics.swift
//  PandoraCore
//
//  Word-exact lyrics from Musixmatch's web API — the provider that
//  turns the swept line from an interpolation into a real wavefront.
//
//  The protocol is derived from BitChord's GPL-3 client
//  (shared/.../data/lyrics/Musixmatch.kt), the reference the project
//  names for rich-sync sources; nothing is guessed. The flow:
//
//   1. `token.get` — a per-device token for a random GUID, issued
//      behind a signed request.
//   2. `track.search` — up to ten candidates for the title/artist,
//      scored on title match, artist match and duration proximity;
//      the best is trusted only above a floor (a match that failed
//      title, artist *and* duration is refused, never guessed).
//   3. `track.richsync.get` — the word-timed tier. Its body is a JSON
//      array of lines `{ts, te, x, l: [{c, o}]}` — fragments carry
//      their own spacing, which is the only thing saying where a word
//      stops; a run that neither ends in whitespace nor is followed by
//      whitespace continues the word in hand. Han, kana, Thai and
//      full-width scripts are written without spaces at all, so their
//      fragments stay words of their own.
//   4. `track.subtitle.get` — the line-timed fallback, converted to
//      LRC and parsed by the shared parser.
//
//  Every API request is signed: `<normalized url><UTC yyyyMMdd>` with
//  HMAC-SHA256 and a secret the web client rotates — read from the
//  page's application script when reachable, a static fallback
//  otherwise. A 401/402 inside a successful HTTP response means the
//  token expired: both moving credentials refresh and the request
//  retries once — the same retry-once semantics the session manager
//  applies to Pandora.
//
//  Failures are quiet by design: the provider throws, the chain
//  falls through to lrclib, and nothing in the UI changes.
//

import CryptoSwift
import Foundation

public struct MusixmatchLyricsProvider: LyricsProviding, Sendable {
    /// Musixmatch's web endpoints and the app identity the web client
    /// presents.
    private static let baseURL = "https://apic.musixmatch.com/ws/1.1"
    private static let appID = "mobile-app-v1.0"
    private static let searchPage = "https://www.musixmatch.com/search"
    private static let browserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    /// Used only if the public page serving the rotating key is briefly
    /// unavailable.
    private static let fallbackSigningSecret = "f09016176ba43a1cfd1031fbd6b3d26c"

    private let transport: any HTTPGETTransport
    private let credentials: Credentials

    public init(transport: any HTTPGETTransport = URLSessionGETTransport()) {
        self.transport = transport
        self.credentials = Credentials()
    }

    // MARK: - Entry point

    public func lyrics(for track: Track) async throws -> Lyrics {
        guard !track.isRadio, !track.title.isEmpty, !track.artist.isEmpty else {
            throw LyricsError.notFound
        }
        let best = try await bestTrack(
            title: track.title, artist: track.artist, seconds: track.duration
        )
        guard let best else { throw LyricsError.notFound }

        if best.hasRichSync == 1 {
            let lines = try await fetchRichSync(trackID: best.trackID)
            if lines.contains(where: \.isWordSynced) {
                return Lyrics(lines: lines)
            }
        }

        if best.hasSubtitles == 1 {
            let lrc = try await fetchSubtitleLRC(trackID: best.trackID)
            let parsed = LRC.parse(lrc)
            if parsed.isSynced {
                return parsed
            }
        }
        throw LyricsError.notFound
    }

    // MARK: - Track search

    struct CandidateTrack: Equatable {
        var trackID: Int64
        var trackName: String
        var artistName: String
        var trackLength: Int?
        var hasSubtitles: Int
        var hasRichSync: Int
    }

    private func bestTrack(title: String, artist: String, seconds: Int) async throws
        -> CandidateTrack?
    {
        let body = try await signedGet { token in
            Self.makeURL(
                path: "track.search",
                query: [
                    "q_track": title, "q_artist": artist,
                    "f_has_lyrics": "1", "s_track_rating": "desc",
                    "quorum_factor": "1", "page_size": "10", "page": "1",
                ],
                token: token
            )
        }
        let candidates = Self.decodeTrackSearch(body)
        guard let best = candidates.map(
            ({ Self.score($0, title: title, artist: artist, seconds: seconds) })
        ).enumerated().max(by: { $0.element < $1.element }), best.element >= 40 else {
            return nil
        }
        return candidates[best.offset]
    }

    /// The distrustful score: title match carries the most weight, the
    /// artist confirms, duration proximity settles ties and punishes
    /// mismatches. A candidate below 40 failed every signal — refused.
    static func score(
        _ candidate: CandidateTrack, title: String, artist: String, seconds: Int
    ) -> Double {
        var score = 0.0
        let name = candidate.trackName.trimmingCharacters(in: .whitespaces).lowercased()
        let target = title.trimmingCharacters(in: .whitespaces).lowercased()
        if name == target {
            score += 80
        } else if name.contains(target) || target.contains(name) {
            score += 40
        }
        let artistName = candidate.artistName.trimmingCharacters(in: .whitespaces).lowercased()
        if artistName.contains(artist.trimmingCharacters(in: .whitespaces).lowercased()) {
            score += 40
        }
        if let length = candidate.trackLength {
            let diff = abs(length - seconds)
            if diff <= 2 {
                score += 30
            } else if diff <= 5 {
                score += 15
            } else if diff <= 10 {
                score += 5
            } else {
                score -= 20
            }
        }
        return score
    }

    // MARK: - Rich sync

    private func fetchRichSync(trackID: Int64) async throws -> [LyricLine] {
        let body = try await signedGet { token in
            Self.makeURL(
                path: "track.richsync.get",
                query: ["track_id": String(trackID)],
                token: token
            )
        }
        return Self.parseRichSyncBody(body)
    }

    /// Decodes the rich-sync body: a JSON array of lines whose `l`
    /// fragments each carry their own text and offset from the line's
    /// start. Source order is retained — punctuation and syllable
    /// fragments may share a stamp.
    static func parseRichSyncBody(_ body: String) -> [LyricLine] {
        let entries = (try? JSONDecoder().decode([RichSyncEntry].self, from: Data(body.utf8)))
            ?? []
        return entries.compactMap { entry in
            let lineStart = entry.ts
            let lineEnd = max(lineStart, entry.te)
            let runs = timedRuns(entry: entry, lineStart: lineStart, lineEnd: lineEnd)
            let words = wordsFromRuns(runs: runs)
            let text = (entry.x ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let display = text.isEmpty
                ? words.map(\.text).joined(separator: " ")
                : text
            guard !display.isEmpty else { return nil }
            return LyricLine(
                timestamp: min(lineStart, words.first?.timestamp ?? lineStart),
                text: display,
                words: words
            )
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    private static func timedRuns(
        entry: RichSyncEntry, lineStart: TimeInterval, lineEnd: TimeInterval
    ) -> [TimedRun] {
        var runs: [TimedRun] = []
        var previousStart = lineStart
        for (index, fragment) in entry.l.enumerated() {
            guard !fragment.c.isEmpty else { continue }
            let start = max(lineStart, max(previousStart, lineStart + fragment.o))
            let next = index + 1 < entry.l.count
                ? lineStart + entry.l[index + 1].o
                : lineEnd
            runs.append(
                TimedRun(start: start, end: max(start, min(lineEnd, next)), raw: fragment.c)
            )
            previousStart = start
        }
        return runs
    }

    struct TimedRun {
        let start: TimeInterval
        let end: TimeInterval
        let raw: String
    }

    /// Glues timed runs into words, each keeping its timestamp. Every
    /// format that times syllables says which ones belong together the
    /// same way, by leaving the space out: a run that neither ends in
    /// whitespace nor is followed by a run starting with it continues
    /// the word in hand. Two cases where a missing space says nothing:
    /// Han, kana, Thai and full-width scripts are written without
    /// spaces at all (each fragment stays a word of its own), and a
    /// blank run — the lone space between words — ends the word in
    /// hand.
    static func wordsFromRuns(runs: [TimedRun]) -> [LyricWord] {
        var words: [LyricWord] = []
        var current = ""
        var start: TimeInterval = 0

        func flush() {
            guard !current.isEmpty else { return }
            words.append(LyricWord(timestamp: start, text: current))
            current = ""
        }

        for run in runs {
            let content = run.raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                flush()
                continue
            }
            let joins = !current.isEmpty
                && !run.raw.hasPrefix(" ")
                && !(current.last?.isUnspacedScript ?? false)
                && content.first?.isUnspacedScript != true
            if !joins { flush() }
            if current.isEmpty { start = run.start }
            current += content
            if run.raw.hasSuffix(" ") { flush() }
        }
        flush()
        return words
    }

    // MARK: - Line-timed fallback

    private func fetchSubtitleLRC(trackID: Int64) async throws -> String {
        let body = try await signedGet { token in
            Self.makeURL(
                path: "track.subtitle.get",
                query: ["track_id": String(trackID), "subtitle_format": "mxm"],
                token: token
            )
        }
        return Self.subtitleToLRC(body)
    }

    /// Musixmatch's `mxm` subtitle JSON, converted to LRC so the shared
    /// parser handles it — the line-timed tier never gets flattened
    /// into word data it does not have.
    static func subtitleToLRC(_ body: String) -> String {
        let lines = (try? JSONDecoder().decode([SubtitleLine].self, from: Data(body.utf8))) ?? []
        return lines.compactMap { line in
            let total = Int(line.time.total * 1_000)
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return String(
                format: "[%02d:%02d.%03d]%@",
                total / 60_000, (total / 1_000) % 60, total % 1_000, line.text
            )
        }
        .joined(separator: "\n")
    }

    // MARK: - Signed transport

    /// Signs and issues the request; a 401/402 inside a successful
    /// response refreshes both moving credentials and retries once.
    private func signedGet(
        _ buildURL: @Sendable (String) -> String
    ) async throws -> String {
        let first = try await signedAttempt(buildURL)
        if let first, !Self.looksUnauthorized(first) { return first }

        await credentials.invalidate()
        let second = try await signedAttempt(buildURL)
        guard let second else { throw LyricsError.notFound }
        return second
    }

    private func signedAttempt(
        _ buildURL: @Sendable (String) -> String
    ) async throws -> String? {
        let secret = await credentials.secret(using: self)
        guard let token = await credentials.token(using: self) else { return nil }
        return try await apiGet(Self.sign(url: buildURL(token), secret: secret, date: Self.utcDate()))
    }

    /// `<normalized url><UTC yyyyMMdd>` with HMAC-SHA256, matching the
    /// current web client. The normalized URL carries its spaces as
    /// `+`; the base64 signature rides percent-encoded with the
    /// protocol named alongside.
    static func sign(url: String, secret: String, date: String) -> String {
        let normalized = url
            .replacingOccurrences(of: "%20", with: "+")
            .replacingOccurrences(of: " ", with: "+")
        let mac = HMAC(key: Array(secret.utf8), variant: .sha256)
        let raw = try? mac.authenticate(Array("\(normalized)\(date)".utf8))
        let signature = Data(raw ?? []).base64EncodedString()
        let encoded = signature.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? signature
        return "\(normalized)&signature=\(encoded)&signature_protocol=sha256"
    }

    static func utcDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    /// Musixmatch reports an expired token inside a successful HTTP
    /// response.
    static func looksUnauthorized(_ body: String) -> Bool {
        guard let envelope = try? JSONDecoder().decode(
            StatusEnvelope.self, from: Data(body.utf8)
        ) else { return false }
        return envelope.message.header.status_code == 401
            || envelope.message.header.status_code == 402
    }

    static func makeURL(path: String, query: [String: String], token: String) -> String {
        var items = query.map { parameter in
            "\(parameter.key)=\(Self.encodeQuery(parameter.value))"
        }
        items.insert("app_id=\(appID)&format=json", at: 0)
        items.append("usertoken=\(Self.encodeQuery(token))")
        return "\(baseURL)/\(path)?\(items.joined(separator: "&"))"
    }

    private static func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? value
    }

    private func apiGet(_ url: String) async throws -> String {
        guard let requestURL = URL(string: url) else { throw LyricsError.notFound }
        let data = try await transport.get(
            url: requestURL,
            headers: [
                "User-Agent": Self.browserAgent,
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "en-US,en;q=0.9",
            ]
        )
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Moving credentials

    /// The token and the signing secret, cached across calls. The
    /// secret is read from the JavaScript the search page links: the
    /// web client embeds it base64-reversed behind a `_app-*.js` chunk.
    /// When the page or its script cannot be read, the static fallback
    /// signs instead — a brief outage must not disable the provider.
    /// Concurrent first calls may both fetch; the fetches are
    /// idempotent and the last write wins.
    actor Credentials {
        private var secret: String?
        private var token: String?
        private let guid = UUID().uuidString

        func secret(using provider: MusixmatchLyricsProvider) async -> String {
            if let secret { return secret }
            let fresh = await provider.readSecretFromWebPage()
                ?? MusixmatchLyricsProvider.fallbackSigningSecret
            secret = fresh
            return fresh
        }

        func token(using provider: MusixmatchLyricsProvider) async -> String? {
            if let token { return token }
            guard let fresh = await provider.fetchToken(guid: guid) else { return nil }
            token = fresh
            return fresh
        }

        func invalidate() {
            token = nil
            secret = nil
        }
    }

    func readSecretFromWebPage() async -> String? {
        // Compile-checked literals, evaluated at the call site (the
        // toolchain's Regex type is not Sendable for static storage).
        let appScriptPattern = #/src=["']([^"']*_next/static/chunks/pages/_app-[^"']+\.js)["']/#
        let encodedSecretPattern = #/from\(\s*["']([^"']+)["']\s*\.split/#
        guard
            let page = try? await browserGet(
                url: Self.searchPage,
                accept: "text/html,application/xhtml+xml",
                cookie: "mxm_bab=AB"
            ),
            let scriptPath = page.firstMatch(of: appScriptPattern)?.1,
            let scriptURL = URL(string: Self.resolve(path: String(scriptPath))),
            let javascript = try? await browserGet(
                url: scriptURL.absoluteString, accept: "*/*", cookie: nil
            ),
            let encoded = javascript.firstMatch(of: encodedSecretPattern)?.1
        else { return nil }
        let reversed = String(encoded.reversed())
        guard let data = Data(base64Encoded: reversed) else { return nil }
        let decoded = String(decoding: data, as: UTF8.self)
        return decoded.isEmpty ? nil : decoded
    }

    func fetchToken(guid: String) async -> String? {
        guard let body = try? await apiGet(
            Self.sign(
                url: Self.makeURL(path: "token.get", query: ["guid": guid], token: ""),
                secret: await credentials.secret(using: self),
                date: Self.utcDate()
            )
        ) else { return nil }
        let envelope = try? JSONDecoder().decode(TokenEnvelope.self, from: Data(body.utf8))
        return envelope?.message.body?.user_token
    }

    private func browserGet(url: String, accept: String, cookie: String?) async throws -> String {
        guard let requestURL = URL(string: url) else { throw LyricsError.notFound }
        var headers = [
            "User-Agent": Self.browserAgent,
            "Accept": accept,
            "Accept-Language": "en-US,en;q=0.9",
        ]
        if let cookie { headers["Cookie"] = cookie }
        let data = try await transport.get(url: requestURL, headers: headers)
        return String(decoding: data, as: UTF8.self)
    }

    static func resolve(path: String) -> String {
        if path.hasPrefix("http") { return path }
        return "https://www.musixmatch.com" + (path.hasPrefix("/") ? path : "/" + path)
    }

    // MARK: - Wire shapes

    struct StatusEnvelope: Decodable {
        struct Message: Decodable { let header: Header }
        struct Header: Decodable { let status_code: Int }
        let message: Message
    }

    struct TokenEnvelope: Decodable {
        struct Header: Decodable { let status_code: Int }
        struct Body: Decodable { let user_token: String }
        let message: Message
        struct Message: Decodable { let body: Body? }
    }

    struct TrackSearchEnvelope: Decodable {
        let message: Message
        struct Message: Decodable { let body: Body? }
        struct Body: Decodable { let track_list: [Wrapper]? }
        struct Wrapper: Decodable { let track: CandidateDecodable }
        struct CandidateDecodable: Decodable {
            let track_id: Int64
            let track_name: String
            let artist_name: String?
            let track_length: Int?
            let has_subtitles: Int?
            let has_richsync: Int?
        }
    }

    struct RichSyncEnvelope: Decodable {
        let message: Message
        struct Message: Decodable { let body: Body? }
        struct Body: Decodable { let richsync: RichSync? }
        struct RichSync: Decodable { let richsync_body: String? }
    }

    struct SubtitleEnvelope: Decodable {
        let message: Message
        struct Message: Decodable { let body: Body? }
        struct Body: Decodable { let subtitle: Subtitle? }
        struct Subtitle: Decodable { let subtitle_body: String? }
    }

    struct RichSyncEntry: Decodable {
        /// Line start, seconds.
        let ts: TimeInterval
        /// Line end, seconds.
        let te: TimeInterval
        /// The line text.
        let x: String?
        /// Timed fragments: `c` is the text, `o` the offset from `ts`.
        let l: [Fragment]

        struct Fragment: Decodable {
            let c: String
            let o: TimeInterval
        }
    }

    struct SubtitleLine: Decodable {
        let text: String
        let time: SubtitleTime
        struct SubtitleTime: Decodable { let total: TimeInterval }
    }

    /// The `track.search` decode, flattened to the fields the scoring
    /// needs.
    static func decodeTrackSearch(_ body: String) -> [CandidateTrack] {
        guard
            let envelope = try? JSONDecoder().decode(
                TrackSearchEnvelope.self, from: Data(body.utf8)
            ),
            let list = envelope.message.body?.track_list
        else { return [] }
        return list.map { wrapper in
            CandidateTrack(
                trackID: wrapper.track.track_id,
                trackName: wrapper.track.track_name,
                artistName: wrapper.track.artist_name ?? "",
                trackLength: wrapper.track.track_length,
                hasSubtitles: wrapper.track.has_subtitles ?? 0,
                hasRichSync: wrapper.track.has_richsync ?? 0
            )
        }
    }
}

private extension Character {
    /// Scripts written without spaces between words — a missing space
    /// there is not a decision about words.
    var isUnspacedScript: Bool {
        switch self {
        case "\u{3400}"..."\u{9FFF}", // Han
             "\u{3040}"..."\u{30FF}", // hiragana and katakana
             "\u{3000}"..."\u{303F}", // CJK punctuation
             "\u{FF00}"..."\u{FFEF}", // full-width forms
             "\u{0E00}"..."\u{0E7F}": // Thai
            return true
        default:
            return false
        }
    }
}

private extension LyricLine {
    /// The line carries word timings worth rendering.
    var isWordSynced: Bool { !(words ?? []).isEmpty }
}
