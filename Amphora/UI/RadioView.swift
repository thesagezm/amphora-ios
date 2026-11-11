import PandoraCore
import SwiftUI

/// The Radio tab — internet radio from the radio-browser directory (the
/// Shortwave port, user request 2026-11-07). The root shows recently
/// played stations, favorites, and discovery entries (popular / country /
/// tag); typing in the search field swaps the root for live results.
/// All directory fetching lives in `RadioController` (`store.radio`) —
/// this view only renders state and dispatches intents to `AppStore`.
struct RadioView: View {
    @Environment(AppStore.self) private var store

    @State private var isAddingStation = false
    @State private var editingStation: RadioStation?

    private var radio: RadioController { store.radio }

    var body: some View {
        Group {
            if radio.searchText.isEmpty {
                homeList
                    .miniPlayer()
            } else {
                RadioResultsView()
            }
        }
        .navigationTitle("Radio")
        .searchable(text: searchBinding, prompt: "Search radio stations")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingStation = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add custom station")
            }
        }
        .sheet(isPresented: $isAddingStation) {
            RadioStationFormSheet(existing: nil)
        }
        .sheet(item: $editingStation) { station in
            RadioStationFormSheet(existing: station)
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { store.radio.searchText },
            set: { store.radio.searchText = $0 }
        )
    }

    // MARK: Home (recents, favorites, discovery)

    private var homeList: some View {
        List {
            // The landing centerpiece: the last-played station, large
            // and centered — the same hero the Home tab carries, for
            // radio (user request 2026-11-10). Hidden until something
            // has played.
            radioHero

            // Custom stations the user added by URL — editable and
            // deletable via the row's context menu.
            if !store.radioCustomStations.isEmpty {
                Section("My Stations") {
                    ForEach(store.radioCustomStations) { station in
                        stationButton(station)
                            .amphoraCardRow(tinted: isCurrent(station))
                            .contextMenu {
                                Button {
                                    editingStation = station
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.send(.deleteRadioCustomStation(station))
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            if !store.radioRecents.isEmpty {
                Section {
                    ForEach(store.radioRecents) { station in
                        stationButton(station)
                            .amphoraCardRow(tinted: isCurrent(station))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.send(.removeRadioRecent(station))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("Recently Played")
                        Spacer()
                        Button("Clear") {
                            store.send(.clearRadioRecents)
                        }
                        .font(.footnote)
                        .accessibilityLabel("Clear recently played radio stations")
                    }
                }
            }
            if !store.radioFavorites.isEmpty {
                Section("Favorites") {
                    ForEach(store.radioFavorites) { station in
                        stationButton(station)
                            .amphoraCardRow(tinted: isCurrent(station))
                    }
                }
            }
            Section("Discover") {
                NavigationLink {
                    RadioStationListView(mode: .popular)
                } label: {
                    discoverRow("Popular", "The directory's most upvoted stations", "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(RowPressableButtonStyle())
                .amphoraCardRow()

                NavigationLink {
                    RadioCountryListView()
                } label: {
                    discoverRow("Countries", "Browse stations by country", "globe")
                }
                .buttonStyle(RowPressableButtonStyle())
                .amphoraCardRow()

                NavigationLink {
                    RadioTagListView()
                } label: {
                    discoverRow("Tags", "Browse stations by genre tag", "tag")
                }
                .buttonStyle(RowPressableButtonStyle())
                .amphoraCardRow()
            }
        }
        .listStyle(.plain)
        .amphoraListBackground()
    }

    private func isCurrent(_ station: RadioStation) -> Bool {
        store.currentRadioStation?.uuid == station.uuid
    }

    /// The last-played radio station as the landing page's centerpiece:
    /// the station's tile large and centered, the name, and a play/
    /// pause button — the Home tab's hero, for radio. The store toggles
    /// playback when the tapped station is the one playing, so the
    /// button doubles as pause. Hidden until something has played.
    @ViewBuilder
    private var radioHero: some View {
        if let station = store.radioRecents.first {
            let isPlaying = isCurrent(station) && store.player.isPlaying
            VStack(spacing: 16) {
                RadioStationArtwork(
                    stationName: station.name,
                    faviconURL: station.faviconURL,
                    cornerRadius: Theme.radiusL,
                    minimumArtworkPixels: 200
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.40), radius: 22, y: 10)

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
                .accessibilityElement(children: .combine)

                Button {
                    Haptics.light()
                    store.send(.playRadioStation(station))
                } label: {
                    ZStack {
                        if isPlaying {
                            TransportGlyph(.pause, size: 23, color: Theme.accentGlyph)
                        } else {
                            TransportGlyph(.play, size: 23, color: Theme.accentGlyph)
                        }
                    }
                    .frame(width: 58, height: 58)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 5)
                }
                .buttonStyle(PressableButtonStyle())
                .animation(.snappy(duration: 0.2), value: isPlaying)
                .accessibilityLabel(
                    isPlaying ? "Pause \(station.name)" : "Play \(station.name)"
                )
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// A station row as a play button — tapping plays (or toggles) the
    /// live stream via the store.
    private func stationButton(_ station: RadioStation) -> some View {
        Button {
            Haptics.light()
            store.send(.playRadioStation(station))
        } label: {
            RadioStationRow(station: station, isCurrent: isCurrent(station))
        }
        .buttonStyle(RowPressableButtonStyle())
    }

    private func discoverRow(_ title: String, _ caption: String, _ systemImage: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(Theme.accentText)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(caption)
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
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Station results (search root + pushed lists)

/// The controller's current `results` with loading / error / empty
/// states. Used directly for search results at the tab root and wrapped
/// by `RadioStationListView` for the pushed discovery lists.
private struct RadioResultsView: View {
    @Environment(AppStore.self) private var store

    private var radio: RadioController { store.radio }

    var body: some View {
        Group {
            if !radio.results.isEmpty {
                resultsList
            } else if radio.isLoading || !radio.didLoadResults {
                ProgressView("Loading stations…")
                    .tint(.secondary)
                    .accessibilityLabel("Loading stations")
            } else if let message = radio.errorMessage {
                errorState(message)
            } else {
                ContentUnavailableView {
                    Label("No stations", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Nothing matched here. Try another search or browse.")
                }
            }
        }
        .miniPlayer()
    }

    private var resultsList: some View {
        List(radio.results) { station in
            let isCurrent = store.currentRadioStation?.uuid == station.uuid
            Button {
                Haptics.light()
                store.send(.playRadioStation(station))
            } label: {
                RadioStationRow(station: station, isCurrent: isCurrent)
            }
            .buttonStyle(RowPressableButtonStyle())
            .amphoraCardRow(tinted: isCurrent)
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
                if let mode = radio.activeMode {
                    radio.show(mode)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// A pushed discovery list (popular / one country / one tag): triggers
/// the load on appear and renders the shared results states.
private struct RadioStationListView: View {
    @Environment(AppStore.self) private var store
    let mode: RadioController.Mode

    var body: some View {
        RadioResultsView()
            .navigationTitle(mode.title)
            .onAppear {
                store.radio.show(mode)
            }
    }
}

// MARK: - Catalog lists (countries, tags)

private struct RadioCountryListView: View {
    @Environment(AppStore.self) private var store

    private var radio: RadioController { store.radio }

    var body: some View {
        Group {
            if let countries = radio.countries {
                if countries.isEmpty {
                    ContentUnavailableView(
                        "No countries",
                        systemImage: "globe",
                        description: Text("The directory returned no countries.")
                    )
                } else {
                    List(countries) { country in
                        NavigationLink {
                            RadioStationListView(mode: .country(code: country.code, name: country.name))
                        } label: {
                            catalogRow(
                                title: country.name.isEmpty ? country.code : country.name,
                                caption: "\(country.stationCount) stations",
                                systemImage: "globe"
                            )
                        }
                        .buttonStyle(RowPressableButtonStyle())
                        .amphoraCardRow()
                    }
                    .listStyle(.plain)
                    .amphoraListBackground()
                }
            } else if radio.isLoading {
                ProgressView("Loading countries…")
                    .tint(.secondary)
                    .accessibilityLabel("Loading countries")
            } else if let message = radio.errorMessage {
                errorState(message) { radio.retryCountries() }
            } else {
                ProgressView("Loading countries…")
                    .tint(.secondary)
                    .accessibilityLabel("Loading countries")
            }
        }
        .miniPlayer()
        .navigationTitle("Countries")
        .onAppear {
            radio.loadCountries()
        }
    }

    private func errorState(_ message: String, retry: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label("Couldn't load countries", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }

    private func catalogRow(title: String, caption: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(Theme.accentText)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(caption)
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
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct RadioTagListView: View {
    @Environment(AppStore.self) private var store

    private var radio: RadioController { store.radio }

    var body: some View {
        Group {
            if let tags = radio.tags {
                if tags.isEmpty {
                    ContentUnavailableView(
                        "No tags",
                        systemImage: "tag",
                        description: Text("The directory returned no tags.")
                    )
                } else {
                    List(tags) { tag in
                        NavigationLink {
                            RadioStationListView(mode: .tag(tag.name))
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.accent.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "tag")
                                            .font(.body)
                                            .foregroundStyle(Theme.accentText)
                                    )
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(tag.stationCount) stations")
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
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressableButtonStyle())
                        .amphoraCardRow()
                    }
                    .listStyle(.plain)
                    .amphoraListBackground()
                }
            } else if radio.isLoading {
                ProgressView("Loading tags…")
                    .tint(.secondary)
                    .accessibilityLabel("Loading tags")
            } else if let message = radio.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load tags", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { radio.retryTags() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Loading tags…")
                    .tint(.secondary)
                    .accessibilityLabel("Loading tags")
            }
        }
        .miniPlayer()
        .navigationTitle("Tags")
        .onAppear {
            radio.loadTags()
        }
    }
}

// MARK: - Station row

/// One directory station: favicon, name, caption (country · codec ·
/// bitrate), a playing indicator for the live stream, and the star
/// toggle for favorites. The row itself is wrapped in a play button by
/// the callers; the star is a nested button and takes its own taps.
private struct RadioStationRow: View {
    @Environment(AppStore.self) private var store
    let station: RadioStation
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            // The station's real favicon when it exists and is big
            // enough for this slot; otherwise the generated monogram
            // tile — a bare antenna glyph read as "no artwork".
            RadioStationArtwork(
                stationName: station.name,
                faviconURL: station.faviconURL,
                cornerRadius: Theme.radiusS,
                minimumArtworkPixels: 64
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCurrent ? Theme.accentText : Color.primary)
                    .lineLimit(1)
                if !station.caption.isEmpty {
                    Text(station.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if isCurrent, store.player.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Playing")
            }

            let isFavorite = store.isRadioFavorite(station)
            Button {
                Haptics.light()
                store.send(.toggleRadioFavorite(station))
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(isFavorite ? Theme.accentText : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(
                isFavorite
                    ? "Remove \(station.name) from favorites"
                    : "Add \(station.name) to favorites"
            )
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        // .contain, not .combine — the star stays its own VoiceOver
        // element beside the row's play action.
        .accessibilityElement(children: .contain)
    }
}
