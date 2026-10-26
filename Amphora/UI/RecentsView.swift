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
                        .foregroundStyle(isSelected ? Theme.accentText : Color.secondary)
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
                let station = station(for: entry)
                HistoryRow(
                    entry: entry,
                    station: station,
                    isRating: store.ratingTrackTokens.contains(entry.trackToken),
                    onRate: { rating in
                        guard let station else { return }
                        store.send(.rateHistoryTrack(rating, entry: entry, station: station))
                    },
                    onRemoveRating: {
                        guard let station else { return }
                        store.send(.removeHistoryTrackRating(entry: entry, station: station))
                    }
                )
                .amphoraCardRow()
            }
            .listStyle(.plain)
            .amphoraListBackground()
        }
    }

    /// The station a remembered track was played from — the rating of a
    /// past track belongs to that station. Nil when the station is no
    /// longer in the user's list (deleted or transformed), in which case
    /// the row's rating buttons are disabled.
    private func station(for entry: PlayHistory.Entry) -> Station? {
        guard let token = entry.stationToken else { return nil }
        return store.stations.first { $0.token == token }
    }
}

/// One remembered play: artwork, title/artist, when it played, and the
/// rating controls.
///
/// **Rating a song that has already played** (user request 2026-10-26)
/// — the rating belongs to the song, so it can be given long after the
/// track ended. The buttons mirror the player's FeedbackBar: the active
/// rating fills, tapping it again removes the rating.
private struct HistoryRow: View {
    let entry: PlayHistory.Entry
    /// The station the track was played from — nil when it is gone.
    let station: Station?
    /// A rating request is in flight for this row.
    let isRating: Bool
    let onRate: (FeedbackRating) -> Void
    let onRemoveRating: () -> Void

    private var rating: FeedbackRating { entry.rating ?? .none }

    var body: some View {
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

            ratingControls
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    /// The two rating glyphs, plus when the track played.
    @ViewBuilder
    private var ratingControls: some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                ratingButton(.loved, systemImage: "hand.thumbsup", label: "Thumbs up")
                ratingButton(.banned, systemImage: "hand.thumbsdown", label: "Thumbs down")
            }
            Text(entry.playedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    private func ratingButton(
        _ value: FeedbackRating,
        systemImage: String,
        label: String
    ) -> some View {
        let isActive = rating == value
        return Button {
            Haptics.light()
            if isActive {
                onRemoveRating()
            } else {
                onRate(value)
            }
        } label: {
            Image(systemName: isActive ? "\(systemImage).fill" : systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(isActive ? Theme.accentText : Color.secondary)
                .frame(width: 30, height: 24)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isRating || station == nil)
        .opacity(station == nil ? 0.4 : 1)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
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
