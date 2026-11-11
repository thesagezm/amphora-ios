import AVFoundation
import CoreMedia
import Foundation
import Observation
import PandoraCore

/// Playback engine — the single source of truth for playback state.
///
/// Owns the `AVQueuePlayer`, the audio session and the now-playing track.
/// It performs **no networking**: every track (and therefore every stream
/// URL) arrives from PandoraCore through `AppStore`.
///
/// Queueing mirrors pithos' `start_song`: the queue holds the current
/// track plus the next one, so AVFoundation buffers the next stream while
/// the current one plays (near-gapless transition). When the queue runs
/// low, `onNeedMoreTracks` asks the owner for the next playlist — pithos
/// preloads the next playlist when one song remains.
///
/// The service lives as long as the app (`AppStore` owns it), so it does
/// not implement `deinit`-based observer teardown; all observer closures
/// capture `self` weakly.
@MainActor
@Observable
final class PlayerService {

    /// Coarse playback state for the UI.
    enum PlaybackState: Equatable {
        case idle
        case playing
        case paused
        case buffering
        case failed
    }

    // MARK: Observable state

    private(set) var currentTrack: Track? {
        didSet { for observer in onTrackChanged { observer(currentTrack) } }
    }
    private(set) var state: PlaybackState = .idle {
        didSet {
            if oldValue != state {
                AppLog.info("playback state: \(oldValue) → \(state)", .playback)
                for observer in onPlaybackStateChanged { observer() }
            }
        }
    }
    /// Playback position in seconds.
    private(set) var elapsed: TimeInterval = 0
    /// Track length in seconds (from Pandora's `trackLength`).
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?

    /// The name of the external output the audio is playing through —
    /// an AirPlay receiver ("Living Room"), a Bluetooth speaker, a pair
    /// of headphones. `nil` while the phone's own speaker is the output.
    private(set) var outputRouteName: String?
    /// `true` when the current output is an AirPlay receiver rather than
    /// a device wired to the phone.
    private(set) var isAirPlayActive: Bool = false

    /// The app's playback volume (0...1). `AVPlayer.volume` scales what
    /// this app outputs — it does **not** change the phone's system
    /// volume, so the player can offer its own level without fighting
    /// the hardware buttons.
    private(set) var volume: Float = 1 {
        didSet { player.volume = volume }
    }

    var isPlaying: Bool { state == .playing || state == .buffering }

    /// Tracks queued behind the current one, most immediate first — the
    /// "Up Next" list. The queue holds the current track plus everything
    /// enqueued from playlist fetches, so this is what will actually play.
    var upcomingTracks: [Track] {
        slots.dropFirst().map(\.track)
    }

    // MARK: Callbacks (set by the owner)

    /// Fired when the queue holds ≤ 1 playable track — fetch another
    /// playlist and hand it back via `enqueue(_:)`.
    var onNeedMoreTracks: (() -> Void)?
    /// Fired when the current track played to its end.
    var onTrackEnded: (() -> Void)?
    /// Fired when playback of the current track failed.
    var onPlaybackFailed: ((String) -> Void)?
    /// Fired when the current track changed (start, skip, natural end).
    /// A list of observers: the now-playing service and the app store
    /// both need the hook, so neither may overwrite the other.
    var onTrackChanged: [(Track?) -> Void] = []
    /// Fired when the playback state changed (play/pause/buffering/failed).
    var onPlaybackStateChanged: [() -> Void] = []
    /// Fired when a track stops being the current one — natural end,
    /// user skip, station switch or stop — with how far into it playback
    /// reached. The scrobbler's policy input (pithos evaluates its rule
    /// at song-ended). Fires *before* `onTrackChanged` for the
    /// replacement track, so "started at" timestamps stay aligned.
    var onTrackFinished: [(Track, TimeInterval) -> Void] = []
    /// Fired when the output route changed — an AirPlay receiver was
    /// picked or lost. The now-playing service re-publishes the metadata
    /// so a receiver that just joined shows the current track.
    var onRouteChanged: [() -> Void] = []

    // MARK: Private state

    /// One queue slot: the track and the player item that plays it.
    private struct Slot {
        let track: Track
        let item: AVPlayerItem
    }

    private var player = AVQueuePlayer()
    private var slots: [Slot] = []
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var wasPlayingBeforeInterruption = false
    /// `true` while the system has the session paused for an
    /// interruption (a call, another app taking over).
    private var isInterrupted = false
    /// What the user asked for: `true` while the app wants audio running.
    /// The player's own state can dip to `.paused` for a moment during a
    /// route handover (an AirPlay receiver joining or leaving), so the
    /// intent is kept apart from what the player reports.
    private var wantsToPlay = false

    // MARK: Init

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        // AirPlay: the player may be handed to an external receiver.
        // This is the default, stated here so the intent is explicit.
        player.allowsExternalPlayback = true
        // Configure the session **before** the user can pick a route.
        // Setting the category re-evaluates the available routes, so a
        // category change made after the user chose a receiver can drop
        // that choice and fall back to the phone's speaker. Doing it
        // once at launch means the category is already right by the time
        // the route picker is ever used.
        configureAudioSession()
        observeTimeControl()
        startTimeObserver()
        observePlayerEvents()
        observeSessionEvents()
    }

    // MARK: - Public API

    /// Starts a track, queueing the next one for a gapless hand-over.
    func play(track: Track, prefetching next: Track?) {
        finishOutgoingTrack()
        resetQueue()
        guard let item = makeItem(for: track) else {
            // The queue is empty now, so the old track is no longer
            // playing — say so, or the player would keep showing the
            // track that was replaced.
            currentTrack = nil
            fail("That track isn't playable right now.")
            return
        }
        var newSlots = [Slot(track: track, item: item)]
        player.insert(item, after: nil)
        if let next, let nextItem = makeItem(for: next) {
            player.insert(nextItem, after: item)
            newSlots.append(Slot(track: next, item: nextItem))
        }
        slots = newSlots
        currentTrack = track
        elapsed = 0
        duration = TimeInterval(track.duration)
        errorMessage = nil
        activateAudioSession()
        player.play()
        state = .playing
        wantsToPlay = true
        requestMoreTracksIfNeeded()
    }

    /// Starts a live radio stream: one slot, nothing behind it — there
    /// is no "next" to prefetch, and the track's duration is 0 (the
    /// scrubber reads it as live and disables itself).
    func playLiveStream(track: Track) {
        finishOutgoingTrack()
        resetQueue()
        guard let item = makeItem(for: track) else {
            // The queue was emptied for the switch, so nothing is
            // playing any more — the current track must not keep
            // pointing at the track that was replaced.
            currentTrack = nil
            fail("That stream isn't playable right now.")
            return
        }
        slots = [Slot(track: track, item: item)]
        player.insert(item, after: nil)
        currentTrack = track
        elapsed = 0
        duration = 0
        errorMessage = nil
        activateAudioSession()
        player.play()
        state = .playing
        wantsToPlay = true
    }

    /// Appends tracks to the queue (a freshly fetched playlist). Items are
    /// buffered by AVFoundation while the current track plays.
    func enqueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        var lastItem = slots.last?.item
        for track in tracks {
            guard let item = makeItem(for: track) else { continue }
            if let lastItem {
                player.insert(item, after: lastItem)
            } else {
                player.insert(item, after: nil)
            }
            lastItem = item
            slots.append(Slot(track: track, item: item))
            if slots.count == 1 {
                // The queue was empty — this track starts right away.
                currentTrack = track
                elapsed = 0
                duration = TimeInterval(track.duration)
                player.play()
                state = .playing
                wantsToPlay = true
            }
        }
        requestMoreTracksIfNeeded()
    }

    /// Skip to the next track (user action).
    func skipToNext() {
        guard !slots.isEmpty else { return }
        finishOutgoingTrack()
        player.advanceToNextItem()
        slots.removeFirst()
        if let next = slots.first {
            currentTrack = next.track
            elapsed = 0
            duration = TimeInterval(next.track.duration)
            state = player.timeControlStatus == .paused ? PlaybackState.paused : PlaybackState.playing
        } else {
            currentTrack = nil
            elapsed = 0
            duration = 0
            state = .idle
        }
        requestMoreTracksIfNeeded()
    }

    func pause() {
        player.pause()
        state = .paused
        wantsToPlay = false
    }

    func resume() {
        guard !slots.isEmpty else { return }
        activateAudioSession()
        player.play()
        state = .playing
        wantsToPlay = true
    }

    func togglePlayback() {
        switch state {
        case .playing, .buffering:
            pause()
        case .paused, .failed:
            resume()
        case .idle:
            break
        }
    }

    /// Sets the app's playback volume, clamped to 0...1.
    func setVolume(_ value: Float) {
        volume = min(max(value, 0), 1)
    }

    /// Jumps forward in the current track (remote command).
    func skipForward(by seconds: TimeInterval) {
        guard !slots.isEmpty else { return }
        seek(to: min(elapsed + seconds, maxDuration))
    }

    /// Jumps backward in the current track (remote command).
    func skipBackward(by seconds: TimeInterval) {
        guard !slots.isEmpty else { return }
        seek(to: max(0, elapsed - seconds))
    }

    /// Seeks within the current track.
    func seek(to seconds: TimeInterval) {
        guard !slots.isEmpty else { return }
        let target = max(0, min(seconds, maxDuration))
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        elapsed = target
    }

    /// Track length in seconds; falls back to the player item's duration
    /// when Pandora did not send one.
    private var maxDuration: TimeInterval {
        if duration > 0 { return duration }
        let itemDuration = player.currentItem?.duration.seconds ?? 0
        return itemDuration.isFinite ? itemDuration : 0
    }

    /// Stops playback and clears the queue (sign-out, station switch).
    func stop() {
        finishOutgoingTrack()
        resetQueue()
        currentTrack = nil
        elapsed = 0
        duration = 0
        state = .idle
        wantsToPlay = false
        deactivateAudioSession()
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Queue internals

    /// Empties the queue for a source switch.
    ///
    /// `AVQueuePlayer.removeAllItems()` alone does **not** reliably drop
    /// the item that is currently playing: the old stream keeps playing
    /// and stays the player's current item, so the item inserted right
    /// after it waits in the queue and never becomes current. That is
    /// exactly the handover that failed in the field — starting a radio
    /// station while a Pandora track played left the Pandora track
    /// playing (the radio stream sat behind it), and starting a Pandora
    /// station while radio played left the radio stream playing.
    ///
    /// Pausing first and then dropping the current item *explicitly*
    /// hands the player over: the old item is gone before the new one
    /// is inserted, in either direction.
    private func resetQueue() {
        player.pause()
        player.removeAllItems()
        player.replaceCurrentItem(with: nil)
        slots.removeAll()
    }

    /// Reports the outgoing track and the reached position to the
    /// `onTrackFinished` observers (scrobbling), before any queue or
    /// current-track change. The 0.5 s time-observer granularity of
    /// `elapsed` is close enough for the policy's thresholds.
    private func finishOutgoingTrack() {
        guard let outgoing = currentTrack else { return }
        for observer in onTrackFinished {
            observer(outgoing, elapsed)
        }
    }

    /// Builds a player item for a track, with buffer tuning for a fast,
    /// smooth start (AGENTS.md audio-quality requirements).
    private func makeItem(for track: Track) -> AVPlayerItem? {
        guard let stream = track.streamURL,
              let url = URL(string: stream) else { return nil }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 30
        return item
    }

    /// pithos preloads the next playlist when one song remains — ask the
    /// owner for more tracks at that point.
    private func requestMoreTracksIfNeeded() {
        guard slots.count <= 1 else { return }
        onNeedMoreTracks?()
    }

    private func fail(_ message: String) {
        AppLog.error("playback failed: \(message)", .playback)
        errorMessage = message
        state = .failed
        onPlaybackFailed?(message)
    }

    // MARK: - Audio session

    /// Configures the session for long-form music and lets the route be
    /// shared with an AirPlay receiver.
    ///
    /// The category is only set when it differs from what the session
    /// already has: `setCategory` posts a `.categoryChange` route
    /// notification, and setting the same category again would bounce
    /// straight back into this method.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let sharing = AVAudioSession.RouteSharingPolicy.longFormAudio
        guard session.category != .playback
                || session.mode != .default
                || session.routeSharingPolicy != sharing else { return }
        do {
            try session.setCategory(.playback, mode: .default, policy: sharing)
        } catch {
            AppLog.error("could not set the audio session category: \(error.localizedDescription)", .playback)
        }
    }

    private func activateAudioSession() {
        configureAudioSession()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            AppLog.error("could not activate the audio session: \(error.localizedDescription)", .playback)
            // A failure while audio is already running (a route handover,
            // say) must not replace the track's error with a scary one.
            if state != .playing {
                errorMessage = "Couldn't start audio output."
            }
        }
        refreshOutputRoute()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Reads the session's live output and publishes it. Everything but
    /// the phone's own speaker counts as an external route; an AirPlay
    /// receiver is called out separately so the UI can say so.
    private func refreshOutputRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let isAirPlay = outputs.contains {
            $0.portType.rawValue == AVAudioSession.Port.airPlay.rawValue
        }
        let external = outputs.first {
            $0.portType.rawValue != AVAudioSession.Port.builtInSpeaker.rawValue
        }
        let name = external?.portName
        guard name != outputRouteName || isAirPlay != isAirPlayActive else { return }
        outputRouteName = name
        isAirPlayActive = isAirPlay
        // The port list, the types and the external-playback flag go
        // into the log: when an AirPlay handover misbehaves on a
        // device, this is what says whether the system moved the
        // output, to which port types, and whether AVPlayer actually
        // engaged the receiver for the audio-only path.
        let ports = outputs
            .map { "\($0.portName) [\($0.portType.rawValue)]" }
            .joined(separator: ", ")
        AppLog.info(
            "output route: \(name ?? "device speaker")\(isAirPlay ? " [airplay]" : "")"
                + " — external playback \(player.isExternalPlaybackActive ? "active" : "off")"
                + " — ports: \(ports)",
            .playback
        )
        for observer in onRouteChanged { observer() }
    }

    // MARK: - Observation

    private func observeTimeControl() {
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { _, _ in
            Task { @MainActor [weak self] in
                self?.syncStateWithPlayer()
            }
        }
    }

    private func startTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self, seconds.isFinite else { return }
                self.elapsed = max(0, Double(seconds))
            }
        }
    }

    private func syncStateWithPlayer() {
        guard !slots.isEmpty else {
            state = .idle
            return
        }
        switch player.timeControlStatus {
        case .playing:
            state = .playing
        case .waitingToPlayAtSpecifiedRate:
            state = .buffering
        case .paused:
            if state == .failed { break }
            // A pause the app did not ask for: the system parks the
            // player for a moment when the output route is switched
            // (the audio-only AirPlay handover does this) and does not
            // always resume it. `pause()` and `stop()` clear
            // `wantsToPlay`, so a deliberate pause is never overridden;
            // while the app still wants audio and no interruption holds
            // the session, resume. If the current item is dead,
            // `play()` does not change the status, so this cannot loop.
            if wantsToPlay, !isInterrupted {
                player.play()
                state = .buffering
            } else {
                state = .paused
            }
        @unknown default:
            state = .idle
        }
    }

    // MARK: - Notifications

    private func observePlayerEvents() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let endedID = Self.itemID(from: notification)
            Task { @MainActor [weak self] in
                self?.handleItemEnded(endedID)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let failedID = Self.itemID(from: notification)
            Task { @MainActor [weak self] in
                self?.handleItemFailed(failedID)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .playing else { return }
                self.state = .buffering
            }
        }
    }

    private func observeSessionEvents() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = Self.interruptionTypeValue(from: notification)
            let rawOptions = Self.interruptionOptionsValue(from: notification)
            Task { @MainActor [weak self] in
                self?.handleInterruption(type: rawType, options: rawOptions)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawReason = Self.routeChangeReasonValue(from: notification)
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reason: rawReason)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }
    }

    // MARK: - Event handling

    private func handleItemEnded(_ endedID: ObjectIdentifier?) {
        guard let endedID, let first = slots.first,
              ObjectIdentifier(first.item) == endedID else { return }
        // The queue advanced on its own — adopt the next slot.
        finishOutgoingTrack()
        slots.removeFirst()
        onTrackEnded?()
        if let next = slots.first {
            currentTrack = next.track
            elapsed = 0
            duration = TimeInterval(next.track.duration)
            state = .playing
        } else {
            currentTrack = nil
            elapsed = 0
            duration = 0
            state = .idle
        }
        requestMoreTracksIfNeeded()
    }

    private func handleItemFailed(_ failedID: ObjectIdentifier?) {
        guard let failedID, let first = slots.first,
              ObjectIdentifier(first.item) == failedID else { return }
        AppLog.error("player item failed to play to end", .playback)
        fail("Playback failed. Tap next to skip this track.")
    }

    private func handleInterruption(type: UInt?, options: UInt) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        AppLog.info("audio session interruption: \(kind.rawValue)", .playback)
        switch kind {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            isInterrupted = true
            player.pause()
            state = .paused
        case .ended:
            isInterrupted = false
            let resumeOptions = AVAudioSession.InterruptionOptions(rawValue: options)
            if wasPlayingBeforeInterruption, resumeOptions.contains(.shouldResume) {
                activateAudioSession()
                player.play()
                state = .playing
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reason: UInt?) {
        guard let reason, let kind = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }
        AppLog.info("audio route change: \(kind.rawValue)", .playback)
        // AVPlayer follows the output route on its own — external
        // playback carries AirPlay, the session's audio graph carries
        // everything else; a player item is not bound to the renderer
        // it was created for. Replacing the item here tore down the
        // handover the system was in the middle of establishing (the
        // music stopped instead of moving), so no player work belongs
        // in this path. The new route is published for the UI, and if
        // the system paused the player as part of the switch, the
        // timeControlStatus observer resumes it: `wantsToPlay` is still
        // set and no interruption is active.
        refreshOutputRoute()
        if kind == .categoryChange {
            // Our own category change, or the system's. Re-apply the
            // sharing policy, but never re-activate from here — that
            // would post another category change and loop.
            configureAudioSession()
        }
    }

    /// The media stack was reset (e.g. after the audio daemon restarted):
    /// the old AVPlayer is dead, so build a fresh one and restore the queue.
    private func handleMediaServicesReset() {
        AppLog.error("media services were reset — rebuilding the player", .playback)
        let wasPlaying = isPlaying
        let remaining = slots
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        timeControlObservation = nil
        player = AVQueuePlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        // The fresh player starts at full volume — restore the level
        // the user had set.
        player.volume = volume
        observeTimeControl()
        startTimeObserver()
        slots = []
        player.removeAllItems()
        var lastItem: AVPlayerItem?
        for slot in remaining {
            guard let item = makeItem(for: slot.track) else { continue }
            if let lastItem {
                player.insert(item, after: lastItem)
            } else {
                player.insert(item, after: nil)
            }
            lastItem = item
            slots.append(Slot(track: slot.track, item: item))
        }
        currentTrack = slots.first?.track
        if wasPlaying, !slots.isEmpty {
            activateAudioSession()
            player.play()
            state = .playing
        }
    }

    // MARK: - Notification payload helpers

    // Notification payloads are not Sendable; only plain values cross into
    // the main actor.

    private nonisolated static func itemID(from notification: Notification) -> ObjectIdentifier? {
        guard let item = notification.object as? AVPlayerItem else { return nil }
        return ObjectIdentifier(item)
    }

    private nonisolated static func interruptionTypeValue(from notification: Notification) -> UInt? {
        notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
    }

    private nonisolated static func interruptionOptionsValue(from notification: Notification) -> UInt {
        notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
    }

    private nonisolated static func routeChangeReasonValue(from notification: Notification) -> UInt? {
        notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
    }
}
