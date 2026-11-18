//
//  CurrentLyricStrip.swift
//  Amphora
//
//  BitChord's strip: the single sung line riding above the scrubber
//  while the lyrics panel is closed — the reader sees the words
//  without leaving the player. Clock-driven on the same interpolated
//  playhead the panel scrolls on (`LyricClock`), so it follows the
//  song continuously; tapping it opens the lyrics. Radio's identified
//  song works like any track — its synthetic-track lyrics ride the
//  same store path — and nothing shows while lyrics are unavailable
//  or the song has none.
//

import PandoraCore
import SwiftUI

struct CurrentLyricStrip: View {
    @Environment(AppStore.self) private var store
    var onOpenLyrics: (() -> Void)?

    var body: some View {
        Group {
            if let lyrics = store.lyrics, lyrics.isSynced {
                TimelineView(.animation(paused: !store.player.isPlaying)) { context in
                    let index = lyrics.activeLineIndex(
                        at: LyricClock.elapsed(at: context.date, in: store.player)
                    )
                    // A fixed strip: the scrubber never shifts when a
                    // line ends and the next has not started yet.
                    ZStack {
                        if let index {
                            Text(lyrics.lines[index].text)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.light()
                    onOpenLyrics?()
                }
                .accessibilityLabel("Current lyric line")
                .accessibilityHint("Double-tap to open the lyrics")
            }
        }
    }
}
