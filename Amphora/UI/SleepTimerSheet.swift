import PandoraCore
import SwiftUI

/// Sleep-timer control: pick a duration or "end of track".
struct SleepTimerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Offered durations in minutes.
    private let durations = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(durations, id: \.self) { minutes in
                        Button {
                            store.send(.setSleepTimer(SleepTimer(minutes: minutes)))
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(minutes) minutes")
                                Spacer()
                                Image(systemName: "moon.zzz")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button {
                        store.send(.setSleepTimer(SleepTimer(endOfTrack: true)))
                        dismiss()
                    } label: {
                        HStack {
                            Text("End of current track")
                            Spacer()
                            Image(systemName: "forward.end")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !store.sleepTimer.isOff {
                        Button(role: .destructive) {
                            store.send(.cancelSleepTimer)
                            dismiss()
                        } label: {
                            Text("Cancel timer")
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
