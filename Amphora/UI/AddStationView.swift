import PandoraCore
import SwiftUI

/// Add-station sheet (M2): search field → results → tap a row to create a
/// station from its `musicToken` (pithos SearchDialog + add_station flow).
/// Debounce lives in `scheduleSearch()`; policy (min query length, scoring)
/// lives in `AppStore`/`PandoraCore` — this view only dispatches intents.
struct AddStationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?

    /// Recent keystrokes clear stale results before the debounce fires.
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("New Station")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .accessibilityLabel("Cancel")
                    }
                }
        }
        .searchable(text: $query, prompt: "Artists, songs, genres")
        .onAppear {
            scheduleSearch()
        }
        .onChange(of: query) {
            scheduleSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onChange(of: store.stationCreatedTick) {
            // The station landed — close the sheet (fire-and-forget intent
            // can't return success, so the tick is the signal).
            dismiss()
        }
    }

    /// Debounce: restart the 350 ms timer on every keystroke. (Was
    /// `.task(id: query)` — the app avoids `.task(id:)` because its
    /// backing modifier, `_TaskValueModifier`, trapped inside SwiftUI's
    /// type-metadata instantiation during launch on iOS 27.0; see
    /// `CachedArtwork`.)
    private func scheduleSearch() {
        searchTask?.cancel()
        let searchQuery = trimmedQuery
        guard searchQuery.count >= 2 else {
            store.send(.searchStations(query: searchQuery))
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            store.send(.searchStations(query: searchQuery))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = store.lastErrorMessage {
            banner(message)
        }
        if store.isSearching && store.searchResults.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Searching")
        } else if trimmedQuery.count < 2 {
            prompt("Type at least 2 characters to search.")
        } else if store.searchResults.isEmpty {
            prompt(trimmedQuery.isEmpty
                  ? "Search to add a station."
                  : "No results for “\(trimmedQuery)”.")
        } else {
            results
        }
    }

    private var results: some View {
        List(store.searchResults) { hit in
            row(hit)
                .listRowBackground(Color.primaryBackground.opacity(0.4))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ hit: MusicSearchResult) -> some View {
        Button {
            store.send(.createStation(hit))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: hit.kind))
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(caption(for: hit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.isMutatingStations {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isMutatingStations)
        .accessibilityLabel("Create station from \(hit.title)")
        .accessibilityHint(caption(for: hit))
    }

    private func prompt(_ text: String) -> some View {
        ContentUnavailableView(
            "Find a station",
            systemImage: "magnifyingglass",
            description: Text(text)
        )
    }

    private func banner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.send(.dismissError)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Kind presentation

    private func icon(for kind: MusicSearchResult.Kind) -> String {
        switch kind {
        case .artist: return "music.mic"
        case .song: return "music.note"
        case .genre: return "radio"
        }
    }

    /// Second line under the title: the artist for a song (pithos shows
    /// "title by artist" on one line; we split across two), a kind label
    /// for artist/genre rows.
    private func caption(for hit: MusicSearchResult) -> String {
        switch hit.kind {
        case .song:
            if let artist = hit.subtitle { return artist }
            return "Song"
        case .artist:
            return "Artist"
        case .genre:
            return "Genre station"
        }
    }
}
