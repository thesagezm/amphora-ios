import PandoraCore
import SwiftUI

/// The Home tab: the last-played station as a large centered hero
/// (user request 2026-10-24), then the browse row and the station list.
/// Rows show artwork, name, and badges (QuickMix / thumbprint /
/// shared); the playing station's card washes in the accent. Sorting:
/// QuickMix pinned first, then the stored order, then A–Z. No
/// networking here — intents only (`refreshStations`).
struct StationsView: View {
    @Environment(AppStore.self) private var store

    @State private var renameTarget: Station?
    @State private var renameText = ""
    @State private var deleteTarget: Station?
    @State private var tuningStation: Station?
    @State private var isAddingStation = false
    @State private var isBrowsingStations = false
    @State private var isEditingOrder = false

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
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingStation = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add station")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditingOrder.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Reorder stations")
            }
        }
        .environment(\.editMode, .constant(isEditingOrder ? .active : .inactive))
        .sheet(isPresented: $isAddingStation) {
            AddStationView()
        }
        .sheet(isPresented: $isBrowsingStations) {
            BrowseStationsSheet()
        }
        .sheet(item: $tuningStation) { station in
            TuneStationSheet(station: station)
        }
        .alert("Rename Station", isPresented: renameBinding) {
            TextField("Station name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let station = renameTarget {
                    store.send(.renameStation(station, to: renameText))
                }
                renameTarget = nil
            }
        } message: {
            Text("Choose a new name for this station.")
        }
        .alert(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: deleteBinding,
            presenting: deleteTarget
        ) { station in
            Button("Delete", role: .destructive) {
                store.send(.deleteStation(station))
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the station from your list. It can't be undone here.")
        }
    }

    // MARK: States

    private var loading: some View {
        ProgressView("Loading stations…")
            .tint(.secondary)
            .accessibilityLabel("Loading stations")
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No stations yet", systemImage: "music.note.list")
        } description: {
            Text("Your stations will appear here.")
        } actions: {
            Button("Add Station") {
                isAddingStation = true
            }
            .buttonStyle(.borderedProminent)
        }
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
        List {
            hero
            browseRow
                .amphoraCardRow()
            ForEach(store.stations) { station in
                let isCurrent = store.currentStation?.id == station.id
                Button {
                    store.send(.playStation(station))
                } label: {
                    StationRow(
                        station: station,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && store.player.isPlaying
                    )
                }
                .buttonStyle(.plain)
                .amphoraCardRow(tinted: isCurrent)
                .contextMenu {
                    // QuickMix is an aggregator — Pandora offers it no
                    // listening modes to tune.
                    if !station.isQuickMix {
                        Button {
                            tuningStation = station
                        } label: {
                            Label("Tune Station…", systemImage: "slider.horizontal.3")
                        }
                    }
                    // pithos' edit dialog filters quickmix + thumbprint out
                    // of rename/delete — mirror that here.
                    if !station.isQuickMix && !station.isThumbprint {
                        Button {
                            renameText = station.name
                            renameTarget = station
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteTarget = station
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .onMove { source, destination in
                // onMove reports an IndexSet; Amphora moves one row at a time.
                guard let from = source.first else { return }
                store.send(.moveStation(from: from, to: destination))
            }
        }
        .listStyle(.plain)
        .amphoraListBackground()
        .refreshable {
            await store.refreshStations()
        }
        // Non-blocking error surface once a list exists (empty-state errors
        // render above); M5 restyles these.
        .safeAreaInset(edge: .bottom) {
            if !store.stations.isEmpty, let message = store.lastErrorMessage {
                errorBanner(message)
            }
        }
    }

    /// The last-played (or playing) station, large and centered — the
    /// landing page's centerpiece. Hidden until something has played.
    @ViewBuilder
    private var hero: some View {
        if let station = store.featuredStation {
            let isPlaying = store.currentStation?.id == station.id && store.player.isPlaying
            VStack(spacing: 16) {
                CachedArtwork(
                    urlString: station.artUrl,
                    cornerRadius: Theme.radiusL,
                    fallbackSystemImage: station.isQuickMix ? "shuffle" : "music.note.list"
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.40), radius: 22, y: 10)
                .shadow(color: Theme.accent.opacity(0.16), radius: 36, y: 10)

                VStack(spacing: 4) {
                    Text(station.name)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(isPlaying ? "Now playing" : "Last played")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                Button {
                    Haptics.light()
                    store.send(.playStation(station))
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.accentGlyph)
                        .frame(width: 58, height: 58)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 5)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(
                    isPlaying ? "Pause \(station.name)" : "Play \(station.name)"
                )
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    /// Landing-page entry to Pandora's featured stations (user request:
    /// "landing page only shows my stations … popular pandora created
    /// main stations as well"). Opens `BrowseStationsSheet`.
    private var browseRow: some View {
        Button {
            isBrowsingStations = true
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "radio.fill")
                            .font(.body)
                            .foregroundStyle(Theme.accent)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Browse Pandora Stations")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text("Popular stations made by Pandora")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse Pandora's featured stations")
    }

    private func errorBanner(_ message: String) -> some View {
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
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                .fill(Theme.surface)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Alert bindings

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    // MARK: Sorting

    // The store owns the order (QuickMix first, then the user's stored
    // order, then A–Z); the view renders `store.stations` as given.
}

/// One station row: artwork (AsyncImage → URLCache until the dedicated
/// cache lands), name, badge caption for the non-plain cases.
private struct StationRow: View {
    let station: Station
    var isCurrent = false
    var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if station.isQuickMix {
                        Image(systemName: "shuffle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                            .accessibilityHidden(true)
                    }
                    Text(station.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isCurrent ? Theme.accentText : Color.primary)
                        .lineLimit(1)
                }
                if let caption = badgeCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Playing")
            } else if station.isShared {
                Image(systemName: "person.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Shared station")
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isCurrent ? "\(station.name), currently playing" : station.name
        )
    }

    private var artwork: some View {
        CachedArtwork(urlString: station.artUrl, cornerRadius: 10)
            .frame(width: 52, height: 52)
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
}
