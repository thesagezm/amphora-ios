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
        case dismissError
    }

    private let session: SessionManager
    private var didStartRestore = false

    private(set) var authPhase: AuthPhase = .restoring
    private(set) var stations: [Station] = []
    private(set) var isLoadingStations = false
    // Current station, current track and feedback state arrive in M3/M4.
    // Errors surface here too.
    private(set) var lastErrorMessage: String?

    init(session: SessionManager = SessionManager(store: KeychainSessionStore())) {
        self.session = session
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
