import PandoraCore
import SwiftUI

/// Full-screen player: ambient artwork-derived gradient, large rounded
/// artwork, custom scrubber, transport and feedback. Every color comes
/// from `Theme` + the artwork palette (`ArtworkThemeController`) — flat
/// fills only, no system materials, so the Android port matches exactly.
/// Presented from the mini-player.
struct NowPlayingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The shared ambient theme. Reading the singleton's `@Observable`
    /// state from body is tracked like any environment dependency.
    private var theme: ArtworkThemeController { ArtworkThemeController.shared }

    @State private var isShowingSleepTimer = false
    @State private var isShowingTuning = false
    @State private var isShowingLyrics = false
    @State private var isShowingUpNext = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.playerBackground(theme.colors).ignoresSafeArea()
                AmbientGlow(color: theme.colors.accent.color)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                content
            }
            .navigationTitle(store.currentStation?.name ?? "Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingLyrics.toggle()
                    } label: {
                        Image(systemName: isShowingLyrics ? "quote.bubble.fill" : "quote.bubble")
                    }
                    .accessibilityLabel(isShowingLyrics ? "Hide lyrics" : "Show lyrics")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSleepTimer = true
                    } label: {
                        Image(systemName: store.sleepTimer.isOff ? "moon.zzz" : "moon.zzz.fill")
                    }
                    .accessibilityLabel(
                        store.sleepTimer.isOff
                            ? "Sleep timer"
                            : "Sleep timer, \(store.sleepTimerLabel)"
                    )
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingTuning = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Tune station")
                }
            }
            .sheet(isPresented: $isShowingSleepTimer) {
                SleepTimerSheet()
            }
            .sheet(isPresented: $isShowingTuning) {
                TuneStationSheet(station: nil)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let track = store.player.currentTrack {
            if isShowingLyrics {
                // The lyrics panel scrolls itself; the transport stays fixed.
                VStack(spacing: 20) {
                    LyricsPanel()
                    fixedControls(for: track)
                }
                .padding(.bottom, 24)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        artwork(for: track)
                        trackHeader(track)
                        scrubber
                    }
                    .padding(.top, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    fixedControls(for: track)
                }
            }
        } else {
            ContentUnavailableView(
                "Nothing playing",
                systemImage: "music.note",
                description: Text("Pick a station to start listening.")
            )
        }
    }

    /// Everything below the artwork/lyrics region: ad badge, transport,
    /// feedback, up next, confirmations, errors.
    private func fixedControls(for track: Track) -> some View {
        VStack(spacing: 18) {
            adBadge(track)
            transport
            if !track.isAdvertisement {
                FeedbackBar(accent: theme.colors.accent)
                bookmarkButtons
            }
            upNext
            confirmation
            if let message = store.player.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func artwork(for track: Track) -> some View {
        CachedArtwork(
            urlString: track.artworkUrl,
            cornerRadius: Theme.radiusArtwork,
            fallbackSystemImage: "music.note"
        )
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusArtwork, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .shadow(color: theme.colors.accent.color.opacity(0.18), radius: 40, y: 8)
        .padding(.horizontal, 28)
    }

    private func trackHeader(_ track: Track) -> some View {
        VStack(spacing: 6) {
            Text(track.title)
                .font(Font.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(track.artist)
                .font(.headline)
                .foregroundStyle(theme.colors.accent.color.opacity(0.9))
                .lineLimit(1)
            if !track.album.isEmpty {
                Text(track.album)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            PlayerScrubber(
                elapsed: store.player.elapsed,
                duration: store.player.duration,
                accent: theme.colors.accent.color,
                onSeek: { store.player.seek(to: $0) }
            )
            HStack {
                Text(AmphoraTimeFormat.string(store.player.elapsed))
                Spacer()
                Text(AmphoraTimeFormat.string(store.player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func adBadge(_ track: Track) -> some View {
        if track.isAdvertisement {
            // pydora's player prints "Advertisement" — the slot is
            // labeled, unratable and unskippable by protocol.
            Text("ADVERTISEMENT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.yellow)
                .tracking(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.14), in: Capsule())
        }
    }

    private var transport: some View {
        HStack(spacing: 32) {
            Button {
                Haptics.light()
                store.player.skipBackward(by: 15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back 15 seconds")

            Button {
                Haptics.light()
                store.send(.togglePlayback)
            } label: {
                Image(systemName: store.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.colors.accent.isLight
                                     ? Color.black.opacity(0.85)
                                     : Color.white)
                    .frame(width: 74, height: 74)
                    .background(theme.colors.accent.color, in: Circle())
                    .shadow(
                        color: theme.colors.accent.color.opacity(0.35),
                        radius: 14, y: 5
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.player.isPlaying ? "Pause" : "Play")

            Button {
                Haptics.medium()
                store.send(.skipToNext)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.colors.accent.color)
                    .frame(width: 48, height: 48)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }

    private var bookmarkButtons: some View {
        HStack(spacing: 16) {
            capsuleBookmark(
                "Song",
                icon: "bookmark",
                action: .bookmarkCurrentSong,
                accessibilityLabel: "Bookmark this song"
            )
            capsuleBookmark(
                "Artist",
                icon: "person.crop.circle.badge.plus",
                action: .bookmarkCurrentArtist,
                accessibilityLabel: "Bookmark this artist"
            )
        }
    }

    private func capsuleBookmark(
        _ title: String,
        icon: String,
        action: AppStore.Intent,
        accessibilityLabel: String
    ) -> some View {
        Button {
            Haptics.light()
            store.send(action)
        } label: {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.medium))
                .frame(minWidth: 104, minHeight: 40)
        }
        .foregroundStyle(.primary)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .accessibilityLabel(accessibilityLabel)
    }

    /// A short, self-dismissing confirmation ("Song bookmarked") — the
    /// user can see that a button did something.
    @ViewBuilder
    private var confirmation: some View {
        if let message = store.confirmationMessage {
            Text(message)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.surfaceHighlight, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityAddTraits(.isStaticText)
        }
    }

    /// Pithos-style "Up Next": the next few tracks the queue will play.
    /// Collapsed to a one-line header (with the immediate next title);
    /// expanding reveals up to four rows. Hidden while nothing is queued.
    @ViewBuilder
    private var upNext: some View {
        let upcoming = Array(store.player.upcomingTracks.prefix(4))
        if !upcoming.isEmpty {
            DisclosureGroup(isExpanded: $isShowingUpNext) {
                ForEach(upcoming) { track in
                    HStack(spacing: 12) {
                        CachedArtwork(
                            urlString: track.artworkUrl,
                            cornerRadius: 6,
                            fallbackSystemImage: "music.note"
                        )
                        .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if track.isAdvertisement {
                            Text("AD")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Up Next")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.colors.accent.color)
                    Text(upcoming.first?.title ?? "")
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityLabel(
                "Up next: \(upcoming.map(\.title).joined(separator: ", "))"
            )
        }
    }
}

/// A soft ellipse of the artwork accent above the player's gradient —
/// the "light in the room" effect. Static per track (no per-tick state),
/// so the blur renders once.
private struct AmbientGlow: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Ellipse()
                .fill(color.opacity(0.20))
                .frame(width: geo.size.width * 1.1, height: geo.size.width * 0.9)
                .blur(radius: 80)
                .offset(y: -geo.size.height * 0.18)
        }
    }
}
