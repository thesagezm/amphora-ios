import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .task {
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
            signedInPlaceholder
        }
    }

    /// Stands in for the station list (M2). Auth is the last M1 unit.
    private var signedInPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Signed in")
                .font(.title2.weight(.semibold))
            Text("Stations are coming next.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    RootView()
        .environment(AppStore())
}

extension ShapeStyle where Self == Color {
    static var primaryBackground: Color {
        Color(red: 0.07, green: 0.07, blue: 0.09)
    }
}
