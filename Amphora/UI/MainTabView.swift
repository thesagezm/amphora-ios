import SwiftUI

/// The signed-in shell: Home (stations), Radio (the Shortwave port,
/// R4) and Settings. Recents lost its tab (user request 2026-11-07) —
/// history and bookmarks open from a Home toolbar button. The
/// persistent mini-player rides along.
///
/// The mini-player rides the **scroll surfaces themselves** (each
/// screen's List/ScrollView, via `.miniPlayer()`), not the tab content:
/// a bottom safe-area inset applied *outside* a `NavigationStack` keeps
/// its place above the tab bar but never reaches the scroll content
/// inside — the lists scrolled underneath the card and the last row was
/// stuck beneath it, untappable (user report 2026-11-11). Attached to
/// the scroll surface directly, the inset is part of the scroll view's
/// own safe area, so the last row scrolls clear of the card.
///
/// Three layouts tried and worth remembering:
/// - `safeAreaInset` on the `TabView` itself lays the inset out in the
///   tab bar's own region and covers the bar — the original bug.
/// - `safeAreaInset` on each tab's `NavigationStack` fixed the bar but
///   not the lists — an inset outside a `NavigationStack` does not
///   propagate into the scroll content inside it.
/// - iOS 26's `tabViewBottomAccessory` is the system-shaped solution,
///   but it does not exist in the iOS 18 SDK this project builds
///   against (CI: Xcode 16.4, "has no member"). Revisit when the
///   toolchain moves past iOS 18.
struct MainTabView: View {
    @State private var isShowingNowPlaying = false

    var body: some View {
        TabView {
            NavigationStack {
                StationsView()
            }
            .tabItem {
                Label("Home", systemImage: "music.note.house")
            }

            NavigationStack {
                RadioView()
            }
            .tabItem {
                Label("Radio", systemImage: "antenna.radiowaves.left.and.right")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(Theme.accent)
        .environment(\.openNowPlaying, OpenNowPlayingAction {
            isShowingNowPlaying = true
        })
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView()
        }
    }
}

/// Opens the full player. `MainTabView` owns the sheet — one instance
/// for the whole shell, so tab switches never tear it down — and hands
/// the action down through the environment; every screen's mini-player
/// slot dispatches to it.
///
/// `@unchecked Sendable`: the closure mutates `MainTabView`'s `@State`
/// and every caller reaches it from the main actor — it is a
/// main-actor affordance, not a thread-safe one (the same shape as the
/// core's `SessionBox`).
struct OpenNowPlayingAction: @unchecked Sendable {
    let open: () -> Void
}

private struct OpenNowPlayingKey: EnvironmentKey {
    static let defaultValue = OpenNowPlayingAction(open: {})
}

extension EnvironmentValues {
    /// Presents the full Now Playing sheet.
    var openNowPlaying: OpenNowPlayingAction {
        get { self[OpenNowPlayingKey.self] }
        set { self[OpenNowPlayingKey.self] = newValue }
    }
}

/// The mini-player slot: an empty inset until something plays. It must
/// attach to the scroll surface itself — see the discussion on
/// `MainTabView`.
struct MiniPlayerInset: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openNowPlaying) private var openNowPlaying

    var body: some View {
        Group {
            if store.player.currentTrack != nil {
                MiniPlayer(onOpen: { openNowPlaying.open() })
            }
        }
    }
}

extension View {
    /// Pins the mini-player above the tab bar and keeps scrollable
    /// content clear of it. Attach directly to the screen's
    /// List/ScrollView (or the Group selecting them) — never to a
    /// `NavigationStack`.
    ///
    /// The content is stretched to fill the screen first. Without it,
    /// a screen whose content is a small centered placeholder (the
    /// loading spinner, an empty state) gave the inset a small anchor:
    /// `safeAreaInset` places its content at the *bottom of the
    /// modified view's own bounds*, so the card landed directly under
    /// the centered spinner — in the middle of the screen (user report
    /// 2026-11-12, the Popular/Countries pages). A flexible frame
    /// makes the bounds the whole screen, so the card is at the bottom
    /// whatever the content is; Lists already fill and are unaffected.
    func miniPlayer() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerInset()
            }
    }
}
