import PandoraCore
import SwiftUI

/// Compact player card floating above the tab bar while something plays:
/// rounded surface, a progress hairline along its top edge, artwork,
/// title/artist, play and skip. The full-player sheet is owned by
/// `MainTabView` (one instance for the whole shell), so tab switches
/// never tear it down — the card itself only reports taps through
/// `onOpen`.
struct MiniPlayer: View {
    @Environment(AppStore.self) private var store
    let onOpen: () -> Void

    private var track: Track? { store.player.currentTrack }

    var body: some View {
        card
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private var card: some View {
        HStack(spacing: 12) {
            Button {
                onOpen()
            } label: {
                HStack(spacing: 12) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track?.title ?? "")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(track?.artist ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open now playing")

            Button {
                Haptics.light()
                store.send(.togglePlayback)
            } label: {
                Image(systemName: store.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(store.player.isPlaying ? "Pause" : "Play")

            Button {
                Haptics.medium()
                store.send(.skipToNext)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Next track")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        )
        .overlay(alignment: .top) {
            MiniPlayerProgress()
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Theme.stroke)
        )
        .accessibilityElement(children: .contain)
    }

    private var artwork: some View {
        CachedArtwork(urlString: track?.artworkUrl, cornerRadius: Theme.radiusS + 2)
            .frame(width: 44, height: 44)
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
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.accent, Theme.violet],
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
