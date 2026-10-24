import AVFoundation
import Foundation
import MediaPlayer
import PandoraCore
import UIKit

/// Lock-screen / Control Center integration.
///
/// Publishes the current track to `MPNowPlayingInfoCenter` and wires the
/// transport controls (`MPRemoteCommandCenter`) to the player:
/// play, pause, toggle, next track and skip forward 15 s.
///
/// The service is owned by `AppStore` and lives for the whole app
/// session; it holds the player weakly so it can never keep the player
/// alive on its own.
@MainActor
final class NowPlayingService {

    private weak var player: PlayerService?
    private var timeObserver: Any?
    private var artworkTask: Task<Void, Never>?

    init(player: PlayerService) {
        self.player = player
        player.onTrackChanged.append { [weak self] track in
            self?.updateNowPlaying(for: track)
        }
        player.onPlaybackStateChanged.append { [weak self] in
            self?.updatePlaybackState()
        }
        updateNowPlaying(for: player.currentTrack)
        configureRemoteCommands()
        observeElapsedTime()
    }
    // MARK: - Now Playing info

    private func updateNowPlaying(for track: Track?) {
        let center = MPNowPlayingInfoCenter.default()
        guard let track else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: TimeInterval(track.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.elapsed ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: player?.isPlaying == true ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        center.nowPlayingInfo = info
        loadArtwork(for: track)
    }

    /// Album art for the lock screen. It comes from the shared artwork
    /// cache, so the lock screen reuses the image the in-app player
    /// already downloaded instead of fetching it a second time. The
    /// image is produced off the main actor and applied on it; only
    /// `Data` crosses the boundary so the Swift 6 concurrency rules stay
    /// satisfied.
    private func loadArtwork(for track: Track) {
        guard let urlString = track.artworkUrl else {
            AppLog.debug("lock screen: track has no artwork URL", .playback)
            return
        }
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            let image = await ArtworkCache.shared.image(for: urlString)
            guard !Task.isCancelled else { return }
            self?.applyArtwork(image)
        }
    }

    private func applyArtwork(_ image: UIImage?) {
        guard let image else {
            AppLog.debug("lock screen: artwork unavailable", .playback)
            return
        }
        AppLog.info("lock screen artwork applied (\(Int(image.size.width))×\(Int(image.size.height)))", .playback)
        let artwork = Self.lockScreenArtwork(for: image)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// MediaPlayer invokes an artwork request handler on its own internal
    /// dispatch queue (never the main actor) whenever the system renders
    /// the lock screen. A closure formed inside a @MainActor method
    /// inherits that isolation, and Swift 6's dynamic isolation check
    /// (`dispatch_assert_queue`) then traps at runtime when MediaPlayer
    /// calls it off-main — SIGTRAP seconds after playback starts. Built
    /// here, in a nonisolated context, the handler carries no isolation;
    /// `UIGraphicsImageRenderer` is thread-safe so scaling off-main is
    /// fine.
    private nonisolated static func lockScreenArtwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable requestedSize in
            guard requestedSize.width > 0, requestedSize.width < image.size.width else {
                return image
            }
            return UIGraphicsImageRenderer(size: requestedSize).image { _ in
                image.draw(in: CGRect(origin: .zero, size: requestedSize))
            }
        }
    }

    private func updatePlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.isPlaying == true ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.elapsed ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func observeElapsedTime() {
        timeObserver = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePlaybackState()
            }
        }
    }
    // MARK: - Remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player?.resume()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player?.pause()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player?.togglePlayback()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player?.skipToNext()
            }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player?.skipForward(by: 15)
            }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player?.skipBackward(by: 15)
            }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            // Extract the value before crossing into the main actor — the
            // event object itself is not Sendable.
            let position = positionEvent.positionTime
            Task { @MainActor [weak self] in
                self?.player?.seek(to: position)
            }
            return .success
        }
    }
}
