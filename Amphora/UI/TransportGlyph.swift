import SwiftUI

/// The transport's icon family, drawn rather than borrowed.
///
/// The system's filled media glyphs read chunky at transport sizes —
/// `play.fill` rendered at 58 pt bold is a heavy wedge and the
/// double-triangle `forward.fill` looks dated (the user called them
/// "substandard"). These five glyphs are drawn to one design language
/// instead: soft-rounded corners, matched visual weight across the
/// family, and every proportion derived from the square the glyph is
/// drawn in — so play at 16 pt and play at 44 pt are the same icon,
/// scaled.
struct TransportGlyph: View {
    enum Kind {
        case play, pause, next, stop, back15
    }

    let kind: Kind
    /// The side of the square the glyph is drawn within.
    var size: CGFloat
    var color: Color = .primary

    /// Explicit init on purpose: the synthesized memberwise init would
    /// demand the `kind:` label, and the whole point of the family is
    /// terse call sites — `TransportGlyph(.play, size: 44)` and
    /// `TransportGlyph(.back15, size: 27)` in the transports, with the
    /// color where the glyph sits on the accent fill instead of white.
    init(_ kind: Kind, size: CGFloat, color: Color = .primary) {
        self.kind = kind
        self.size = size
        self.color = color
    }

    var body: some View {
        switch kind {
        case .play:
            RoundedTriangle()
                .fill(color)
                .frame(width: size * 0.92, height: size)
        case .pause:
            HStack(spacing: size * 0.16) {
                pauseBar
                pauseBar
            }
            .frame(height: size)
        case .next:
            HStack(spacing: size * 0.07) {
                RoundedTriangle()
                    .fill(color)
                    .frame(width: size * 0.62, height: size * 0.96)
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .fill(color)
                    .frame(width: size * 0.13, height: size * 0.96)
            }
            .frame(height: size)
        case .stop:
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(color)
                .frame(width: size * 0.74, height: size * 0.74)
        case .back15:
            BackFifteenGlyph(size: size, color: color)
        }
    }

    /// One pause bar: a slim rounded rectangle, full height.
    private var pauseBar: some View {
        RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
            .fill(color)
            .frame(width: size * 0.20, height: size * 0.96)
    }
}

/// A right-pointing triangle with softened corners. The corner radius
/// is proportional to the triangle's own size, so the play glyph and
/// the triangle inside the next glyph round identically at any scale.
private struct RoundedTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        roundedPolygon(
            [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ],
            cornerRadius: min(rect.width, rect.height) * 0.10
        )
    }
}

/// A closed polygon with each corner softened by a quadratic curve —
/// the edge is trimmed `cornerRadius` short of the vertex on both
/// sides and the vertex itself becomes the curve's control point.
private func roundedPolygon(_ points: [CGPoint], cornerRadius: CGFloat) -> Path {
    var path = Path()
    let count = points.count
    guard count >= 3 else { return path }
    for i in 0..<count {
        let previous = points[(i + count - 1) % count]
        let current = points[i]
        let next = points[(i + 1) % count]
        let toPrevious = CGPoint(x: previous.x - current.x, y: previous.y - current.y)
        let toNext = CGPoint(x: next.x - current.x, y: next.y - current.y)
        let previousLength = max(hypot(toPrevious.x, toPrevious.y), 0.001)
        let nextLength = max(hypot(toNext.x, toNext.y), 0.001)
        // Never trim past the middle of the adjoining edges.
        let trim = min(cornerRadius, previousLength / 2, nextLength / 2)
        let start = CGPoint(
            x: current.x + toPrevious.x / previousLength * trim,
            y: current.y + toPrevious.y / previousLength * trim
        )
        let end = CGPoint(
            x: current.x + toNext.x / nextLength * trim,
            y: current.y + toNext.y / nextLength * trim
        )
        if i == 0 {
            path.move(to: start)
        } else {
            path.addLine(to: start)
        }
        path.addQuadCurve(to: end, control: current)
    }
    path.closeSubpath()
    return path
}

/// "Back 15 seconds": a nearly-full circle with the gap at the upper
/// left and the arrowhead at the top pointing counterclockwise, the
/// number inside — the shape language of the system's gobackward.15,
/// drawn to match the family's weight.
private struct BackFifteenGlyph: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            BackFifteenArc()
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round)
                )
            BackFifteenArrowhead()
                .fill(color)
            Text("15")
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 290° of circle ending at the top, sweeping counterclockwise: the
/// gap lands in the upper left and the direction of travel at the end
/// (the top) is leftward — where the arrowhead sits.
private struct BackFifteenArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) * 0.40,
            startAngle: .degrees(200),
            endAngle: .degrees(-90),
            clockwise: false
        )
        return path
    }
}

/// The arrowhead at the top of the back-15 arc, pointing left
/// (counterclockwise) — the direction the arc ends travelling. The
/// tip extends past the arc's end and the base overlaps the stroke's
/// round cap, so the two read as one stroke.
private struct BackFifteenArrowhead: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        // The arc ends at the top of the circle (midX, midY - 0.40 size).
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - size * 0.135, y: rect.midY - size * 0.40))
        path.addLine(to: CGPoint(x: rect.midX + size * 0.01, y: rect.midY - size * 0.495))
        path.addLine(to: CGPoint(x: rect.midX + size * 0.01, y: rect.midY - size * 0.305))
        path.closeSubpath()
        return path
    }
}
