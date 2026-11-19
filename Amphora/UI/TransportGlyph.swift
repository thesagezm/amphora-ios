import SwiftUI
import PandoraCore

/// The playback-control icon family, copied exactly from BitChord.
///
/// The user's direction (2026-11-19): "the playback control icons copy
/// exactly those from bitchord". The shapes are BitChord's own transport
/// drawables — `ic_player_play`, `ic_player_pause`, `ic_player_next`,
/// `ic_player_previous` (960×960 viewports) — their `pathData` verbatim
/// in `TransportIconPaths` (PandoraCore), rendered here 1:1.
///
/// The sizing relationships are BitChord's too, verbatim: their
/// `TransportRow` renders the play/pause drawables in a 74dp box and the
/// skip drawables in a 53dp box squashed to 0.85 height
/// (`PLAYER_SKIP_HEIGHT_SCALE`), "so the pair reads lower and longer
/// next to the play button". This view's `size` is the play glyph's
/// rendered height — the family's yardstick — and the skip glyphs scale
/// themselves against it exactly as BitChord's do.
///
/// One deliberate difference: BitChord's mini player mixes Material's
/// `PlayArrow`/`Pause` into the same slots. Amphora keeps the copied
/// family on every surface — mini player, hero tiles, full player — so
/// the app reads as one design language.
///
/// Two glyphs BitChord does not ship, and how they are handled:
///
/// - **Stop** (the radio branch's trailing button): drawn in the
///   family's language — a 480-unit square with the pause bars' 40-unit
///   corner radius — and rendered at the skip glyphs' height, so the
///   radio slot matches the song slot.
/// - **Back 15**: there is no BitChord back-15, so the family's
///   `ic_player_previous` takes the slot, exactly as it leads BitChord's
///   own transport row. The action stays Pandora's back-15 (radio has no
///   previous track to skip to) and the VoiceOver label says what the
///   button does, not what the glyph resembles.
struct TransportGlyph: View {
    enum Kind {
        case play, pause, next, previous, stop
    }

    /// The four copied drawables plus the family-language stop, parsed
    /// once and reused by every surface.
    private static let play = TransportIconPaths.icon(TransportIconPaths.playData)
    private static let pause = TransportIconPaths.icon(TransportIconPaths.pauseData)
    private static let next = TransportIconPaths.icon(TransportIconPaths.nextData)
    private static let previous = TransportIconPaths.icon(TransportIconPaths.previousData)
    private static let stop = TransportIconPaths.icon(TransportIconPaths.stopData)

    /// BitChord's transport constants, verbatim: the skip drawables'
    /// 53dp box against the play drawable's 74dp box, and their
    /// `PLAYER_SKIP_HEIGHT_SCALE`.
    private static let skipBoxToPlayBox: CGFloat = 53 / 74
    private static let skipHeightScale: CGFloat = 0.85

    let kind: Kind
    /// The rendered height of the play glyph's ink — every other glyph
    /// in the family scales against it.
    var size: CGFloat
    var color: Color = .primary

    /// Explicit init on purpose: the synthesized memberwise init would
    /// demand the `kind:` label, and the family's point is terse call
    /// sites — `TransportGlyph(.play, size: 32)` in the transports, with
    /// the color where the glyph sits on the accent fill.
    init(_ kind: Kind, size: CGFloat, color: Color = .primary) {
        self.kind = kind
        self.size = size
        self.color = color
    }

    var body: some View {
        if let rendered {
            rendered
        } else {
            Color.clear
                .frame(width: max(1, size), height: max(1, size))
        }
    }

    /// The glyph at BitChord's proportions, or `nil` when the path data
    /// failed to parse (never expected — the strings are constants).
    @ViewBuilder
    private var rendered: some View {
        if let icon = Self.icon(for: kind), let bounds = icon.bounds,
           bounds.width > 0, bounds.height > 0 {
            let frame = Self.frame(bounds: bounds, kind: kind, size: size)
            TransportIconShape(icon: icon)
                .fill(color)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(y: Self.squash(of: kind))
        }
    }

    /// The glyph's frame, at BitChord's boxes scaled so the play
    /// glyph's ink stands `size` tall.
    private static func frame(bounds: VectorBounds, kind: Kind, size: CGFloat) -> CGSize {
        let viewport = CGFloat(TransportIconPaths.viewport)
        guard let playBounds = play.bounds, playBounds.height > 0 else {
            return CGSize(width: max(1, size), height: max(1, size))
        }
        // The box that renders the play drawable's ink `size` tall.
        let playBox = size * viewport / CGFloat(playBounds.height)
        switch kind {
        case .play, .pause:
            return CGSize(
                width: playBox * CGFloat(bounds.width) / viewport,
                height: playBox * CGFloat(bounds.height) / viewport
            )
        case .next, .previous:
            let skipBox = playBox * skipBoxToPlayBox
            return CGSize(
                width: skipBox * CGFloat(bounds.width) / viewport,
                height: skipBox * CGFloat(bounds.height) / viewport
            )
        case .stop:
            // BitChord ships no stop; ours renders at the skip glyphs'
            // rendered (squashed) height, so the radio slot matches the
            // song slot.
            let skipInkHeight = CGFloat(next.bounds?.height ?? bounds.height)
            let side = playBox * skipBoxToPlayBox * skipHeightScale
                * skipInkHeight / viewport
            return CGSize(width: side, height: side)
        }
    }

    /// BitChord squashes the skip glyphs to 0.85 height — visually only
    /// (`graphicsLayer`): the layout box keeps the drawable's height,
    /// the rendered glyph reads lower and longer. `scaleEffect` is
    /// SwiftUI's identical mechanism.
    private static func squash(of kind: Kind) -> CGFloat {
        kind == .next || kind == .previous ? skipHeightScale : 1
    }

    private static func icon(for kind: Kind) -> TransportIcon {
        switch kind {
        case .play: return play
        case .pause: return pause
        case .next: return next
        case .previous: return previous
        case .stop: return stop
        }
    }
}

/// Renders a parsed icon 1:1: the ink bounds stretch to the frame — a
/// uniform stretch for every glyph (each frame is the ink's own aspect,
/// and the skip squash is applied *outside*, as BitChord applies it), so
/// the arcs stay true arcs.
private struct TransportIconShape: Shape {
    let icon: TransportIcon

    func path(in rect: CGRect) -> Path {
        guard let bounds = icon.bounds, bounds.width > 0, bounds.height > 0 else {
            return Path()
        }
        let scaleX = rect.width / CGFloat(bounds.width)
        let scaleY = rect.height / CGFloat(bounds.height)
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: rect.minX + CGFloat(x - bounds.minX) * scaleX,
                y: rect.minY + CGFloat(y - bounds.minY) * scaleY
            )
        }
        var path = Path()
        for subpath in icon.subpaths {
            for segment in subpath.segments {
                switch segment {
                case .move(let x, let y):
                    path.move(to: point(x, y))
                case .line(let x, let y):
                    path.addLine(to: point(x, y))
                case .arc(
                    let centerX, let centerY, let radius,
                    let start, let end, let clockwiseOnScreen):
                    path.addArc(
                        center: point(centerX, centerY),
                        radius: CGFloat(radius) * scaleX,
                        startAngle: .degrees(start),
                        endAngle: .degrees(end),
                        // A clockwise-on-screen sweep is SwiftUI's
                        // counterclockwise flag — see VectorSegment.
                        clockwise: !clockwiseOnScreen
                    )
                case .close:
                    path.closeSubpath()
                }
            }
        }
        return path
    }
}
