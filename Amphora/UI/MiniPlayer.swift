import PandoraCore
import SwiftUI

/// Compact player bar shown above the tab bar while something plays.
/// Shows the current track, a play/pause button and a skip button.
struct MiniPlayer: View {
    @Environment(AppStore.self) private var store

    @State private var isShowingNowPlaying = false

    private var track: Track? { store.player.currentTrack }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isShowingNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track?.title ?? "")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(track?.artist ?? "")
                            .font(.caption)
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
                store.send(.togglePlayback)
            } label: {
                Image(systemName: store.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.player.isPlaying ? "Pause" : "Play")
            Button {
                store.send(.skipToNext)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView()
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.5))
            if let urlString = track?.artworkUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallbackIcon
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: "music.note")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
