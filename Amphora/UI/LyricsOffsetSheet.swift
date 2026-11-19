//
//  LyricsOffsetSheet.swift
//  Amphora
//
//  BitChord's offset sheet: a provider's sync can run slightly ahead
//  of or behind the audio, and singers notice half-second drift that
//  no provider call can fix. The slider nudges the lyrics clock live
//  (the lines follow every step in memory); the offset is persisted
//  once, on dismissal, through the store's intent — the volume
//  slider's pattern.
//

import SwiftUI

struct LyricsOffsetSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The sheet's own draft while dragging — the store's live value
    /// follows every step, the disk write happens once via the intent.
    @State private var draft: TimeInterval = 0

    /// BitChord's range: five seconds is generous for sync drift.
    private let range: ClosedRange<Double> = -5...5

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // The live value, big enough to read while singing.
                Text(offsetLabel(draft))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: draft)
                Slider(
                    value: Binding(
                        get: { draft },
                        set: { newValue in
                            let stepped = (newValue * 10).rounded() / 10
                            draft = stepped
                            store.setLyricsOffsetLive(stepped)
                        }
                    ),
                    in: range,
                    onEditingChanged: { editing in
                        // The drag end persists once, like the volume
                        // slider's pattern.
                        if !editing {
                            store.send(.setLyricsOffset(draft))
                        }
                    }
                )
                .tint(Theme.accent)
                HStack {
                    Text("−5 s")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("+5 s")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                Text(
                    "Slide right if the lyrics run behind the song, left if they run ahead. "
                        + "The timing is remembered for every song."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                if draft != 0 {
                    Button("Reset to 0") {
                        draft = 0
                        store.setLyricsOffsetLive(0)
                        store.send(.setLyricsOffset(0))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Lyrics Timing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        // Persist exactly where the slider rests.
                        store.setLyricsOffsetLive(draft)
                        store.send(.setLyricsOffset(draft))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { draft = store.lyricsOffset }
    }

    /// "+1.2 s" — the sign is the point.
    private func offsetLabel(_ value: TimeInterval) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
        return String(format: "%@%.1f s", sign, abs(value))
    }
}
