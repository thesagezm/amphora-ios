import SwiftUI

/// The signed-in shell: a tab bar with Stations, Bookmarks and Recently
/// Played, plus the persistent mini-player above the tab bar.
///
/// The mini-player lives here (not inside `StationsView`) so it stays
/// visible on every tab — AGENTS.md: "Persistent mini-player above the
/// tab bar".
struct MainTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            NavigationStack {
                StationsView()
            }
            .tabItem {
                Label("Stations", systemImage: "music.note.list")
            }

            NavigationStack {
                BookmarksView()
            }
            .tabItem {
                Label("Bookmarks", systemImage: "bookmark")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }
        }
        .tint(.accentColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.player.currentTrack != nil {
                MiniPlayer()
            }
        }
    }
}
