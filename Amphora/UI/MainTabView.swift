import SwiftUI

/// The signed-in shell: a tab bar with Stations, Bookmarks and Recently
/// Played, plus the persistent mini-player.
///
/// The mini-player is the tab view's **bottom accessory** (iOS 18): one
/// instance for the whole shell, laid out by the system directly above
/// the tab bar on every tab. An earlier revision attached a
/// `safeAreaInset` to each tab's content instead, which meant three
/// separate player instances — each with its own sheet state — torn down
/// and rebuilt on every tab switch, and stacked insets with the station
/// list's error banner (the "mini player is very buggy when I switch
/// tabs" report).
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
        .tabViewBottomAccessory {
            if store.player.currentTrack != nil {
                MiniPlayer()
            }
        }
        .tint(.accentColor)
    }
}
