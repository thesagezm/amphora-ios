import PandoraCore
import SwiftUI

/// M2 station list: the signed-in screen. Rows show artwork, name, and
/// badges (QuickMix / thumbprint / shared). Sorting: QuickMix pinned first,
/// then case-insensitive name with id as a tiebreak for stable order.
/// No networking here — intents only (`refreshStations`).
struct StationsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.stations.isEmpty {
                if store.isLoadingStations {
                    loading
                } else if let message = store.lastErrorMessage {
                    errorState(message)
                } else {
                    empty
                }
            } else {
                list
            }
        }
        .navigationTitle("Stations")
    }

    // MARK: States

    private var loading: some View {
        ProgressView("Loading stations…")
            .tint(.secondary)
            .accessibilityLabel("Loading stations")
    }

    private var empty: some View {
        ContentUnavailableView(
            "No stations yet",
            systemImage: "music.note.list",
            description: Text("Your stations will appear here.")
        )
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load stations", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                store.send(.refreshStations)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        List(sortedStations) { station in
            StationRow(station: station)
                .listRowBackground(Color.primaryBackground.opacity(0.4))
        }
        .listStyle(.plain)
        .refreshable {
            await store.refreshStations()
        }
    }

    // MARK: Sorting

    /// QuickMix first (it's the default landing station everywhere else),
    /// then A–Z case-insensitively; station id breaks ties so equal names
    /// never shuffle between reloads (Swift's sort is not stable).
    private var sortedStations: [Station] {
        store.stations.sorted { lhs, rhs in
            if lhs.isQuickMix != rhs.isQuickMix {
                return lhs.isQuickMix
            }
            switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.id < rhs.id
            }
        }
    }
}

/// One station row: artwork (AsyncImage → URLCache until the dedicated
/// cache lands), name, badge caption for the non-plain cases.
private struct StationRow: View {
    let station: Station

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if station.isQuickMix {
                        Image(systemName: "shuffle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                    Text(station.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                if let caption = badgeCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if station.isShared {
                Image(systemName: "person.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Shared station")
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
            if let urlString = station.artUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallbackIcon
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: "music.note")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    private var badgeCaption: String? {
        if station.isQuickMix { return "Quick mix" }
        if station.isThumbprint { return "Thumbprint station" }
        return nil
    }
}

#Preview {
    NavigationStack {
        StationsView()
            .environment(AppStore())
    }
    .preferredColorScheme(.dark)
}
