import Foundation

@MainActor
final class PlayerService {
    // AVPlayer wiring arrives in M3. This type is declared now so the app
    // target's structure is fixed: single source of truth for playback state.
    // It must not perform networking — it talks to PandoraCore through AppStore.
}
