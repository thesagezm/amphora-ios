import Observation
import PandoraCore

@MainActor
@Observable
final class AppStore {
    /// Where the app is in the auth lifecycle. Drives `RootView`'s switch.
    enum AuthPhase {
        case restoring      // warm-launch restore attempt in flight
        case signedOut
        case signingIn
        case signedIn
    }

    /// UI intents. Kept as an enum so adding an intent later never changes
    /// the UI call sites.
    enum Intent {
        case restoreSession
        case login(username: String, password: String)
        case refreshStations
        case searchStations(query: String)
        case createStation(MusicSearchResult)
        case renameStation(Station, to: String)
        case deleteStation(Station)
        case playStation(Station)
        case togglePlayback
        case skipToNext
        case refreshLyrics
        case rateCurrentTrack(FeedbackRating)
        case removeCurrentRating
        case sleepCurrentTrack
        case bookmarkCurrentSong
        case bookmarkCurrentArtist
        case refreshBookmarks
        case deleteBookmark(Bookmark)
        case setSleepTimer(SleepTimer)
        case cancelSleepTimer
        case moveStation(from: Int, to: Int)
        case dismissError
    }

    private let session: SessionManager
    private var didStartRestore = false
    private var searchTask: Task<Void, Never>?
    /// Tracks already handed to the player — the next playlist must not
    /// queue the same track twice.
    private var queuedTrackTokens: Set<String> = []

    /// Playback engine. Owns the player, the audio session and the
    /// now-playing track; it never talks to the network.
    let player: PlayerService
    /// Lock-screen / Control Center integration (now playing info +
    /// remote transport commands).
    private let nowPlaying: NowPlayingService
    /// Lyrics provider (lrclib.net). Protocol lives in PandoraCore so a
    /// stub can be injected instead.
    private let lyricsProvider: any LyricsProviding
    /// English translator for non-English lyrics (the endpoint detects the
    /// source language; `nil` result means "already English").
    private let lyricsTranslator: any LyricsTranslating

    private(set) var authPhase: AuthPhase = .restoring
    private(set) var stations: [Station] = []
    private(set) var isLoadingStations = false
    private(set) var isMutatingStations = false
    private(set) var searchResults: [MusicSearchResult] = []
    private(set) var isSearching = false
    /// Increments on each successful create — the add-station sheet's
    /// dismissal signal (fire-and-forget intents can't return a value).
    private(set) var stationCreatedTick = 0
    /// The station whose playlist is playing (nil before the first play).
    private(set) var currentStation: Station?
    /// True while a playlist request for a station is in flight.
    private(set) var isLoadingPlaylist = false
    /// Lyrics for the current track (nil while loading, before the first
    /// play, or when nothing could be fetched).
    private(set) var lyrics: Lyrics?
    private(set) var isLoadingLyrics = false
    /// Session-scoped lyrics cache keyed by `trackToken` — repeat listens
    /// don't re-hit the lyrics service. Not-found results are cached too.
    private var lyricsCache: [String: Lyrics] = [:]
    /// The in-flight lyrics fetch; cancelled when the track changes.
    private var lyricsTask: Task<Void, Never>?
    /// The in-flight translation for the current track's lyrics; cancelled
    /// when the track changes or a new lyrics fetch supersedes it.
    private var translationTask: Task<Void, Never>?
    /// The user's bookmarks (`user.getBookmarks`).
    private(set) var bookmarks: [Bookmark] = []
    private(set) var isLoadingBookmarks = false
    /// Local playback history ("recently played"), newest first.
    private(set) var history: PlayHistory = PlayHistory()
    /// The sleep timer (off by default).
    private(set) var sleepTimer: SleepTimer = .off
    /// Live status text for the sleep timer ("12 min left", "End of
    /// track", "Off"). Refreshed when the remaining minutes change, so
    /// the UI re-renders about once a minute instead of every second.
    private(set) var sleepTimerLabel: String = SleepTimer.off.label()
    /// The countdown task for a duration sleep timer. Cancelled and
    /// replaced whenever the timer changes.
    private var sleepTimerTask: Task<Void, Never>?
    /// The `feedbackId` of the rating on the current track (needed to undo
    /// it) and the rating itself.
    private(set) var currentRating: FeedbackRating = .none
    private var currentFeedbackId: String?
    /// Short confirmation of the last successful action ("Song
    /// bookmarked"), shown briefly in the player so the user can see
    /// that a button did something. Nil when there is nothing to show.
    private(set) var confirmationMessage: String?
    private var confirmationTask: Task<Void, Never>?
    // Errors surface here too.
    private(set) var lastErrorMessage: String?

    /// Disk persistence for the history (Codable-to-disk, per AGENTS.md).
    private let historyStore: HistoryStore
    /// Disk persistence for the non-secret preferences (station order,
    /// last station).
    private let preferencesStore: PreferencesStore
    private var preferences: Preferences

    init(
        session: SessionManager = SessionManager(store: KeychainSessionStore()),
        historyStore: HistoryStore = HistoryStore(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        lyricsProvider: any LyricsProviding = LRCLibClient(),
        lyricsTranslator: any LyricsTranslating = GoogleTranslateClient()
    ) {
        self.session = session
        self.historyStore = historyStore
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()
        self.lyricsProvider = lyricsProvider
        self.lyricsTranslator = lyricsTranslator
        let player = PlayerService()
        self.player = player
        self.nowPlaying = NowPlayingService(player: player)
        self.history = historyStore.load()
        // A sleep timer survives a relaunch: restore it and resume the
        // countdown if its deadline is still ahead.
        let storedTimer = preferences.sleepTimer
        if storedTimer.mode == .duration, !storedTimer.hasExpired() {
            sleepTimer = storedTimer
            sleepTimerLabel = storedTimer.label()
            startSleepTimerCountdown()
        } else if storedTimer.mode == .endOfTrack {
            sleepTimer = storedTimer
            sleepTimerLabel = storedTimer.label()
        }
        // The player asks for more tracks when its queue runs low — pithos
        // preloads the next playlist when one song remains.
        player.onNeedMoreTracks = { [weak self] in
            self?.fetchMoreTracks()
        }
        // A new track means a new rating state: the feedback id belongs to
        // the previous track (pithos keeps it per song). The rating comes
        // from the playlist entry (`songRating`).
        player.onTrackChanged.append { [weak self] track in
            guard let self else { return }
            if let track {
                AppLog.info("track started: \(track.title) — \(track.artist)", .playback)
            } else {
                AppLog.info("track queue empty", .playback)
            }
            self.currentFeedbackId = nil
            self.currentRating = Self.feedbackRating(for: track?.rating)
            // Record the play in the local history.
            if let track {
                self.history.record(track)
                self.historyStore.save(self.history)
            }
            // An "end of track" sleep timer stops playback here.
            if self.sleepTimer.mode == .endOfTrack, track != nil {
                self.fireSleepTimer()
            }
            // Lyrics follow the current track; the per-track cache makes
            // repeat listens free.
            self.loadLyrics(for: track)
        }
    }

    /// Maps Pandora's `songRating` (pithos' `RATE_LOVE` / `RATE_BAN`) onto
    /// the app's rating enum.
    private static func feedbackRating(for rating: Track.Rating?) -> FeedbackRating {
        switch rating {
        case .some(.loved): return .loved
        case .some(.banned): return .banned
        default: return .none
        }
    }

    /// Entry point for UI intents.
    func send(_ intent: Intent) {
        switch intent {
        case .restoreSession:
            restoreSession()
        case .login(let username, let password):
            login(username: username, password: password)
        case .refreshStations:
            Task { await refreshStations() }
        case .searchStations(let query):
            search(query)
        case .createStation(let result):
            Task { await createStation(from: result) }
        case .renameStation(let station, let newName):
            Task { await renameStation(station, to: newName) }
        case .deleteStation(let station):
            Task { await deleteStation(station) }
        case .playStation(let station):
            Task { await play(station) }
        case .togglePlayback:
            player.togglePlayback()
        case .skipToNext:
            player.skipToNext()
        case .refreshLyrics:
            loadLyrics(for: player.currentTrack, force: true)
        case .rateCurrentTrack(let rating):
            Task { await rateCurrentTrack(rating) }
        case .removeCurrentRating:
            Task { await removeCurrentRating() }
        case .sleepCurrentTrack:
            Task { await sleepCurrentTrack() }
        case .bookmarkCurrentSong:
            Task { await bookmarkCurrentSong() }
        case .bookmarkCurrentArtist:
            Task { await bookmarkCurrentArtist() }
        case .refreshBookmarks:
            Task { await refreshBookmarks() }
        case .deleteBookmark(let bookmark):
            Task { await deleteBookmark(bookmark) }
        case .setSleepTimer(let timer):
            setSleepTimer(timer)
        case .cancelSleepTimer:
            setSleepTimer(.off)
        case .moveStation(let source, let destination):
            moveStation(from: source, to: destination)
        case .dismissError:
            lastErrorMessage = nil
        }
    }

    // MARK: Auth

    /// Warm start: pull the Keychain session into memory with zero network.
    /// Expiry surfaces later as a 1001 on the first authenticated call, and
    /// `SessionManager` re-logins transparently then.
    private func restoreSession() {
        guard !didStartRestore else { return }
        didStartRestore = true
        Task {
            let restored = await session.restore()
            AppLog.info("session restore: \(restored ? "restored" : "no session")")
            if restored {
                authPhase = .signedIn
                await refreshStations()
            } else {
                authPhase = .signedOut
            }
        }
    }

    private func login(username: String, password: String) {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Enter your email and password."
            return
        }
        guard authPhase == .signedOut else { return }

        lastErrorMessage = nil
        authPhase = .signingIn
        Task {
            do {
                _ = try await session.login(username: user, password: password)
                authPhase = .signedIn
                await refreshStations()
            } catch {
                authPhase = .signedOut
                lastErrorMessage = Self.userMessage(for: error)
            }
        }
    }

    // MARK: Stations

    /// Fetches `user.getStationList` (M2). Fire-and-forget via the intent;
    /// `refreshStations()` is also awaited directly for pull-to-refresh and
    /// the post-sign-in load. A guard keeps concurrent calls from stacking.
    func refreshStations() async {
        guard !isLoadingStations else { return }
        lastErrorMessage = nil
        isLoadingStations = true
        defer { isLoadingStations = false }
        do {
            let list = try await session.getStationList()
            stations = displayOrder(for: list.stations)
            AppLog.info("station list loaded: \(stations.count) stations")
        } catch {
            // Keep any already-loaded list; surface the error when empty
            // (error/empty-state polish lands in M5).
            if stations.isEmpty {
                lastErrorMessage = Self.userMessage(for: error)
            }
            AppLog.error("station list failed: \(String(describing: error))")
        }
    }

    /// Rename via `SessionManager` (shared stations transform first on the
    /// core side), then reload so sort order reflects the new name.
    private func renameStation(_ station: Station, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isMutatingStations else {
            if trimmed.isEmpty {
                lastErrorMessage = "Enter a station name."
            }
            return
        }
        lastErrorMessage = nil
        isMutatingStations = true
        defer { isMutatingStations = false }
        do {
            try await session.renameStation(station, to: trimmed)
            await refreshStations()
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    private func deleteStation(_ station: Station) async {
        guard !isMutatingStations else { return }
        lastErrorMessage = nil
        isMutatingStations = true
        defer { isMutatingStations = false }
        do {
            try await session.deleteStation(station)
            stations.removeAll { $0.id == station.id }
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    // MARK: Playback

    /// Plays a station: fetches its playlist, starts the first track and
    /// queues the next one (prefetch). Tapping the station that is already
    /// playing toggles playback instead of restarting it.
    private func play(_ station: Station) async {
        if currentStation?.id == station.id, player.currentTrack != nil {
            player.togglePlayback()
            return
        }
        guard !isLoadingPlaylist else { return }
        lastErrorMessage = nil
        isLoadingPlaylist = true
        defer { isLoadingPlaylist = false }
        do {
            let playlist = try await session.getPlaylist(for: station)
            let playable = playlist.tracks.filter { $0.streamURL != nil }
            AppLog.info(
                "playlist for \"\(station.name)\": \(playlist.tracks.count) entries, \(playable.count) playable",
                .playback
            )
            guard let first = playable.first else {
                currentStation = station
                lastErrorMessage = "No playable tracks in this station right now."
                return
            }
            currentStation = station
            queuedTrackTokens = Set(playable.map(\.trackToken))
            preferences.lastStationId = station.id
            preferencesStore.save(preferences)
            player.play(track: first, prefetching: playable.dropFirst().first)
        } catch {
            AppLog.error("playlist for \"\(station.name)\" failed: \(String(describing: error))", .playback)
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Called by the player when its queue runs low — fetch the next
    /// playlist for the current station and queue the new tracks.
    private func fetchMoreTracks() {
        guard let station = currentStation, !isLoadingPlaylist else { return }
        isLoadingPlaylist = true
        Task {
            defer { isLoadingPlaylist = false }
            do {
                let playlist = try await session.getPlaylist(for: station)
                let fresh = playlist.tracks.filter {
                    $0.streamURL != nil && !queuedTrackTokens.contains($0.trackToken)
                }
                guard !fresh.isEmpty else {
                    AppLog.debug("prefetch playlist: nothing new to queue", .playback)
                    return
                }
                AppLog.info("prefetch playlist: queueing \(fresh.count) more tracks", .playback)
                queuedTrackTokens.formUnion(fresh.map(\.trackToken))
                player.enqueue(fresh)
            } catch {
                // A failed prefetch is not fatal — the current track keeps
                // playing; the next skip retries.
                AppLog.error("prefetch playlist failed: \(String(describing: error))", .playback)
                lastErrorMessage = Self.userMessage(for: error)
            }
        }
    }

    /// The list as the user sees it: QuickMix first, then the stored
    /// order, then the remaining stations by name (case-insensitive, id
    /// as the tiebreak so the order never shuffles between reloads).
    private func displayOrder(for stations: [Station]) -> [Station] {
        let ordered = preferences.stationOrder.apply(to: stations)
        let custom = Set(preferences.stationOrder.orderedIds)
        return ordered.sorted { lhs, rhs in
            if lhs.isQuickMix != rhs.isQuickMix { return lhs.isQuickMix }
            let lhsCustom = custom.contains(lhs.id)
            let rhsCustom = custom.contains(rhs.id)
            if lhsCustom != rhsCustom { return lhsCustom }
            if lhsCustom {
                // Both are user-ordered — keep the stored sequence.
                let lhsIndex = preferences.stationOrder.orderedIds.firstIndex(of: lhs.id) ?? 0
                let rhsIndex = preferences.stationOrder.orderedIds.firstIndex(of: rhs.id) ?? 0
                return lhsIndex < rhsIndex
            }
            switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.id < rhs.id
            }
        }
    }

    /// Moves a station to a new position in the list and persists the
    /// new order.
    private func moveStation(from source: Int, to destination: Int) {
        guard stations.indices.contains(source) else { return }
        var ids = stations.map(\.id)
        let moved = ids.remove(at: source)
        let target = min(max(0, destination), ids.count)
        ids.insert(moved, at: target)
        preferences.stationOrder.setOrder(ids)
        stations = preferences.stationOrder.apply(to: stations)
        preferencesStore.save(preferences)
    }

    // MARK: Lyrics

    /// Loads lyrics for the current track (lrclib.net, via the core's
    /// provider). Results — including "not found" — are cached per
    /// `trackToken`, so repeat listens never re-hit the service. A track
    /// change cancels the in-flight fetch; a superseded fetch never
    /// touches state.
    private func loadLyrics(for track: Track?, force: Bool = false) {
        lyricsTask?.cancel()
        lyricsTask = nil
        translationTask?.cancel()
        translationTask = nil
        guard let track, !track.isAdvertisement else {
            lyrics = nil
            isLoadingLyrics = false
            return
        }
        if !force, let cached = lyricsCache[track.trackToken] {
            lyrics = cached
            isLoadingLyrics = false
            return
        }
        lyrics = nil
        isLoadingLyrics = true
        let provider = lyricsProvider
        AppLog.debug("lyrics: lookup for \"\(track.title)\" — \"\(track.artist)\"", .lyrics)
        lyricsTask = Task { [weak self] in
            let outcome: Result<Lyrics, Error>
            do {
                outcome = .success(try await provider.lyrics(for: track))
            } catch {
                outcome = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            isLoadingLyrics = false
            switch outcome {
            case .success(let fetched):
                lyricsCache[track.trackToken] = fetched
                lyrics = fetched
                AppLog.info(
                    "lyrics: \(Self.describe(fetched)) for \"\(track.title)\"",
                    .lyrics
                )
                translateIfNeeded(fetched, for: track)
            case .failure(let error):
                if (error as? LyricsError) == .notFound {
                    lyricsCache[track.trackToken] = .empty
                }
                lyrics = nil
                AppLog.debug(
                    "lyrics: unavailable for \"\(track.title)\" (\(String(describing: error)))",
                    .lyrics
                )
            }
        }
    }

    /// Short, loggable description of what a lyrics lookup returned.
    private static func describe(_ lyrics: Lyrics) -> String {
        if lyrics.instrumental { return "instrumental" }
        if lyrics.isSynced { return "synced, \(lyrics.lines.count) lines" }
        if lyrics.plainText != nil { return "plain text" }
        return "empty"
    }

    /// Kicks off an English translation for a freshly fetched set of
    /// synced lyrics. The endpoint detects the source language and
    /// returns nil for English — then the original stays as-is. Lyrics
    /// display immediately; the translation fills in when it arrives.
    private func translateIfNeeded(_ fetched: Lyrics, for track: Track) {
        guard fetched.isSynced, !fetched.lines.isEmpty else { return }
        let texts = fetched.lines.map(\.text)
        let translator = lyricsTranslator
        AppLog.debug("lyrics: translating \(texts.count) lines", .lyrics)
        translationTask = Task { [weak self] in
            let translated = await translator.englishTranslation(of: texts)
            guard let self, !Task.isCancelled else { return }
            if let translated {
                self.applyTranslation(translated, for: track.trackToken)
                AppLog.info("lyrics: translation applied for \"\(track.title)\"", .lyrics)
            } else {
                AppLog.debug("lyrics: no translation for \"\(track.title)\" (English or none)", .lyrics)
            }
        }
    }

    /// Fills `LyricLine.translation` on the cached lyrics for `token` and,
    /// if that track is still current, on the live state. Guarded by line
    /// count so a mismatched response can never shift the alignment.
    private func applyTranslation(_ translated: [String], for token: String) {
        guard var updated = lyricsCache[token], updated.isSynced,
              updated.lines.count == translated.count else { return }
        var lines = updated.lines
        for index in lines.indices {
            lines[index].translation = translated[index]
        }
        updated = Lyrics(
            lines: lines,
            plainText: updated.plainText,
            instrumental: updated.instrumental,
            trackID: updated.trackID
        )
        lyricsCache[token] = updated
        if player.currentTrack?.trackToken == token {
            lyrics = updated
        }
    }

    // MARK: Feedback & bookmarks

    /// Sets (or clears) the sleep timer. A duration timer that has
    /// expired stops playback; an end-of-track timer fires when the
    /// current track finishes.
    private func setSleepTimer(_ timer: SleepTimer) {
        sleepTimer = timer
        sleepTimerLabel = timer.label()
        preferences.sleepTimer = timer
        preferencesStore.save(preferences)
        // A new timer replaces the old countdown.
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        if timer.hasExpired() {
            player.pause()
            sleepTimer = .off
            sleepTimerLabel = SleepTimer.off.label()
            preferences.sleepTimer = .off
            preferencesStore.save(preferences)
            return
        }
        guard timer.mode == .duration else { return }
        startSleepTimerCountdown()
    }

    /// Counts a duration timer down and stops playback when it expires.
    /// The label is refreshed only when the visible minute count changes,
    /// so the UI re-renders about once a minute — not every second.
    private func startSleepTimerCountdown() {
        let timer = sleepTimer
        guard timer.mode == .duration else { return }
        sleepTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = self.sleepTimer.remaining()
                let label = self.sleepTimer.label()
                if label != self.sleepTimerLabel {
                    self.sleepTimerLabel = label
                }
                if remaining <= 0 {
                    self.fireSleepTimer()
                    return
                }
                // Wake up when the next label changes (or when the timer
                // ends) instead of polling every second.
                let sleepFor = min(remaining, 30)
                try? await Task.sleep(for: .seconds(sleepFor))
            }
        }
    }

    /// The timer expired: pause playback and clear the timer.
    private func fireSleepTimer() {
        player.pause()
        sleepTimer = .off
        sleepTimerLabel = SleepTimer.off.label()
        preferences.sleepTimer = .off
        preferencesStore.save(preferences)
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
    }
    /// old rating: the previous feedback is deleted first, exactly like
    /// pithos' `Song.rate`.
    private func rateCurrentTrack(_ rating: FeedbackRating) async {
        guard let track = player.currentTrack, rating != .none else { return }
        guard let station = currentStation else { return }
        lastErrorMessage = nil
        do {
            if let feedbackId = currentFeedbackId {
                try await session.deleteFeedback(
                    feedbackId: feedbackId,
                    stationToken: station.token
                )
                currentFeedbackId = nil
            }
            let receipt = try await session.addFeedback(
                trackToken: track.trackToken,
                stationToken: station.token,
                rating: rating
            )
            currentFeedbackId = receipt.feedbackId
            currentRating = rating
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Remove the rating on the current track (thumbs up/down → unrated).
    private func removeCurrentRating() async {
        guard let feedbackId = currentFeedbackId,
              let station = currentStation else { return }
        lastErrorMessage = nil
        do {
            try await session.deleteFeedback(
                feedbackId: feedbackId,
                stationToken: station.token
            )
            currentFeedbackId = nil
            currentRating = .none
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Hide the current track for a few hours (`user.sleepSong`).
    private func sleepCurrentTrack() async {
        guard let track = player.currentTrack else { return }
        lastErrorMessage = nil
        do {
            try await session.sleepSong(trackToken: track.trackToken)
            player.skipToNext()
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Bookmark the current song (`bookmark.addSongBookmark`).
    private func bookmarkCurrentSong() async {
        guard let track = player.currentTrack else { return }
        lastErrorMessage = nil
        do {
            try await session.addSongBookmark(trackToken: track.trackToken)
            await refreshBookmarks()
            showConfirmation("Song bookmarked")
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Bookmark the current artist (`bookmark.addArtistBookmark`).
    private func bookmarkCurrentArtist() async {
        guard let track = player.currentTrack else { return }
        lastErrorMessage = nil
        do {
            try await session.addArtistBookmark(trackToken: track.trackToken)
            await refreshBookmarks()
            showConfirmation("Artist bookmarked")
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Shows a short confirmation in the player, clearing it after a few
    /// seconds. A newer message replaces the pending one.
    private func showConfirmation(_ message: String) {
        confirmationTask?.cancel()
        confirmationMessage = message
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.confirmationMessage = nil
        }
    }

    /// Loads the user's bookmarks.
    func refreshBookmarks() async {
        guard !isLoadingBookmarks else { return }
        isLoadingBookmarks = true
        defer { isLoadingBookmarks = false }
        do {
            bookmarks = try await session.getBookmarks()
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Removes a bookmark (song or artist).
    private func deleteBookmark(_ bookmark: Bookmark) async {
        lastErrorMessage = nil
        do {
            switch bookmark.kind {
            case .song:
                try await session.deleteSongBookmark(bookmarkToken: bookmark.bookmarkToken)
            case .artist:
                try await session.deleteArtistBookmark(bookmarkToken: bookmark.bookmarkToken)
            }
            bookmarks.removeAll { $0.bookmarkToken == bookmark.bookmarkToken }
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    // MARK: Search & create

    /// Debounced callers land here (the view waits out the typing pause).
    /// Queries under 2 chars clear results instead of hitting the API —
    /// never hammer the endpoint. A newer query cancels the in-flight one.
    private func search(_ rawQuery: String) {
        searchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [session] in
            do {
                let hits = try await session.search(query)
                guard !Task.isCancelled else { return }
                searchResults = hits
                isSearching = false
            } catch is CancellationError {
                // Superseded by a newer query — that one owns the state now.
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                isSearching = false
                lastErrorMessage = Self.userMessage(for: error)
            }
        }
    }

    /// Creates from a search hit (`musicToken` covers artist/song/genre —
    /// pithos `add_station_by_music_id`). Appends locally like pithos
    /// (`stations.append`) — no refetch round trip; deduped by id.
    /// Bumps `stationCreatedTick` so the sheet dismisses on success.
    private func createStation(from result: MusicSearchResult) async {
        guard !isMutatingStations else { return }
        lastErrorMessage = nil
        isMutatingStations = true
        defer { isMutatingStations = false }
        do {
            let station = try await session.createStation(musicToken: result.musicToken)
            if !stations.contains(where: { $0.id == station.id }) {
                stations.append(station)
            }
            stationCreatedTick += 1
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    /// Typed PandoraCore errors → short copy safe to render. Never includes
    /// credentials, tokens, or stream material.
    private static func userMessage(for error: Error) -> String {
        if let error = error as? PandoraAPIError {
            return error.localizedDescription
        }
        if let error = error as? PandoraTransportError {
            return "Couldn't reach Pandora (\(error.reason)). Check your connection."
        }
        if error is PandoraMalformedResponseError {
            return "Pandora sent an unexpected response. Try again."
        }
        if let error = error as? SessionManagerError {
            switch error {
            case .notAuthenticated:
                return "Not signed in. Try again."
            case .malformedSession:
                return "Pandora sent an unexpected response. Try again."
            }
        }
        return "Something went wrong. Try again."
    }
}
