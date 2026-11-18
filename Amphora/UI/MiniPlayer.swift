import PandoraCore
import SwiftUI
import UIKit

/// Compact player card floating above the tab bar while something plays —
/// BitChord's frosted pill, adapted: a fully-rounded `.ultraThinMaterial`
/// bar with a hairline edge, edge-fading titles (no marquee), a
/// horizontal swipe that skips, and a vertical pull whose bar lifts
/// toward the opening player. The full-player sheet is owned by
/// `MainTabView` (one instance for the whole shell), so tab switches
/// never tear it down — the card itself only reports taps through
/// `onOpen`.
///
/// The card keeps its AirPlay route picker, so the output can be
/// switched from any screen without opening the full player, and it
/// names the device the audio is playing on whenever that is not the
/// phone's own speaker.
///
/// Pandora variations: a radio stream is skipped by neither gesture —
/// it has no next track to swipe to, and stopping the stream must stay
/// a deliberate button press.
struct MiniPlayer: View {
    @Environment(AppStore.self) private var store
    let onOpen: () -> Void

    /// The live vertical pull — the bar follows the finger upward on a
    /// damped rubber-band curve and springs home on release.
    @GestureState private var pull: CGFloat = 0

    private var track: Track? { store.player.currentTrack }
    private var isRadio: Bool { track?.isRadio == true }

    var body: some View {
        card
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private var card: some View {
        HStack(spacing: 10) {
            openButton
            AirPlayRoutePicker(
                tint: UIColor.secondaryLabel,
                activeTint: UIColor(Theme.accentText)
            )
            .frame(width: 44, height: 44)
            .accessibilityLabel("AirPlay")
            playButton
            nextButton
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.5)
        )
        .overlay(alignment: .top) {
            MiniPlayerProgress()
                .clipShape(Capsule(style: .continuous))
        }
        // BitChord's pull: the bar rises with the finger on a decaying
        // curve, then springs home when the sheet takes over.
        .offset(y: pull * 0.6 * 72 / (72 + abs(pull)))
        .animation(.spring(duration: 0.4, bounce: 0.3), value: pull)
        .gesture(cardGesture)
        .accessibilityElement(children: .contain)
    }

    /// The tappable half: artwork and the two fading lines. Taps open
    /// the full player; the pull gesture on the whole card is the
    /// muscle-memory route.
    private var openButton: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if store.player.outputRouteName != nil {
                            Image(systemName: RouteSymbol.name(isAirPlay: store.player.isAirPlayActive))
                                .font(.caption2)
                                .foregroundStyle(Theme.accentText)
                        }
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(
                                store.player.outputRouteName == nil
                                    ? Color.secondary
                                    : Theme.accentText
                            )
                            .lineLimit(1)
                    }
                }
                .mask(textFadeMask)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressableButtonStyle())
        .accessibilityLabel("Open now playing")
    }

    /// The edge fade — BitChord's `fadeOverflow` instead of a marquee.
    /// The gradient is applied to the *column*, not the texts, so a
    /// short title never touches the fade zone: the mask's slope only
    /// engages where the layout width runs out.
    private var textFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.88),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var playButton: some View {
        Button {
            Haptics.light()
            store.send(.togglePlayback)
        } label: {
            ZStack {
                if store.player.isPlaying {
                    TransportGlyph(.pause, size: 17, color: Theme.accentGlyph.opacity(0.85))
                } else {
                    TransportGlyph(.play, size: 17, color: Theme.accentGlyph.opacity(0.85))
                }
            }
            .frame(width: 34, height: 34)
            .background(Theme.accent, in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.snappy(duration: 0.2), value: store.player.isPlaying)
        .frame(width: 44, height: 44)
        .accessibilityLabel(store.player.isPlaying ? "Pause" : "Play")
    }

    private var nextButton: some View {
        Button {
            Haptics.medium()
            // A radio stream has no next track — the button stops it
            // instead. The swipe gesture below stays inert on radio.
            if isRadio {
                store.send(.stopRadio)
            } else {
                store.send(.skipToNext)
            }
        } label: {
            TransportGlyph(isRadio ? .stop : .next, size: 17)
        }
        .buttonStyle(PressableButtonStyle())
        .frame(width: 44, height: 44)
        .accessibilityLabel(isRadio ? "Stop radio" : "Next track")
    }

    /// One detector for both axes, decided at release — BitChord's
    /// single `pointerInput`: a deliberate leftward swipe skips to the
    /// next track (never on radio), an upward pull opens the player.
    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .updating($pull) { value, state, _ in
                state = min(0, value.translation.height)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > abs(vertical) {
                    guard !isRadio, horizontal < -72 else { return }
                    Haptics.medium()
                    store.send(.skipToNext)
                } else if vertical < -60 {
                    Haptics.light()
                    onOpen()
                }
            }
    }

    /// A radio stream has no album art — it has a favicon, which is
    /// usually a 16×16 icon or missing entirely. The generated station
    /// tile covers both cases.
    @ViewBuilder
    private var artwork: some View {
        Group {
            if let track, track.isRadio {
                RadioStationArtwork(
                    stationName: track.title,
                    faviconURL: track.artworkUrl,
                    cornerRadius: Theme.radiusS + 2,
                    minimumArtworkPixels: 64
                )
            } else {
                CachedArtwork(urlString: track?.artworkUrl, cornerRadius: Theme.radiusS + 2)
            }
        }
        .frame(width: 40, height: 40)
    }

    /// The card's second line: the artist normally, the name of the
    /// device the music is playing on while the audio is routed
    /// somewhere else.
    private var caption: String {
        store.player.outputRouteName ?? track?.artist ?? ""
    }
}

/// The card's top-edge progress hairline. Deliberately its own view:
/// `@Observable` tracks per-property, so the per-tick `elapsed` read
/// re-renders only this 2.5 pt strip, never the card's content.
private struct MiniPlayerProgress: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { geo in
            let fraction = store.player.duration > 0
                ? min(1, max(0, store.player.elapsed / store.player.duration))
                : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.progressTrack)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.accent, Theme.accentSecondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 2.5)
        .accessibilityHidden(true)
    }
}
