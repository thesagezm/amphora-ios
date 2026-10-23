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
    let player = PlayerService()

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
    // Errors surface here too.
    private(set) var lastErrorMessage: String?

    init(session: SessionManager = SessionManager(store: KeychainSessionStore())) {
        self.session = session
        // The player asks for more tracks when its queue runs low — pithos
        // preloads the next playlist when one song remains.
        player.onNeedMoreTracks = { [weak self] in
            self?.fetchMoreTracks()
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
            stations = list.stations
        } catch {
            // Keep any already-loaded list; surface the error when empty
            // (error/empty-state polish lands in M5).
            if stations.isEmpty {
                lastErrorMessage = Self.userMessage(for: error)
            }
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
            guard let first = playable.first else {
                currentStation = station
                lastErrorMessage = "No playable tracks in this station right now."
                return
            }
            currentStation = station
            queuedTrackTokens = Set(playable.map(\.trackToken))
            player.play(track: first, prefetching: playable.dropFirst().first)
        } catch {
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
                guard !fresh.isEmpty else { return }
                queuedTrackTokens.formUnion(fresh.map(\.trackToken))
                player.enqueue(fresh)
            } catch {
                // A failed prefetch is not fatal — the current track keeps
                // playing; the next skip retries.
                lastErrorMessage = Self.userMessage(for: error)
            }
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
