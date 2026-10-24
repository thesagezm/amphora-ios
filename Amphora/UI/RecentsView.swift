import PandoraCore
import SwiftUI

/// The Recents tab: the local play history and the user's bookmarks
/// share one screen behind a soft segmented pill. Bookmarks lost their
/// own tab (user request 2026-10-24) — this keeps them one tap away.
struct RecentsView: View {
    @Environment(AppStore.self) private var store

    @State private var segment: Segment = .history

    private enum Segment: String, CaseIterable, Identifiable {
        case history = "Recents"
        case bookmarks = "Bookmarks"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker
            Group {
                switch segment {
                case .history: historyList
                case .bookmarks: BookmarksList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Recents")
    }

    /// The theme's own segmented control: a soft surface track, the
    /// selected pill lifting via a lighter fill + the accent — no hard
    /// borders.
    private var segmentPicker: some View {
        HStack(spacing: 4) {
            ForEach(Segment.allCases) { item in
                let isSelected = segment == item
                Button {
                    withAnimation(.snappy(duration: 0.25)) { segment = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                isSelected ? Theme.surfaceHighlight : Color.clear
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surface))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityLabel("Show recents or bookmarks")
    }

    // MARK: Recents

    @ViewBuilder
    private var historyList: some View {
        if store.history.entries.isEmpty {
            ContentUnavailableView {
                Label("Nothing played yet", systemImage: "clock")
            } description: {
                Text("Tracks you listen to will show up here.")
            }
        } else {
            List(store.history.entries) { entry in
                HStack(spacing: 12) {
                    CachedArtwork(urlString: entry.artworkUrl, cornerRadius: Theme.radiusS)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(entry.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(entry.playedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .amphoraCardRow()
            }
            .listStyle(.plain)
            .amphoraListBackground()
        }
    }
}

/// The bookmarks half of the Recents tab — the user's saved songs and
/// artists (`user.getBookmarks`), with delete.
private struct BookmarksList: View {
    @Environment(AppStore.self) private var store

    private var songs: [Bookmark] { store.bookmarks.filter { $0.kind == .song } }
    private var artists: [Bookmark] { store.bookmarks.filter { $0.kind == .artist } }

    var body: some View {
        Group {
            if store.isLoadingBookmarks && store.bookmarks.isEmpty {
                ProgressView("Loading bookmarks…")
                    .tint(.secondary)
                    .accessibilityLabel("Loading bookmarks")
            } else if store.bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No bookmarks yet", systemImage: "bookmark")
                } description: {
                    Text("Bookmark a song or artist from the player.")
                }
            } else {
                list
            }
        }
        .task {
            await store.refreshBookmarks()
        }
    }

    private var list: some View {
        List {
            if !songs.isEmpty {
                Section("Songs") {
                    ForEach(songs) { bookmark in
                        row(bookmark)
                            .amphoraCardRow()
                    }
                }
            }
            if !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists) { bookmark in
                        row(bookmark)
                            .amphoraCardRow()
                    }
                }
            }
        }
        .listStyle(.plain)
        .amphoraListBackground()
    }

    private func row(_ bookmark: Bookmark) -> some View {
        HStack(spacing: 12) {
            CachedArtwork(
                urlString: bookmark.artworkUrl,
                cornerRadius: Theme.radiusS,
                fallbackSystemImage: bookmark.kind == .song ? "music.note" : "music.mic"
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if bookmark.kind == .song {
                    Text(bookmark.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                store.send(.deleteBookmark(bookmark))
            } label: {
                Image(systemName: "trash")
                    .font(.footnote)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove bookmark \(bookmark.title)")
        }
        .frame(minHeight: 44)
    }
}
