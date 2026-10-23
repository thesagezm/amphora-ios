import PandoraCore
import SwiftUI

/// The user's bookmarks: song and artist lists, with delete.
struct BookmarksView: View {
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
                    Text("Bookmark a song or artist from the Now Playing screen.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Bookmarks")
        .refreshable {
            await store.refreshBookmarks()
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
                    }
                }
            }
            if !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists) { bookmark in
                        row(bookmark)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ bookmark: Bookmark) -> some View {
        HStack(spacing: 12) {
            CachedArtwork(
                urlString: bookmark.artworkUrl,
                cornerRadius: 8,
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
