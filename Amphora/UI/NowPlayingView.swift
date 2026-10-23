import PandoraCore
import SwiftUI

/// Full-screen player: artwork, title/artist, scrubber, transport
/// controls and the station name. Presented from the mini-player.
struct NowPlayingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(store.currentStation?.name ?? "Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let track = store.player.currentTrack {
            VStack(spacing: 24) {
                artwork(for: track)
                    .padding(.horizontal, 32)

                VStack(spacing: 6) {
                    Text(track.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(track.artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                scrubber

                transport

                if let message = store.player.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 24)
        } else {
            ContentUnavailableView(
                "Nothing playing",
                systemImage: "music.note",
                description: Text("Pick a station to start listening.")
            )
        }
    }

    private func artwork(for track: Track) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.quaternary.opacity(0.5))
            if let urlString = track.artworkUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallbackIcon
                }
            } else {
                fallbackIcon
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: "music.note")
            .font(.system(size: 64))
            .foregroundStyle(.secondary)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { store.player.elapsed },
                    set: { store.player.seek(to: $0) }
                ),
                in: 0...max(store.player.duration, 1)
            )
            .disabled(store.player.duration <= 0)
            .accessibilityLabel("Playback position")
            HStack {
                Text(Self.timeString(store.player.elapsed))
                Spacer()
                Text(Self.timeString(store.player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            Button {
                store.player.skipBackward(by: 15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back 15 seconds")

            Button {
                store.send(.togglePlayback)
            } label: {
                Image(systemName: store.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.player.isPlaying ? "Pause" : "Play")

            Button {
                store.send(.skipToNext)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }

    /// `m:ss` (or `h:mm:ss` for long tracks).
    private static func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
