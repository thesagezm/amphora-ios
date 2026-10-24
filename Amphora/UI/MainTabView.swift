import SwiftUI

/// The signed-in shell: a tab bar with Stations, Bookmarks and Recently
/// Played, plus the persistent mini-player.
///
/// The mini-player rides **each tab's content** as a bottom
/// `safeAreaInset`, while the full-player sheet is owned **here** — one
/// instance for the whole shell, so switching tabs never tears it down.
///
/// Two layouts were tried and are worth remembering:
/// - `safeAreaInset` on the `TabView` itself lays the inset out in the
///   tab bar's own region and covers the bar — the original bug.
/// - iOS 26's `tabViewBottomAccessory` is the system-shaped solution,
///   but it does not exist in the iOS 18 SDK this project builds against
///   (CI: Xcode 16.4, "has no member"). Revisit when the toolchain moves
///   past iOS 18.
struct MainTabView: View {
    @Environment(AppStore.self) private var store

    @State private var isShowingNowPlaying = false

    var body: some View {
        TabView {
            NavigationStack {
                StationsView()
            }
            .tabItem {
                Label("Stations", systemImage: "music.note.list")
            }
            .miniPlayer { isShowingNowPlaying = true }

            NavigationStack {
                BookmarksView()
            }
            .tabItem {
                Label("Bookmarks", systemImage: "bookmark")
            }
            .miniPlayer { isShowingNowPlaying = true }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }
            .miniPlayer { isShowingNowPlaying = true }
        }
        .tint(.accentColor)
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView()
        }
    }
}

/// The per-tab mini-player slot: an empty inset until something plays.
/// It must attach to tab *content* — see the discussion on `MainTabView`.
private struct MiniPlayerInset: View {
    @Environment(AppStore.self) private var store
    let onOpen: () -> Void

    var body: some View {
        Group {
            if store.player.currentTrack != nil {
                MiniPlayer(onOpen: onOpen)
            }
        }
    }
}

private extension View {
    func miniPlayer(onOpen: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerInset(onOpen: onOpen)
        }
    }
}
