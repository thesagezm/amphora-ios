import PandoraCore
import SwiftUI

/// Full-screen player, Apple-Music-shaped: large rounded artwork, a
/// left-aligned title block with the stream quality beside it, a thin
/// scrubber, and a plain-glyph transport that answers every touch with
/// a soft spring. Secondary actions (sleep timer, tuning, bookmarks,
/// hide-song) live behind the toolbar's ellipsis menu — one sleep
/// control, no duplicate moons. The ambient backdrop still comes from
/// the artwork palette (`ArtworkThemeController`); every static
/// surface is a matte palette shade, never glass.
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
                ToolbarItem(placement: .topBarLeading) {
                    actionsMenu
                }
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

    /// Every secondary action in one Apple-Music-style place. This is
    /// also the app's only sleep-timer surface entry — the duplicate
    /// moon icon on the main surface is gone.
    private var actionsMenu: some View {
        Menu {
            Button {
                isShowingSleepTimer = true
            } label: {
                Label(
                    store.sleepTimer.isOff
                        ? "Sleep Timer…"
                        : "Sleep Timer (\(store.sleepTimerLabel))…",
                    systemImage: "moon.zzz"
                )
            }
            Button {
                isShowingTuning = true
            } label: {
                Label("Tune Station…", systemImage: "slider.horizontal.3")
            }
            Divider()
            Button {
                Haptics.light()
                store.send(.bookmarkCurrentSong)
            } label: {
                Label("Bookmark Song", systemImage: "bookmark")
            }
            Button {
                Haptics.light()
                store.send(.bookmarkCurrentArtist)
            } label: {
                Label("Bookmark Artist", systemImage: "person.crop.circle.badge.plus")
            }
            Divider()
            Button {
                Haptics.light()
                store.send(.sleepCurrentTrack)
            } label: {
                Label("Hide This Song", systemImage: "ear.slash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More actions")
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
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .shadow(color: theme.colors.accent.color.opacity(0.18), radius: 40, y: 8)
        .padding(.horizontal, 28)
    }

    /// Apple-Music-style block: left-aligned title, artist in the
    /// artwork accent, album beneath, and the stream quality as a matte
    /// chip on the trailing edge.
    private func trackHeader(_ track: Track) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(Font.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(2)
                Text(track.artist)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.colors.accent.color.opacity(0.9))
                    .lineLimit(1)
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let quality = qualityDescription(for: track) {
                Text(quality)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.colors.accent.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Theme.surfaceHighlight.opacity(0.8))
                    )
                    .accessibilityLabel("Audio quality \(quality)")
            }
        }
        .padding(.horizontal, 28)
    }

    /// e.g. "128 kbps · MP3" — the variant the player actually streams
    /// (`Track.preferredVariant`, always the best the account offers).
    private func qualityDescription(for track: Track) -> String? {
        guard let variant = track.preferredVariant else { return nil }
        let encoding: String
        switch variant.encoding.lowercased() {
        case "mp3": encoding = "MP3"
        case "aacplus": encoding = "AAC+"
        case "aac": encoding = "AAC"
        default: encoding = variant.encoding.uppercased()
        }
        return "\(variant.bitrate) kbps · \(encoding)"
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
                .background(Color.yellow.opacity(0.12), in: Capsule())
        }
    }

    /// Plain bold glyphs, no filled circles — the transport Apple Music
    /// uses, with the artwork accent reserved for the scrubber and
    /// ratings.
    private var transport: some View {
        HStack(spacing: 44) {
            Button {
                Haptics.light()
                store.player.skipBackward(by: 15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Back 15 seconds")

            Button {
                Haptics.light()
                store.send(.togglePlayback)
            } label: {
                Image(systemName: store.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 84, height: 64)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())
            .animation(.snappy(duration: 0.25), value: store.player.isPlaying)
            .accessibilityLabel(store.player.isPlaying ? "Pause" : "Play")

            Button {
                Haptics.medium()
                store.send(.skipToNext)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Next track")
        }
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
