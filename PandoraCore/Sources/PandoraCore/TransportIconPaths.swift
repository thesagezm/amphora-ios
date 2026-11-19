//
//  TransportIconPaths.swift
//  PandoraCore
//
//  The playback-control icon geometry, copied exactly from BitChord's
//  transport drawables — `ic_player_play`, `ic_player_pause`,
//  `ic_player_next`, `ic_player_previous` (960×960 viewports,
//  Material-Symbols-rounded shapes). The user's direction for Amphora's
//  transport (2026-11-19): "the playback control icons copy exactly
//  those from bitchord".
//
//  The drawables' `pathData` is kept verbatim and turned into
//  platform-neutral segments by a small SVG path-data interpreter —
//  the M/L/A/Z subset these drawables are written in, absolute
//  commands only. Pure Foundation: an iOS shape renders the segments
//  with `Path.addArc`, and a future Android port renders the identical
//  geometry with `Path.arcTo` (both measure angles in a y-down space,
//  0° at 3 o'clock, increasing clockwise on screen).
//
//  Why the geometry lives here and not in the app: the arc centers are
//  derived from the path data (each rounded corner is an arc whose
//  bulge past its vertices is part of the ink), and the derived ink
//  bounds are what the renderer fits to a frame. That math is exactly
//  the kind of thing this package unit-tests — the app target has no
//  test target of its own.
//

import Foundation

/// The ink extent of a parsed vector icon, in viewport units.
public struct VectorBounds: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

/// One platform-neutral piece of a vector path.
///
/// Angles are degrees in a y-down space — 0° points right, 90° points
/// down, and angles increase clockwise on screen. That is the convention
/// Android's canvas draws in and SwiftUI's `Path` measures in (SwiftUI's
/// `clockwise:` flag is the inverse of it: an on-screen clockwise sweep
/// is `clockwise: false`).
public enum VectorSegment: Equatable, Sendable {
    /// Starts a subpath at (x, y).
    case move(x: Double, y: Double)
    /// A straight line to (x, y).
    case line(x: Double, y: Double)
    /// A circular arc around `center`, from `startAngleDegrees` to
    /// `endAngleDegrees` — already normalized in the sweep's direction,
    /// so a renderer sweeps from start to end and nothing else.
    case arc(
        centerX: Double,
        centerY: Double,
        radius: Double,
        startAngleDegrees: Double,
        endAngleDegrees: Double,
        clockwiseOnScreen: Bool)
    /// Closes the subpath with a straight line back to its start.
    case close
}

/// One subpath: a `move`, its body, and optionally a `close`.
public struct VectorSubpath: Equatable, Sendable {
    public let segments: [VectorSegment]

    public init(segments: [VectorSegment]) {
        self.segments = segments
    }
}

/// A parsed vector icon: its subpaths and the bounding box of its ink.
public struct TransportIcon: Equatable, Sendable {
    public let subpaths: [VectorSubpath]
    /// Every line endpoint and every arc's extremes included — the
    /// rounded corners bulge past their vertices, so the bounds are the
    /// drawable's real ink, not its vertex coordinates. `nil` for an
    /// empty or unparsable icon.
    public let bounds: VectorBounds?

    public init(subpaths: [VectorSubpath], bounds: VectorBounds?) {
        self.subpaths = subpaths
        self.bounds = bounds
    }
}

/// The transport icon geometry and the interpreter that reads it.
public enum TransportIconPaths {

    /// The drawables' viewport (both dimensions).
    public static let viewport = 960.0

    /// BitChord's `ic_player_play`, verbatim.
    public static let playData = "M406.6,242.0 L699.6,433.1 A56,56 0 0 1 699.6,526.9 L406.6,718.0 A56,56 0 0 1 320.0,671.0 L320.0,289.0 A56,56 0 0 1 406.6,242.0 Z"

    /// BitChord's `ic_player_pause`, verbatim.
    public static let pauseData = "M325,240 L405,240 A40,40 0 0 1 445,280 L445,680 A40,40 0 0 1 405,720 L325,720 A40,40 0 0 1 285,680 L285,280 A40,40 0 0 1 325,240 Z M555,240 L635,240 A40,40 0 0 1 675,280 L675,680 A40,40 0 0 1 635,720 L555,720 A40,40 0 0 1 515,680 L515,280 A40,40 0 0 1 555,240 Z"

    /// BitChord's `ic_player_next`, verbatim.
    public static let nextData = "M144.5,207.9 L462.0,434.4 A56,56 0 0 1 462.0,525.6 L144.5,752.1 A56,56 0 0 1 55.9,706.5 L55.9,253.5 A56,56 0 0 1 144.5,207.9 Z M563.7,207.9 L881.3,434.4 A56,56 0 0 1 881.3,525.6 L563.7,752.1 A56,56 0 0 1 475.2,706.5 L475.2,253.5 A56,56 0 0 1 563.7,207.9 Z"

    /// BitChord's `ic_player_previous`, verbatim.
    public static let previousData = "M814.2,207.9 L496.7,434.4 A56,56 0 0 0 496.7,525.6 L814.2,752.1 A56,56 0 0 0 902.7,706.5 L902.7,253.5 A56,56 0 0 0 814.2,207.9 Z M398.3,207.9 L80.7,434.4 A56,56 0 0 0 80.7,525.6 L398.3,752.1 A56,56 0 0 0 486.8,706.5 L486.8,253.5 A56,56 0 0 0 398.3,207.9 Z"

    /// The one glyph BitChord does not ship — their player has no stop,
    /// because they have no radio. Ours is drawn in the same language: a
    /// 480-unit square with the pause bars' 40-unit corner radius, so it
    /// reads as family next to the copied drawables.
    public static let stopData = "M280,240 L680,240 A40,40 0 0 1 720,280 L720,680 A40,40 0 0 1 680,720 L280,720 A40,40 0 0 1 240,680 L240,280 A40,40 0 0 1 280,240 Z"

    /// Parses path data into an icon. Malformed or unsupported data
    /// yields an empty icon rather than an error — the inputs are
    /// compile-time constants, and a renderer shows nothing rather than
    /// a wrong shape.
    public static func icon(_ pathData: String) -> TransportIcon {
        let parsed = subpaths(in: pathData)
        return TransportIcon(subpaths: parsed, bounds: bounds(of: parsed))
    }

    // MARK: - The interpreter

    /// Parses the M/L/A/Z absolute-command subset the drawables use,
    /// including SVG's implicit repeats (coordinate pairs after a
    /// `moveto` are linetos; extra parameter sets after an `arc` repeat
    /// the arc). Relative commands and elliptical arcs (rx ≠ ry, or a
    /// non-zero axis rotation) are not supported and reject the data.
    public static func subpaths(in pathData: String) -> [VectorSubpath] {
        guard let tokens = tokenize(pathData) else { return [] }

        var subpaths: [VectorSubpath] = []
        var current: [VectorSegment] = []
        var command: Command?
        var pending: [Double] = []
        var point: (x: Double, y: Double)?
        var movedAtCurrentCommand = false

        func flushSubpath() {
            if !current.isEmpty {
                subpaths.append(VectorSubpath(segments: current))
                current = []
            }
        }

        for token in tokens {
            switch token {
            case .command(let letter):
                guard pending.isEmpty, let parsed = Command(letter) else { return [] }
                command = parsed
                movedAtCurrentCommand = false
                if parsed == .closePath {
                    current.append(.close)
                    flushSubpath()
                }
            case .number(let value):
                guard let active = command else { return [] }
                pending.append(value)
                guard pending.count == active.arity else { continue }
                let parameters = pending
                pending = []
                switch active {
                case .moveTo:
                    let x = parameters[0], y = parameters[1]
                    if movedAtCurrentCommand {
                        // SVG's implicit repeat: coordinate pairs after
                        // a moveto are linetos, continuing the subpath.
                        guard point != nil else { return [] }
                        point = (x, y)
                        current.append(.line(x: x, y: y))
                    } else {
                        // A fresh moveto ends the previous subpath even
                        // without a close.
                        flushSubpath()
                        point = (x, y)
                        current.append(.move(x: x, y: y))
                    }
                    movedAtCurrentCommand = true
                case .lineTo:
                    guard point != nil else { return [] }
                    point = (parameters[0], parameters[1])
                    current.append(.line(x: parameters[0], y: parameters[1]))
                case .arcTo:
                    guard let from = point else { return [] }
                    guard let arc = arcSegment(from: from, parameters: parameters) else { return [] }
                    point = (parameters[5], parameters[6])
                    current.append(arc)
                case .closePath:
                    break // handled at the command letter
                }
            }
        }
        guard pending.isEmpty else { return [] }
        flushSubpath()
        return subpaths
    }

    private enum Command {
        case moveTo, lineTo, arcTo, closePath

        init?(_ letter: Character) {
            switch letter {
            case "M": self = .moveTo
            case "L": self = .lineTo
            case "A": self = .arcTo
            case "Z": self = .closePath
            default: return nil
            }
        }

        var arity: Int {
            switch self {
            case .moveTo, .lineTo: return 2
            case .arcTo: return 7
            case .closePath: return 0
            }
        }
    }

    private enum Token {
        case command(Character)
        case number(Double)
    }

    private static func tokenize(_ data: String) -> [Token]? {
        var tokens: [Token] = []
        var number = ""

        func flushNumber() -> Bool {
            guard !number.isEmpty else { return true }
            guard let value = Double(number) else { return false }
            tokens.append(.number(value))
            number = ""
            return true
        }

        for character in data {
            switch character {
            case "M", "L", "A", "Z":
                guard flushNumber() else { return nil }
                tokens.append(.command(character))
            case "0"..."9", "-", "+", ".", "e", "E":
                number.append(character)
            case ",", " ", "\n", "\t", "\r":
                guard flushNumber() else { return nil }
            default:
                return nil // relative commands and anything else: unsupported
            }
        }
        guard flushNumber() else { return nil }
        return tokens
    }

    /// Turns one `A` command into an arc segment: derives the circle's
    /// center from the chord, the radius, the sweep direction and the
    /// large-arc flag, and normalizes the angles so the sweep direction
    /// is unambiguous.
    private static func arcSegment(
        from: (x: Double, y: Double),
        parameters: [Double]
    ) -> VectorSegment? {
        let radius = parameters[0]
        let rotation = parameters[2]
        let largeArc = parameters[3]
        let sweep = parameters[4]
        let to = (x: parameters[5], y: parameters[6])
        guard radius > 0, parameters[1] == radius, rotation == 0,
              largeArc == 0 || largeArc == 1, sweep == 0 || sweep == 1
        else { return nil }

        let dx = to.x - from.x
        let dy = to.y - from.y
        let chord = (dx * dx + dy * dy).squareRoot()
        guard chord > 0 else { return nil }
        let half = chord / 2
        // SVG scales an too-small radius up to the chord's half.
        let r = max(radius, half)
        let distance = (r * r - half * half).squareRoot()

        // The right-of-travel normal in a y-down space.
        let normalX = -dy / chord
        let normalY = dx / chord
        // sweep 1 draws clockwise on screen; with the large-arc flag it
        // picks which of the two candidate centers the arc swings
        // around — the minor arc's center sits on the right of travel,
        // the major arc's on the left.
        let side: Double = (sweep == 1) == (largeArc == 0) ? 1 : -1
        let centerX = from.x + dx / 2 + side * distance * normalX
        let centerY = from.y + dy / 2 + side * distance * normalY

        let start = angle(of: from, around: (centerX, centerY))
        var end = angle(of: to, around: (centerX, centerY))
        if sweep == 1 {
            while end <= start { end += 360 }
        } else {
            while end >= start { end -= 360 }
        }
        return .arc(
            centerX: centerX,
            centerY: centerY,
            radius: r,
            startAngleDegrees: start,
            endAngleDegrees: end,
            clockwiseOnScreen: sweep == 1
        )
    }

    private static func angle(
        of point: (x: Double, y: Double),
        around center: (x: Double, y: Double)
    ) -> Double {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }

    // MARK: - The ink bounds

    /// The bounding box of an icon's ink: every line endpoint, plus —
    /// for arcs — every axis extreme the swept range crosses. The
    /// rounded corners bulge past their vertices (the play triangle's
    /// nose is pure arc), so the vertex coordinates alone under-measure.
    public static func bounds(of subpaths: [VectorSubpath]) -> VectorBounds? {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity

        func include(_ x: Double, _ y: Double) {
            minX = Swift.min(minX, x)
            minY = Swift.min(minY, y)
            maxX = Swift.max(maxX, x)
            maxY = Swift.max(maxY, y)
        }
        func include(angle degrees: Double, around center: (x: Double, y: Double), radius: Double) {
            let radians = degrees * .pi / 180
            include(center.x + radius * cos(radians), center.y + radius * sin(radians))
        }

        for subpath in subpaths {
            for segment in subpath.segments {
                switch segment {
                case .move(let x, let y), .line(let x, let y):
                    include(x, y)
                case .arc(
                    let centerX, let centerY, let radius,
                    let start, let end, _):
                    include(angle: start, around: (centerX, centerY), radius: radius)
                    include(angle: end, around: (centerX, centerY), radius: radius)
                    let low = Swift.min(start, end)
                    let high = Swift.max(start, end)
                    for cardinal in [0.0, 90, 180, 270] {
                        for shift in [-360.0, 0, 360] where low <= cardinal + shift && cardinal + shift <= high {
                            include(
                                angle: cardinal + shift,
                                around: (centerX, centerY),
                                radius: radius
                            )
                        }
                    }
                case .close:
                    break // the closing line's endpoints are already included
                }
            }
        }
        guard minX.isFinite else { return nil }
        return VectorBounds(minX: minX, minY: minY, width: maxX - minX, height: maxY - minY)
    }
}
