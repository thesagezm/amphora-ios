import PandoraCore
import SwiftUI

/// M2 station list: the signed-in screen. Rows show artwork, name, and
/// badges (QuickMix / thumbprint / shared). Sorting: QuickMix pinned first,
/// then case-insensitive name with id as a tiebreak for stable order.
/// No networking here — intents only (`refreshStations`).
struct StationsView: View {
    @Environment(AppStore.self) private var store

    @State private var renameTarget: Station?
    @State private var renameText = ""
    @State private var deleteTarget: Station?
    @State private var isAddingStation = false
    @State private var isEditingOrder = false
    @State private var isShowingDiagnostics = false

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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingDiagnostics = true
                } label: {
                    Image(systemName: "stethoscope")
                }
                .accessibilityLabel("Diagnostics and logs")
            }
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
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsView()
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
            ForEach(store.stations) { station in
                Button {
                    store.send(.playStation(station))
                } label: {
                    StationRow(
                        station: station,
                        isCurrent: store.currentStation?.id == station.id,
                        isPlaying: store.currentStation?.id == station.id && store.player.isPlaying
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.primaryBackground.opacity(0.4))
                .contextMenu {
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    .preferredColorScheme(.dark)
}
