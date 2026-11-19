import PandoraCore
import SwiftUI

/// Full-screen player, BitChord-structured with an Apple-Music lineage:
/// artwork-driven mesh scene, a flexible region that swaps between the
/// artwork sleeve, the lyrics panel and the frosted queue panel, and a
/// frosted dock row owning the secondary toggles. The transport, the
/// Pandora badges (thumbs, skip limit, ads, LIVE + identify) and the
/// quality chip are all unchanged — this is the shell around them.
///
/// Static surfaces are frosted (BitChord's glass finish); the mesh
/// backdrop still comes from the artwork palette
/// (`ArtworkThemeController`).
struct NowPlayingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The artwork flight's shared state — the pill's cover is the
    /// flight's origin, this cover is its destination.
    @Environment(\.artworkFlight) private var flight
    /// Reduce Motion — the flight is motion, and motion is exactly
    /// what the user asked not to have.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// BitChord's artwork sleeve easing: the 500 ms CubicBezier
    /// (0.215, 0.61, 0.355, 1) the pause-shrink rides.
    private static let sleeveAnimation = Animation.timingCurve(
        0.215, 0.61, 0.355, 1, duration: 0.5
    )

    /// The cover's flight in: a firm travel with a hair of overshoot —
    /// the cover arrives in the player like it was thrown there.
    private static let coverFlightAnimation = Animation.spring(
        response: 0.52, dampingFraction: 0.86
    )
    /// The way back: quicker and softer — the cover drops into the pill.
    private static let coverReturnAnimation = Animation.timingCurve(
        0.4, 0.0, 0.2, 1, duration: 0.45
    )

    /// The shared ambient theme. Reading the singleton's `@Observable`
    /// state from body is tracked like any environment dependency.
    private var theme: ArtworkThemeController { ArtworkThemeController.shared }

    @State private var isShowingSleepTimer = false
    @State private var isShowingTuning = false
    @State private var isShowingStats = false
    @State private var isShowingLyrics = false
    /// The queue panel — the frosted, read-only successor of the old
    /// Up Next disclosure (Pandora's queue is server-driven).
    @State private var isShowingQueue = false
    /// The volume while the slider is being dragged. The level is
    /// applied live, but it is only written to disk when the drag ends.
    @State private var draftVolume: Double?
    /// The artwork sleeve's live drag translation (BitChord's damped
    /// follow) — cleared and sprung home automatically by the state.
    @GestureState private var sleeveDrag: CGSize = .zero
    /// BitChord's lyrics-mode controls: after five idle seconds in the
    /// lyrics panel the transport, scrubber and feedback fade out for
    /// immersion; any interaction in the panel (or the dock) brings
    /// them back. The dock always stays — it is the way out.
    @State private var areLyricsControlsHidden = false
    @State private var lyricsIdleTask: Task<Void, Never>?

    // MARK: The artwork flight

    /// Where the cover is in its flight: waiting to be measured, on its
    /// way in, in place, or on its way back to the mini player.
    private enum CoverFlightState {
        case pending
        case flying
        case settled
        case returning
    }

    @State private var coverFlightState: CoverFlightState = .pending
    /// The flight's progress: 0 = at the mini player, 1 = in place.
    @State private var coverFlightProgress: Double = 1
    /// The mini player's cover, in window coordinates — the origin.
    @State private var coverOriginFrame: CGRect = .zero
    /// This cover, in window coordinates — the destination.
    @State private var coverDestinationFrame: CGRect = .zero
    /// The owned tasks: the flight's safety net and the return's
    /// dismissal. No `.task` modifier anywhere (the launch-crash rule).
    @State private var coverFlightTask: Task<Void, Never>?
    @State private var coverReturnTask: Task<Void, Never>?

    /// Whether the scrubber/transport/feedback chrome should render —
    /// everything but the lyrics panel itself. The chrome is opaque
    /// (never hidden) outside lyrics mode.
    private var lyricsControlsVisible: Bool {
        !isShowingLyrics || !areLyricsControlsHidden
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // BitChord's artwork-driven mesh scene: the palette's
                // deep stops carry the floor, the accent pools as the
                // light, and the palette glides across tracks.
                MeshBackdrop(colors: theme.colors)
                    .ignoresSafeArea()
                    .opacity(isCoverReturning ? 0 : 1)
                    .animation(.easeOut(duration: 0.25), value: isCoverReturning)
                content
            }
            // The title goes with everything else on the way out: on the
            // return the cover is the only thing that should still be
            // moving, and a station name floating over the fading
            // player would say otherwise.
            .navigationTitle(isCoverReturning ? "" : (store.currentStation?.name ?? "Now Playing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // The dock owns the secondary toggles now — lyrics,
                // queue, sleep timer and the output picker are its four
                // discs — so the bar above stays ellipsis + Done.
                ToolbarItem(placement: .topBarLeading) {
                    actionsMenu
                        .opacity(isCoverReturning ? 0 : 1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismissPlayer() }
                        .opacity(isCoverReturning ? 0 : 1)
                }
            }
            .sheet(isPresented: $isShowingSleepTimer) {
                SleepTimerSheet()
            }
            .sheet(isPresented: $isShowingTuning) {
                TuneStationSheet(station: nil)
            }
            .sheet(isPresented: $isShowingStats) {
                TrackStatsSheet()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            prepareCoverFlight()
        }
        .onDisappear {
            coverFlightTask?.cancel()
            coverReturnTask?.cancel()
        }
    }

    /// Every secondary action in one Apple-Music-style place. This is
    /// also the app's only sleep-timer surface entry — the duplicate
    /// moon icon on the main surface is gone.
    ///
    /// A radio stream has no song behind it, so the song-level actions
    /// (tuning a Pandora station, bookmarking the song or the artist,
    /// hiding the song) would all be no-ops — they are not offered.
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
                isShowingStats = true
            } label: {
                Label("Track Stats", systemImage: "info.circle")
            }
            if isRadioStream {
                // The Identify button: retries the announced song's
                // artwork + lyrics lookup; before the first
                // announcement it reconnects the probe. A station that
                // announces nothing says so beside the LIVE badge.
                Button {
                    store.send(.identifyRadioSong)
                } label: {
                    Label("Identify Song", systemImage: "magnifyingglass")
                }
            } else {
                // Playback speed (BitChord's, 0.5–2×): a song can be
                // sped; a live stream cannot — its edge cannot be
                // outpaced, so the control is not offered on radio and
                // the player pins a stream to 1× regardless.
                Picker(
                    "Playback Speed",
                    selection: Binding(
                        get: { Double(store.player.playbackRate) },
                        set: { store.send(.setPlaybackRate(Float($0))) }
                    )
                ) {
                    Text("0.5×").tag(0.5)
                    Text("0.75×").tag(0.75)
                    Text("1×").tag(1.0)
                    Text("1.25×").tag(1.25)
                    Text("1.5×").tag(1.5)
                    Text("1.75×").tag(1.75)
                    Text("2×").tag(2.0)
                }
                Divider()
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
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More actions")
    }

    /// `true` while a live radio stream is the current track.
    private var isRadioStream: Bool { store.player.currentTrack?.isRadio == true }

    @ViewBuilder
    private var content: some View {
        if let track = store.player.currentTrack {
            // One fixed stack, BitChord-structured: the flexible region
            // (artwork / lyrics / queue — one at a time), then header,
            // scrubber, transport and dock as siblings, so nothing can
            // scroll independently. When everything fits, nothing
            // scrolls at all.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 18) {
                        mainRegion(track)
                        // Everything but the cover, in one group: on the
                        // way out it fades as a whole, so the cover's
                        // return is the only thing left moving.
                        VStack(spacing: 18) {
                            if !isShowingLyrics {
                                trackHeader(track)
                            }
                            routeIndicator
                            // A live stream has no timeline — a dead
                            // zero-length scrubber would only look
                            // broken. The LIVE badge takes its place.
                            if !track.isRadio {
                                scrubber
                                    .opacity(lyricsControlsVisible ? 1 : 0)
                                    .allowsHitTesting(lyricsControlsVisible)
                                    .animation(.easeInOut(duration: 0.3), value: lyricsControlsVisible)
                            }
                            playerControls(for: track)
                                .opacity(lyricsControlsVisible ? 1 : 0)
                                .allowsHitTesting(lyricsControlsVisible)
                                .animation(.easeInOut(duration: 0.3), value: lyricsControlsVisible)
                            PlayerDock(
                                isShowingLyrics: $isShowingLyrics,
                                isShowingQueue: $isShowingQueue,
                                onSleepTimer: { isShowingSleepTimer = true }
                            )
                        }
                        .opacity(isCoverReturning ? 0 : 1)
                        .animation(.easeOut(duration: 0.25), value: isCoverReturning)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geo.size.height,
                        alignment: .top
                    )
                    .padding(.top, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .onChange(of: isShowingLyrics) { _, showing in
                if showing {
                    noteLyricsInteraction()
                } else {
                    lyricsIdleTask?.cancel()
                    areLyricsControlsHidden = false
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

    /// The player's flexible region: the artwork, the lyrics panel or
    /// the queue panel — one at a time, swapping in place with
    /// BitChord's 420 ms travel (the queue rises from the bottom while
    /// the artwork sinks away; panels mount through the transition,
    /// not before it). Whatever occupies the slot yields height to the
    /// controls, never the reverse — the fixed-stack property.
    @ViewBuilder
    private func mainRegion(_ track: Track) -> some View {
        ZStack {
            if isShowingLyrics {
                LyricsPanel(onUserInteraction: { noteLyricsInteraction() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isShowingQueue {
                PlayerQueuePanel()
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                artwork(for: track)
                    .gesture(sleeveGesture(for: track))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Everything below the artwork/lyrics region: ad badge, LIVE badge,
    /// transport, volume, feedback, up next, confirmations, errors. In
    /// the main layout it rides inside the same stack as the artwork, so
    /// the two can never move independently.
    private func playerControls(for track: Track) -> some View {
        VStack(spacing: 18) {
            adBadge(track)
            if track.isRadio {
                radioIdentifyStatus
            } else {
                liveBadge(track)
            }
            skipLimitBadge
            transport(for: track)
            volumeControl
            if !track.isAdvertisement && !track.isRadio {
                // A radio stream is not a song: there is nothing to
                // rate — the thumbs would fire at a synthetic
                // `radio.<uuid>` token.
                FeedbackBar(accent: theme.colors.accent)
            }
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

    /// The app's playback volume. `AVPlayer.volume` scales what
    /// Amphora outputs — the phone's own system volume is untouched, so
    /// this slider never fights the hardware buttons.
    ///
    /// The level moves live while the finger is down and is written to
    /// disk once, when the drag ends — saving on every frame would
    /// hammer the file system for nothing.
    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { draftVolume ?? Double(store.player.volume) },
                    set: { newValue in
                        draftVolume = newValue
                        store.player.setVolume(Float(newValue))
                    }
                ),
                in: 0...1,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    if let draftVolume {
                        store.send(.setPlaybackVolume(Float(draftVolume)))
                    }
                    draftVolume = nil
                }
            )
            .tint(theme.colors.accent.color)
            .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }

    private func artwork(for track: Track) -> some View {
        let transform = coverFlightTransform
        let radius = coverCornerRadius
        return Group {
            if track.isRadio {
                if let artwork = store.radioSongArtwork {
                    // The identified song's cover (iTunes Search).
                    CachedArtwork(
                        urlString: artwork.largeArtworkURL.absoluteString,
                        cornerRadius: radius,
                        fallbackSystemImage: "music.note"
                    )
                } else {
                    // At cover size a tiny favicon is worse than the
                    // generated station tile, so the tile wins unless
                    // the station really has a big logo.
                    RadioStationArtwork(
                        stationName: track.title,
                        faviconURL: track.artworkUrl,
                        cornerRadius: radius,
                        minimumArtworkPixels: 200
                    )
                }
            } else {
                CachedArtwork(
                    urlString: track.artworkUrl,
                    cornerRadius: radius,
                    fallbackSystemImage: "music.note"
                )
            }
        }
        // The square itself. The probe sits on it, so the flight
        // measures the cover's own place and size — not the padded
        // region around it, and not the sleeve's shrunken version of
        // it.
        .aspectRatio(1, contentMode: .fit)
        .background(coverProbe)
        // The flexible square: it grows with the space left over and
        // yields it again when the controls need room (large Dynamic
        // Type, the badges) — the Apple-Music artwork behavior.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .shadow(color: theme.colors.accent.color.opacity(0.18), radius: 40, y: 8)
        // BitChord's sleeve: the artwork settles 12% smaller while
        // paused, springing back with the same easing the panels use.
        .scaleEffect(sleeveScale)
        .animation(Self.sleeveAnimation, value: store.player.isPlaying)
        // BitChord's damped follow: the sleeve tracks the finger at a
        // third of its travel, dips slightly while held, and springs
        // home when the finger lifts.
        .offset(
            x: abs(sleeveDrag.width) > abs(sleeveDrag.height)
                ? sleeveDrag.width * 0.35 : 0,
            y: abs(sleeveDrag.width) > abs(sleeveDrag.height)
                ? 0
                // The collapse only pulls down — never up into the
                // header.
                : min(max(sleeveDrag.height, -40), 120) * 0.35
        )
        .scaleEffect(sleeveDrag == .zero ? 1 : 0.94)
        .animation(.interactiveSpring(response: 0.28), value: sleeveDrag)
        // The flight: the cover's place and size on its way in and on
        // its way back. It rides outside the sleeve's transforms, so
        // the two never fight over the cover's size.
        .scaleEffect(transform.scale)
        .offset(x: transform.dx, y: transform.dy)
        .opacity(coverOpacity)
    }

    /// BitChord's sleeve scale: the cover settles 12% smaller while
    /// paused.
    ///
    /// The flight holds the sleeve at full size. The flight *measures*
    /// the cover, and a shrunken sleeve would make every measurement
    /// 12% small — the cover would land small and stay small. The
    /// sleeve comes back when the cover settles, on its own easing.
    private var sleeveScale: CGFloat {
        switch coverFlightState {
        case .pending, .flying, .returning:
            return 1
        case .settled:
            return store.player.isPlaying ? 1 : 0.88
        }
    }

    /// The probe that reports this cover's place on screen. The flight
    /// measures the mini player's cover and this one in the same space
    /// (window coordinates), so the two can be compared.
    private var coverProbe: some View {
        WindowFrameProbe(
            onProbe: { flight?.registerPlayerProbe($0) }
        )
    }

    /// The cover's flight transform: where it sits relative to its own
    /// place in the player, and how big it is — interpolated between
    /// the mini player's cover and this one.
    private var coverFlightTransform: (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        switch coverFlightState {
        case .pending, .settled:
            // Nothing is in flight: the cover is exactly where it
            // belongs.
            return (1, 0, 0)
        case .flying, .returning:
            break
        }
        let progress = CGFloat(coverFlightProgress)
        guard coverDestinationFrame.width > 1, coverOriginFrame.width > 1 else {
            return (1, 0, 0)
        }
        let width = coverOriginFrame.width
            + (coverDestinationFrame.width - coverOriginFrame.width) * progress
        let scale = width / coverDestinationFrame.width
        let targetX = coverOriginFrame.midX
            + (coverDestinationFrame.midX - coverOriginFrame.midX) * progress
        let targetY = coverOriginFrame.midY
            + (coverDestinationFrame.midY - coverOriginFrame.midY) * progress
        return (
            scale,
            targetX - coverDestinationFrame.midX,
            targetY - coverDestinationFrame.midY
        )
    }

    /// The cover's corner radius while it flies. The radius is drawn in
    /// the cover's own space and scaled with it, so it is divided by
    /// the flight's scale — the rendered radius is then the one the
    /// pill and the player use, at every point of the flight.
    private var coverCornerRadius: CGFloat {
        let pill = Theme.radiusS + 2
        let full = Theme.radiusArtwork
        let radius = pill + (full - pill) * CGFloat(coverFlightProgress)
        let scale = coverFlightTransform.scale
        guard scale > 0.02 else { return full }
        return radius / scale
    }

    /// The cover fades in as it leaves the pill — the flight reads as
    /// the cover emerging from the mini player, not as a picture
    /// appearing out of nowhere.
    private var coverOpacity: Double {
        switch coverFlightState {
        case .pending:
            return 0
        case .flying:
            return min(1, coverFlightProgress * 4)
        case .settled, .returning:
            return 1
        }
    }

    /// `true` while the cover is on its way back to the mini player.
    private var isCoverReturning: Bool {
        coverFlightState == .returning
    }

    /// The flight's preparation. The cover waits (hidden) until this
    /// player's own place on screen is known; then it flies in from the
    /// mini player's cover.
    private func prepareCoverFlight() {
        guard coverFlightState == .pending else { return }
        // A radio stream's cover is not shared between the two hosts —
        // the pill shows the station tile, the player may show the
        // identified song's cover — so there is nothing to fly.
        let isRadio = store.player.currentTrack?.isRadio == true
        let isEnabled = store.artworkFlightEnabled && !reduceMotion
        guard isEnabled, !isRadio, let flight else {
            settleCoverWithoutFlight()
            return
        }
        coverFlightProgress = 0
        // Wait for this cover's place to be measured — a frame or two —
        // then fly. The wait is bounded: if the place never arrives (an
        // odd layout, a zero-sized region), the plain cover shows
        // anyway.
        coverFlightTask?.cancel()
        coverFlightTask = Task { @MainActor in
            for _ in 0..<45 {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                if flight.currentDestination() != nil {
                    beginCoverFlight()
                    // The flight itself takes about half a second;
                    // after it, the cover is simply in place — and the
                    // sleeve comes back with it.
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    if coverFlightState == .flying {
                        withAnimation(Self.sleeveAnimation) {
                            coverFlightState = .settled
                        }
                    }
                    return
                }
            }
            settleCoverWithoutFlight()
        }
    }

    /// The cover's place is known — fly it in from the mini player.
    private func beginCoverFlight() {
        guard coverFlightState == .pending else { return }
        guard let flight,
              let origin = flight.originFrame, let originWindow = flight.originWindow,
              // Read the destination *now*, not from an earlier report:
              // the sheet is still rising while the flight starts, and
              // the cover has to fly from the pill's place to where the
              // cover is at this very instant — otherwise the flight
              // starts from a place the cover has already left.
              let destination = flight.currentDestination(),
              // The two covers are only comparable when they are in the
              // same window — otherwise the flight would start from a
              // place that means nothing here.
              originWindow === destination.window,
              origin.width > 1, destination.frame.width > 1
        else {
            settleCoverWithoutFlight()
            return
        }
        coverOriginFrame = origin
        coverDestinationFrame = destination.frame
        coverFlightState = .flying
        withAnimation(Self.coverFlightAnimation) {
            coverFlightProgress = 1
        }
    }

    /// No flight: the plain cover, in place, as it has always been.
    ///
    /// The change lands without an animation on purpose. The cover was
    /// hidden while the flight waited for its place, and it must appear
    /// the way it always has — at once, at its resting size (the
    /// sleeve comes back in the same frame, so there is no shrink to
    /// watch).
    private func settleCoverWithoutFlight() {
        guard coverFlightState == .pending else { return }
        coverFlightTask?.cancel()
        coverFlightTask = nil
        coverFlightProgress = 1
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            coverFlightState = .settled
        }
    }

    /// "Done": the cover flies back to the mini player before the sheet
    /// goes away, so it lands exactly where the pill's cover is.
    private func dismissPlayer() {
        guard canFlyCoverBack else {
            dismiss()
            return
        }
        // Measure both covers again — the sheet may have moved since
        // the flight in (a rotation, a resized sheet), and the pill's
        // cover is where it is now.
        if let flight {
            flight.captureOrigin()
            if let origin = flight.originFrame {
                coverOriginFrame = origin
            }
            if let destination = flight.currentDestination() {
                coverDestinationFrame = destination.frame
            }
        }
        // One transaction for both: the cover flies back *and* the
        // sleeve returns to full size (it was held small while the
        // flight measured the cover), on the way back's easing.
        withAnimation(Self.coverReturnAnimation) {
            coverFlightState = .returning
            coverFlightProgress = 0
        }
        coverReturnTask?.cancel()
        coverReturnTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            // The chrome has faded and the cover has landed: the sheet
            // leaves without sliding, so the pill underneath takes the
            // cover's place in one motion.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }

    /// The cover can only fly back when it is the cover on screen and
    /// there is a pill to fly it to.
    private var canFlyCoverBack: Bool {
        coverFlightState == .settled
            && !isShowingLyrics
            && !isShowingQueue
            && coverOriginFrame.width > 1
    }


    /// BitChord's lyrics idle clock: an interaction reveals the
    /// controls and restarts the five-second countdown to fade them.
    /// The owned task is replaced on every interaction, so a held
    /// engagement keeps the chrome up.
    private func noteLyricsInteraction() {
        guard isShowingLyrics else { return }
        lyricsIdleTask?.cancel()
        areLyricsControlsHidden = false
        lyricsIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            areLyricsControlsHidden = true
        }
    }

    /// The sleeve's gestures, Pandora-adapted from BitChord's: a
    /// deliberate leftward fling skips to the next track; a downward
    /// drag collapses the artwork into the queue panel. Both are
    /// radio-aware — a live stream has no next track and no queue, so
    /// neither gesture fires on one (a rightward fling has nothing to
    /// go back to either: Pandora's playlist only advances).
    private func sleeveGesture(for track: Track) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($sleeveDrag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > abs(vertical) {
                    guard !track.isRadio, horizontal < -72 else { return }
                    Haptics.medium()
                    store.send(.skipToNext)
                } else if vertical > 90, !track.isRadio {
                    Haptics.light()
                    withAnimation(PlayerDock.panelAnimation) {
                        isShowingQueue = true
                        isShowingLyrics = false
                    }
                }
            }
    }

    /// Apple-Music-style block: left-aligned title, artist in the
    /// artwork accent, album beneath, and the stream quality as a matte
    /// chip on the trailing edge.
    ///
    /// A radio station's identified song takes the header: the stream
    /// is still what plays, but the song is what the user cares about —
    /// the station stays visible beneath it ("on <station>").
    private func trackHeader(_ track: Track) -> some View {
        let song = track.isRadio ? store.radioNowPlaying : nil
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song?.title ?? track.title)
                    .font(Font.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(2)
                if song != nil, let artist = song?.artist {
                    Text(artist)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.colors.accent.color.opacity(0.9))
                        .lineLimit(1)
                } else if song == nil {
                    // No song identified — the stream's own caption.
                    Text(track.artist)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.colors.accent.color.opacity(0.9))
                        .lineLimit(1)
                }
                if !track.isRadio, !track.album.isEmpty {
                    Text(track.album)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                // The station the track came from (AGENTS.md's Now
                // Playing list: artwork, title, artist, station,
                // progress, skips). A radio stream's title *is* the
                // station name — the line appears only once a song is
                // identified, as "on <station>".
                if track.isRadio {
                    if song != nil, let stationName = store.currentRadioStation?.name {
                        Text("on \(stationName)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityLabel("Playing on \(stationName)")
                    }
                } else if let stationName = store.currentStation?.name {
                    Text(stationName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("Playing on \(stationName)")
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
                        Capsule().fill(Theme.playerSurface)
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

    /// "Living Room" — where the audio is actually going, whenever that
    /// is not the phone's own speaker. Shows the user that the AirPlay
    /// handover really happened instead of leaving the music silent on
    /// the device.
    @ViewBuilder
    private var routeIndicator: some View {
        if let name = store.player.outputRouteName {
            Label(
                name,
                systemImage: RouteSymbol.name(isAirPlay: store.player.isAirPlayActive)
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.colors.accent.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.playerSurface))
            .accessibilityLabel("Playing on \(name)")
        }
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            // BitChord's strip: the sung line rides above the scrubber
            // while the lyrics panel is closed — tapping it opens the
            // lyrics. Nothing renders while there are no lyrics.
            CurrentLyricStrip(onOpenLyrics: {
                withAnimation(PlayerDock.panelAnimation) {
                    isShowingLyrics = true
                    isShowingQueue = false
                }
            })
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

    /// The LIVE badge of a radio stream — the counterpart of the
    /// advertisement badge: it says what the slot is.
    @ViewBuilder
    private func liveBadge(_ track: Track) -> some View {
        if track.isRadio {
            LiveBadge()
        }
    }

    /// The song identification beside the LIVE badge: a spinner while
    /// the first announcement is awaited, an honest note when the
    /// station announces nothing, and the Identify affordance in the
    /// meantime (AGENTS.md: honest states). An identified song needs
    /// nothing here — it is in the header and the artwork.
    @ViewBuilder
    private var radioIdentifyStatus: some View {
        HStack(spacing: 10) {
            LiveBadge()
            switch store.radioIdentification {
            case .identifying:
                // Tappable: a fresh probe connection often carries the
                // current title within the first metadata interval.
                Button {
                    store.send(.identifyRadioSong)
                } label: {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.secondary)
                        Text("Identify")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.colors.accent.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.playerSurface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Identify the current song")
            case .stationAnnouncesNothing:
                Text("No song announcements")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .identified:
                if store.isIdentifyingRadioSong {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.secondary)
                        Text("Looking up artwork…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .inactive:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Pandora's daily skip limit stopped the playlist for this station.
    /// The badge says why no more tracks are coming — the server refuses
    /// to hand them out until the limit resets.
    @ViewBuilder
    private var skipLimitBadge: some View {
        if store.isSkipLimitReached {
            VStack(spacing: 6) {
                Text("SKIP LIMIT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
                    .tracking(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.12), in: Capsule())
                Text(store.skipLimitMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The transport: matched side glyphs around the main play/pause,
    /// which sits in the accent-filled circle the mini player and the
    /// Home hero already use (user request 2026-11-12 — the bare 44 pt
    /// glyph read as unfinished next to the two circled buttons
    /// elsewhere in the app).
    ///
    /// A live radio stream has no timeline: the back-15 button is gone
    /// (there is nowhere to go back to) and the trailing button stops
    /// the stream instead of skipping it.
    private func transport(for track: Track) -> some View {
        HStack(spacing: 52) {
            if !track.isRadio {
                Button {
                    Haptics.light()
                    store.player.skipBackward(by: 15)
                } label: {
                    // BitChord's previous glyph leads their transport
                    // row; the action stays Pandora's back-15 (there is
                    // no previous track to skip to on radio).
                    TransportGlyph(.previous, size: 32)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Back 15 seconds")
            }

            Button {
                Haptics.light()
                store.send(.togglePlayback)
            } label: {
                ZStack {
                    if store.player.isPlaying {
                        TransportGlyph(.pause, size: 32, color: Theme.accentGlyph)
                    } else {
                        TransportGlyph(.play, size: 32, color: Theme.accentGlyph)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accent.opacity(0.30), radius: 12, y: 4)
            }
            .frame(width: 92, height: 76)
            .buttonStyle(PressableButtonStyle())
            .animation(.snappy(duration: 0.25), value: store.player.isPlaying)
            .accessibilityLabel(store.player.isPlaying ? "Pause" : "Play")

            Button {
                Haptics.medium()
                if track.isRadio {
                    store.send(.stopRadio)
                } else {
                    store.send(.skipToNext)
                }
            } label: {
                // `size` is the family's yardstick (the play glyph's
                // height); the skip glyphs scale themselves against it,
                // exactly as BitChord's transport row does.
                TransportGlyph(track.isRadio ? .stop : .next, size: 32)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(track.isRadio ? "Stop radio" : "Next track")
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
                .background(Theme.playerSurface, in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// The LIVE indicator of a radio stream: a pulsing dot next to the
/// word, in the same capsule language as the advertisement badge. It
/// replaces the scrubber — a live stream has no length, so a progress
/// bar over nothing would read as a broken control.
private struct LiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 0.3 : 1)
            Text("LIVE")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.playerSurface, in: Capsule())
        .onAppear { isPulsing = true }
        .animation(
            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live radio stream")
    }
}
