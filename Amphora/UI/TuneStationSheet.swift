import PandoraCore
import SwiftUI

/// "Tune your station": Pandora's listening modes (My Mix / Deep Cuts /
/// Crowd Faves / Discovery …). Free accounts can select every mode
/// Pandora marks available; the premium-only mode is shown disabled.
/// Opened from the full player (`station: nil` → the playing station —
/// a successful change starts a new song) and from the station list's
/// context menu (tunes that station for its next play). Either way the
/// sheet dismisses itself on the change tick.
struct TuneStationSheet: View {
    let station: Station?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let modes = store.stationModes {
                    if !modes.isInteractiveRadioAvailable || modes.modes.isEmpty {
                        ContentUnavailableView(
                            "No tuning options",
                            systemImage: "slider.horizontal.3",
                            description: Text("Pandora does not offer modes for this station.")
                        )
                    } else {
                        modeList(modes)
                    }
                } else if store.isLoadingModes {
                    ProgressView("Loading modes…")
                } else if let message = store.lastErrorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load modes", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { store.send(.loadStationModes(station)) }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Tune Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { store.send(.loadStationModes(station)) }
        .onChange(of: store.stationModeChangedTick) {
            dismiss()
        }
    }

    private func modeList(_ modes: StationModes) -> some View {
        List {
            Section(footer: Text(store.isChangingMode ? "Changing mode…" : "Changing modes starts a new song.")) {
                ForEach(modes.modes) { mode in
                    row(mode)
                }
            }
            if let message = store.lastErrorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ mode: StationMode) -> some View {
        let selectable = mode.isSelectable(isSubscriber: store.isSubscriber)
        let isCurrent = store.stationModes?.currentModeID == mode.id
        Button {
            store.send(.setStationMode(mode, for: station))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mode.name)
                        if mode.isPremiumOnly && !store.isSubscriber {
                            Text("Premium")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    if !mode.modeDescription.isEmpty {
                        Text(mode.modeDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .disabled(!selectable || store.isChangingMode)
        .foregroundStyle(selectable ? Color.primary : Color.secondary)
        .accessibilityLabel("\(mode.name)\(isCurrent ? ", current" : "")")
        .accessibilityHint(selectable ? "Changes the station mode" : "Unavailable")
    }
}
