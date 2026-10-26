import PandoraCore
import SwiftUI

/// Browse Pandora's featured stations ("Today's Hits", "Classic Rock", …)
/// by category — the stations Pandora itself surfaces on its front page.
/// Protocol: `station.getGenreStations` (no parameters), stations grouped
/// under `categories`; a genre station has no playlist, so tapping one
/// creates a personal station from its token (`station.createStation`
/// with the token as `musicToken`) and the sheet dismisses on success —
/// the same tick-dismiss contract as `AddStationView`. Catalog loading
/// and creation live in `AppStore` — this view only dispatches intents.
struct BrowseStationsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let message = store.lastErrorMessage, store.genreCategories == nil {
                    errorState(message)
                } else if let categories = store.genreCategories {
                    if categories.isEmpty {
                        ContentUnavailableView(
                            "No featured stations",
                            systemImage: "radio",
                            description: Text("Pandora returned no station catalog.")
                        )
                    } else {
                        categoryList(categories)
                    }
                } else {
                    ProgressView("Loading stations…")
                        .tint(.secondary)
                        .accessibilityLabel("Loading stations")
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Browse Stations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
            }
        }
        .preferredColorScheme(ThemeController.shared.preferredColorScheme)
        .onAppear {
            store.send(.loadGenreStations)
        }
        .onChange(of: store.stationCreatedTick) {
            // The station landed — close the sheet (same signal the
            // add-station sheet uses).
            dismiss()
        }
    }

    private func categoryList(_ categories: [GenreCategory]) -> some View {
        List(categories) { category in
            NavigationLink {
                CategoryStationsView(category: category)
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "radio")
                                .font(.body)
                                .foregroundStyle(Theme.accentText)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(category.stations.count) stations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .amphoraCardRow()
        }
        .listStyle(.plain)
        .amphoraListBackground()
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load stations", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                store.send(.loadGenreStations)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// One category's featured stations; a row tap creates a personal
/// station from the genre station's token.
private struct CategoryStationsView: View {
    let category: GenreCategory
    @Environment(AppStore.self) private var store

    var body: some View {
        List(category.stations) { genre in
            Button {
                store.send(.createGenreStation(genre))
            } label: {
                HStack(spacing: 12) {
                    CachedArtwork(
                        urlString: genre.artUrl,
                        cornerRadius: 12,
                        fallbackSystemImage: "radio"
                    )
                    .frame(width: 48, height: 48)
                    Text(genre.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if store.isMutatingStations {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accentText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(store.isMutatingStations)
            .accessibilityLabel("Add \(genre.name) to your stations")
            .amphoraCardRow()
        }
        .listStyle(.plain)
        .amphoraListBackground()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
