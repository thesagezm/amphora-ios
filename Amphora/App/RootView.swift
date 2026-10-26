import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    /// The device's current appearance — feeds the "Match System"
    /// theme option.
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .preferredColorScheme(ThemeController.shared.preferredColorScheme)
        .onChange(of: systemColorScheme) { _, scheme in
            ThemeController.shared.setSystemColorScheme(isLight: scheme == .light)
        }
        .task {
            // The device's appearance at launch (before any change).
            ThemeController.shared.setSystemColorScheme(isLight: systemColorScheme == .light)
            // Artwork-driven theming hooks the player's track changes.
            ArtworkThemeController.shared.attach(to: store.player)
            // Warm-launch restore — idempotent, so re-entering after a
            // background relaunch is a no-op.
            store.send(.restoreSession)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.authPhase {
        case .restoring:
            ProgressView("Restoring session…")
                .tint(.secondary)
                .accessibilityLabel("Restoring session")
        case .signedOut, .signingIn:
            LoginView()
        case .signedIn:
            MainTabView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore())
}
