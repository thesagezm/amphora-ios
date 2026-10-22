import Observation

@MainActor
@Observable
final class AppStore {
    // Auth state is filled in during M1; until then the app shows its
    // placeholder root view.
    private(set) var isSignedIn: Bool = false

    // Stations, current station, current track and feedback state arrive in
    // M2/M4. Errors surface here too.
    private(set) var lastErrorMessage: String?

    /// Entry point for UI intents. Kept as an enum so adding an intent later
    /// never changes the UI call sites.
    func send(_ intent: Intent) {
        switch intent {
        case .dismissError:
            lastErrorMessage = nil
        }
    }

    enum Intent {
        case dismissError
    }
}
