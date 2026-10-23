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

    private(set) var currentTrack: Track?
    private(set) var state: PlaybackState = .idle
    /// Playback position in seconds.
    private(set) var elapsed: TimeInterval = 0
    /// Track length in seconds (from Pandora's `trackLength`).
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?

    var isPlaying: Bool { state == .playing || state == .buffering }

    // MARK: Callbacks (set by the owner)

    /// Fired when the queue holds ≤ 1 playable track — fetch another
    /// playlist and hand it back via `enqueue(_:)`.
    var onNeedMoreTracks: (() -> Void)?
    /// Fired when the current track played to its end.
    var onTrackEnded: (() -> Void)?
    /// Fired when playback of the current track failed.
    var onPlaybackFailed: ((String) -> Void)?

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

    // MARK: Init

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        observeTimeControl()
        startTimeObserver()
        observePlayerEvents()
        observeSessionEvents()
    }

    // MARK: - Public API

    /// Starts a track, queueing the next one for a gapless hand-over.
    func play(track: Track, prefetching next: Track?) {
        resetQueue()
        guard let item = makeItem(for: track) else {
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
        requestMoreTracksIfNeeded()
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
            }
        }
        requestMoreTracksIfNeeded()
    }

    /// Skip to the next track (user action).
    func skipToNext() {
        guard !slots.isEmpty else { return }
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
    }

    func resume() {
        guard !slots.isEmpty else { return }
        activateAudioSession()
        player.play()
        state = .playing
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

    /// Stops playback and clears the queue (sign-out, station switch).
    func stop() {
        resetQueue()
        currentTrack = nil
        elapsed = 0
        duration = 0
        state = .idle
        deactivateAudioSession()
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Queue internals

    private func resetQueue() {
        player.removeAllItems()
        slots.removeAll()
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
        errorMessage = message
        state = .failed
        onPlaybackFailed?(message)
    }

    // MARK: - Audio session

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Couldn't start audio output."
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            state = .paused
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
        fail("Playback failed. Tap next to skip this track.")
    }

    private func handleInterruption(type: UInt?, options: UInt) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch kind {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            player.pause()
            state = .paused
        case .ended:
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
        switch kind {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange:
            // Keep playing on the new route.
            activateAudioSession()
        default:
            break
        }
    }

    /// The media stack was reset (e.g. after the audio daemon restarted):
    /// the old AVPlayer is dead, so build a fresh one and restore the queue.
    private func handleMediaServicesReset() {
        let wasPlaying = isPlaying
        let remaining = slots
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        timeControlObservation = nil
        player = AVQueuePlayer()
        player.automaticallyWaitsToMinimizeStalling = true
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
