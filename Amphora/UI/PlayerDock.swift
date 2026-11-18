//
//  PlayerDock.swift
//  Amphora
//
//  The player's frosted dock row — BitChord's PlayerActionRow, adapted:
//  four frosted discs under the transport that own the secondary
//  toggles (lyrics, queue, sleep timer, output), so the toolbar above
//  stays ellipsis + Done. Active states are carried by the discs
//  themselves: the panel that is open, the timer that is running.
//
//  Pandora variations: a live radio stream has no queue (its disc is
//  not offered) and no lyrics unless the station's current song has
//  been identified; the sleep timer and the output picker always
//  apply. The sleep-timer sheet is owned by `NowPlayingView` — the
//  disc only reports the intent, keeping sheet ownership in one place.
//

import PandoraCore
import SwiftUI
import UIKit

struct PlayerDock: View {
    @Environment(AppStore.self) private var store
    @Binding var isShowingLyrics: Bool
    @Binding var isShowingQueue: Bool
    let onSleepTimer: () -> Void

    private var theme: ArtworkThemeController { ArtworkThemeController.shared }

    private var track: Track? { store.player.currentTrack }
    private var isRadio: Bool { track?.isRadio == true }

    var body: some View {
        HStack(spacing: 24) {
            if lyricsAvailable { lyricsDisc }
            if !isRadio { queueDisc }
            sleepDisc
            outputDisc
        }
        .frame(maxWidth: .infinity)
    }

    /// A radio stream has no lyrics — unless the station's current
    /// song has been identified; its lyrics are looked up like any
    /// song's (the rule the toolbar bubble carried, moved here).
    private var lyricsAvailable: Bool {
        !isRadio || store.radioIdentification == .identified
    }

    private var lyricsDisc: some View {
        dockDisc(
            symbol: isShowingLyrics ? "quote.bubble.fill" : "quote.bubble",
            label: isShowingLyrics ? "Hide lyrics" : "Show lyrics",
            isActive: isShowingLyrics
        ) {
            withAnimation(Self.panelAnimation) { isShowingLyrics.toggle() }
            if isShowingLyrics { withAnimation(Self.panelAnimation) { isShowingQueue = false } }
        }
    }

    private var queueDisc: some View {
        dockDisc(
            symbol: "music.note.list",
            label: isShowingQueue ? "Hide queue" : "Show queue",
            isActive: isShowingQueue
        ) {
            withAnimation(Self.panelAnimation) { isShowingQueue.toggle() }
            if isShowingQueue { withAnimation(Self.panelAnimation) { isShowingLyrics = false } }
        }
    }

    private var sleepDisc: some View {
        dockDisc(
            symbol: "moon.zzz",
            label: store.sleepTimer.isOff
                ? "Sleep Timer…"
                : "Sleep Timer (\(store.sleepTimerLabel))…",
            isActive: !store.sleepTimer.isOff
        ) {
            onSleepTimer()
        }
    }

    /// The system route picker riding a frosted disc, in the dock slot
    /// BitChord gives the output picker — the toolbar AirPlay item is
    /// gone; the mini player keeps its own.
    private var outputDisc: some View {
        AirPlayRoutePicker(
            tint: UIColor(Color.primary),
            activeTint: UIColor(theme.colors.accent.color)
        )
        .frame(width: 44, height: 44)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityLabel("Audio output")
    }

    private func dockDisc(
        symbol: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(isActive ? theme.colors.accent.color : Color.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        isActive
                            ? theme.colors.accent.color.opacity(0.45)
                            : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// BitChord's panel travel clock: the 420 ms tween the queue and
    /// the lyrics panel ride, and the artwork sleeve easing.
    static let panelAnimation = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.42)
}
