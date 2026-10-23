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
            NavigationStack {
                StationsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                NavigationLink {
                                    BookmarksView()
                                } label: {
                                    Label("Bookmarks", systemImage: "bookmark")
                                }
                                NavigationLink {
                                    HistoryView()
                                } label: {
                                    Label("Recently Played", systemImage: "clock")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel("More")
                        }
                    }
            }
        }
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
