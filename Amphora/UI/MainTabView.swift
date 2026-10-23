import SwiftUI

/// The signed-in shell: a tab bar with Stations, Bookmarks and Recently
/// Played, plus the persistent mini-player above the tab bar.
///
/// The mini-player is attached to **each tab's content**, not to the
/// `TabView` itself: a bottom safe-area inset on the `TabView` is laid
/// out in the tab bar's own region, so the player covered the tab bar.
/// An inset inside a tab's content sits directly above it.
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                StationsView()
                    .modifier(MiniPlayerInset())
            }
            .tabItem {
                Label("Stations", systemImage: "music.note.list")
            }

            NavigationStack {
                BookmarksView()
                    .modifier(MiniPlayerInset())
            }
            .tabItem {
                Label("Bookmarks", systemImage: "bookmark")
            }

            NavigationStack {
                HistoryView()
                    .modifier(MiniPlayerInset())
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }
        }
        .tint(.accentColor)
    }
}

/// Keeps the mini-player pinned above the tab bar on every tab.
private struct MiniPlayerInset: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if store.player.currentTrack != nil {
                MiniPlayer()
            }
        }
    }
}
