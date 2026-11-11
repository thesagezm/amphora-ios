import Foundation
import PandoraCore

/// A read-only listener on a radio station's ICY now-playing metadata.
///
/// The station's stream carries interleaved metadata blocks
/// (`StreamTitle='Artist - Title';…`) — the protocol is derived in
/// `PandoraCore/RadioStreamMetadata.swift`, verified live against real
/// stations (Europe 1, MANGORADIO answer; France Info announces
/// nothing — no `icy-metaint`). This actor opens its **own** connection
/// to the stream URL with `Icy-MetaData: 1` and parses whatever bytes
/// arrive. The player keeps its own connection: the probe never touches
/// the audio path, it only reads along.
///
/// Consequences worth remembering:
/// - **Bandwidth**: while a station plays, the probe doubles the
///   stream's bandwidth (a second full stream connection). Acceptable —
///   and it stops the moment playback stops.
/// - **No announcements ≠ broken stream.** A station that sends no
///   `icy-metaint` is honestly reported (`announcesNothing`), not
///   retried forever.
///
/// One probe instance lives in `AppStore`; `start` swaps the station,
/// `stop` ends everything.
actor RadioMetadataProbe {
    /// What the probe learned, delivered as it learns it.
    enum Event: Sendable, Equatable {
        /// Connected; the stream announces an `icy-metaint`. A
        /// `StreamTitle` is expected but has not arrived yet.
        case listening
        /// A (new) song announcement arrived.
        case announced(RadioNowPlaying)
        /// The server sent no `icy-metaint` — this station announces
        /// nothing and can never be identified from the stream.
        case announcesNothing
    }

    private var task: Task<Void, Never>?
    /// The last announcement's raw title — a repeat of the same title
    /// (the station re-announcing) is not a new song.
    private var lastAnnouncedTitle: String?

    /// Starts (or restarts) listening to `url`. Any previous listening
    /// task is cancelled first — the probe follows the station that is
    /// playing now.
    func start(url: URL, delivering deliver: @escaping @Sendable (Event) -> Void) {
        stop()
        lastAnnouncedTitle = nil
        task = Task {
            await listen(to: url, delivering: deliver)
            // The task ends when the stream ends, the connection fails
            // or it is cancelled. A finished task is left in place until
            // the next `start`/`stop` replaces it — there is nothing to
            // clean up (the session invalidates itself), and identity
            // bookkeeping here would race a concurrent restart.
        }
    }

    /// Stops listening and drops the connection.
    func stop() {
        task?.cancel()
        task = nil
        lastAnnouncedTitle = nil
    }

    /// The listening loop: open the byte stream, read the interval from
    /// the headers, then feed every chunk into the core parser. Runs
    /// until cancelled, the stream ends or the connection fails — a
    /// dead server surfaces as a task that simply stopped, never as a
    /// crash, and the audio path is unaffected either way.
    private func listen(to url: URL, delivering deliver: @escaping @Sendable (Event) -> Void) async {
        let configuration = URLSessionConfiguration.default
        // A live stream runs for hours, so the *resource* timeout must
        // not bound the listening session; the *request* timeout only
        // bounds the time between data arrivals, so a dead server is
        // noticed while a paused-but-alive one is not dropped.
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            let headers = Self.stringHeaders(of: response)
            guard let interval = ICYMetadataParser.metadataInterval(in: headers) else {
                AppLog.info("radio metadata: station announces nothing", .playback)
                deliver(.announcesNothing)
                return
            }
            AppLog.debug("radio metadata: listening, interval \(interval) bytes", .playback)
            deliver(.listening)

            var parser = ICYMetadataParser()
            parser.setMetadataInterval(interval)
            for try await data in bytes {
                if Task.isCancelled { return }
                for block in parser.consume(data) {
                    guard let nowPlaying = RadioStreamMetadata.nowPlaying(in: block),
                          nowPlaying.rawTitle != lastAnnouncedTitle else { continue }
                    lastAnnouncedTitle = nowPlaying.rawTitle
                    AppLog.info(
                        "radio metadata: now playing \"\(nowPlaying.rawTitle)\"",
                        .playback
                    )
                    deliver(.announced(nowPlaying))
                }
            }
        } catch is CancellationError {
            // Normal shutdown.
        } catch {
            // A failed probe never fails the stream: the audio keeps
            // playing and the UI keeps the station's own identity. The
            // error itself is not logged — a network error's description
            // can carry the failing URL, and stream URLs must never
            // reach the log.
            AppLog.debug(
                "radio metadata: probe ended (connection failed, type \(String(describing: type(of: error))))",
                .playback
            )
        }
    }

    /// `HTTPURLResponse.allHeaderFields` is `[AnyHashable: Any]`; the
    /// core's header lookup wants flat strings. Non-string entries are
    /// skipped — the interval header is always a string.
    private static func stringHeaders(of response: URLResponse) -> [String: String] {
        guard let http = response as? HTTPURLResponse else { return [:] }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let key = key as? String, let value = value as? String else { continue }
            headers[key] = value
        }
        return headers
    }
}
