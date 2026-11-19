import SwiftUI
import UIKit

/// Reports a view's frame in **window coordinates** — the one space the
/// mini player's cover and the full player's cover can be compared in.
///
/// SwiftUI's `.global` coordinate space is rooted at each presentation,
/// so the pill's frame and the sheet's frame cannot be compared through
/// it. A UIKit probe can: the sheet is presented in the app's window,
/// so both frames land in the same space — and the flight checks that
/// they do before it flies anything.
///
/// The frame is taken through the **layer** conversion, not
/// `UIView.convert(_:to:)`: the sheet's own rise and SwiftUI's own
/// render-time transforms are layer transforms, and only the layer
/// conversion is guaranteed to see them. Both probes are read the same
/// way, so the two frames are always comparable.
struct WindowFrameProbe: UIViewRepresentable {
    /// Called once, when the probe view exists, so its owner can query
    /// the frame on demand (the mini player reads its cover's place at
    /// the moment the player opens, not from a cached value).
    var onProbe: (@MainActor (ProbeView) -> Void)?

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        onProbe?(view)
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}

    /// The measuring view. It is empty and non-interactive — it only
    /// knows where it is.
    @MainActor
    final class ProbeView: UIView {
        /// The view's frame in its window's coordinate space. `nil`
        /// until the view is in a window.
        var windowFrame: CGRect? {
            guard let window else { return nil }
            return layer.convert(bounds, to: window.layer)
        }

        var hostWindow: UIWindow? { window }
    }
}

/// The artwork flight's shared state — the pill's cover and the
/// player's cover, in window coordinates, and the frozen origin of a
/// flight.
///
/// Plain (not `@Observable`) on purpose: the values are read on demand
/// from the probes, and SwiftUI must not read those reads as
/// publications. The views read them imperatively at the moments they
/// need them.
@MainActor
final class ArtworkFlightCoordinator {
    /// The pill's cover probe.
    private weak var miniProbe: WindowFrameProbe.ProbeView?
    /// The player's cover probe.
    private weak var playerProbe: WindowFrameProbe.ProbeView?

    /// The pill's cover at the moment the player was opened — the
    /// flight's origin.
    private(set) var originFrame: CGRect?
    /// The window the origin was measured in. The flight only runs when
    /// the player lands in the same window.
    private(set) var originWindow: UIWindow?

    /// `nonisolated`: the coordinator is main-actor work, but creating
    /// one must be possible from a plain property initializer.
    nonisolated init() {}

    func registerMiniProbe(_ probe: WindowFrameProbe.ProbeView) {
        miniProbe = probe
    }

    func registerPlayerProbe(_ probe: WindowFrameProbe.ProbeView) {
        playerProbe = probe
    }

    /// Freezes the pill's cover as the flight's origin. Called at the
    /// moment the user opens the player, so the frame is the current
    /// one.
    func captureOrigin() {
        guard let probe = miniProbe,
              let window = probe.hostWindow,
              let frame = probe.windowFrame,
              frame.width > 1, frame.height > 1
        else { return }
        originFrame = frame
        originWindow = window
    }

    /// The player's cover, measured now.
    func currentDestination() -> (frame: CGRect, window: UIWindow?)? {
        guard let probe = playerProbe,
              let window = probe.hostWindow,
              let frame = probe.windowFrame,
              frame.width > 1, frame.height > 1
        else { return nil }
        return (frame, window)
    }
}

private struct ArtworkFlightKey: EnvironmentKey {
    static let defaultValue: ArtworkFlightCoordinator? = nil
}

extension EnvironmentValues {
    /// The artwork flight's coordinator — present while the mini player
    /// and the full player can talk to each other. `nil` means there is
    /// no flight, and every host falls back to the plain cover.
    var artworkFlight: ArtworkFlightCoordinator? {
        get { self[ArtworkFlightKey.self] }
        set { self[ArtworkFlightKey.self] = newValue }
    }
}
