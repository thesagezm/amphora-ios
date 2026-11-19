//
//  TransportIconPathsTests.swift
//  PandoraCoreTests
//
//  The playback-control icon geometry, copied from BitChord's transport
//  drawables. These vectors pin the interpreter (subpath structure, arc
//  centers) and the derived ink bounds — the bounds are computed
//  independently (arc bulges past vertices included) and are what the
//  renderer fits to a frame, so a wrong derivation would visibly
//  mis-size every transport glyph.
//

import XCTest
@testable import PandoraCore

final class TransportIconPathsTests: XCTestCase {

    // MARK: - The copied drawables parse into the expected shapes

    func testPlayParsesToOneSubpathOfEightSegments() {
        let icon = TransportIconPaths.icon(TransportIconPaths.playData)
        XCTAssertEqual(icon.subpaths.count, 1)
        XCTAssertEqual(icon.subpaths[0].segments.count, 8) // M, L, A, L, A, L, A, close
    }

    func testPauseParsesToTwoSubpaths() {
        let icon = TransportIconPaths.icon(TransportIconPaths.pauseData)
        XCTAssertEqual(icon.subpaths.count, 2)
        XCTAssertEqual(icon.subpaths.map { $0.segments.count }, [10, 10])
    }

    func testNextAndPreviousParseToTwoSubpathsEach() {
        for data in [TransportIconPaths.nextData, TransportIconPaths.previousData] {
            let icon = TransportIconPaths.icon(data)
            XCTAssertEqual(icon.subpaths.count, 2)
            XCTAssertEqual(icon.subpaths.map { $0.segments.count }, [8, 8])
        }
    }

    func testEveryArcRadiusIsTheDrawablesFiftySixOrForty() {
        for data in [
            TransportIconPaths.playData,
            TransportIconPaths.pauseData,
            TransportIconPaths.nextData,
            TransportIconPaths.previousData,
            TransportIconPaths.stopData
        ] {
            let icon = TransportIconPaths.icon(data)
            for subpath in icon.subpaths {
                for segment in subpath.segments {
                    if case .arc(_, _, let radius, _, _, _) = segment {
                        XCTAssertTrue(radius == 56 || radius == 40)
                    }
                }
            }
        }
    }

    // MARK: - The derived arc (a known-answer vector)

    func testPlayApexArcCentersOnTheComputedCircle() {
        let icon = TransportIconPaths.icon(TransportIconPaths.playData)
        guard case .arc(let centerX, let centerY, let radius, let start, let end, let clockwise) =
            icon.subpaths[0].segments[2] // M, L, then the apex arc
        else {
            return XCTFail("the third segment should be the apex arc")
        }
        // Chord from (699.6, 433.1) to (699.6, 526.9), r 56, sweep 1:
        // the center sits 30.60 units left of the chord's midpoint, and
        // the arc sweeps clockwise on screen through 0° — the bulge that
        // is the triangle's nose.
        XCTAssertEqual(centerX, 668.9995, accuracy: 0.001)
        XCTAssertEqual(centerY, 480.0, accuracy: 0.001)
        XCTAssertEqual(radius, 56, accuracy: 0.001)
        XCTAssertEqual(start, -56.8771, accuracy: 0.001)
        XCTAssertEqual(end, 56.8771, accuracy: 0.001)
        XCTAssertTrue(clockwise)
    }

    // MARK: - The ink bounds (computed independently, arc bulges in)

    func testPlayBounds() throws {
        let icon = TransportIconPaths.icon(TransportIconPaths.playData)
        let bounds = try XCTUnwrap(icon.bounds)
        XCTAssertEqual(bounds.minX, 320.0, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 232.9, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 405.0, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 494.2, accuracy: 0.01)
    }

    func testPauseBounds() throws {
        let icon = TransportIconPaths.icon(TransportIconPaths.pauseData)
        let bounds = try XCTUnwrap(icon.bounds)
        XCTAssertEqual(bounds.minX, 285.0, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 240.0, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 390.0, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 480.0, accuracy: 0.01)
    }

    func testNextBounds() throws {
        let icon = TransportIconPaths.icon(TransportIconPaths.nextData)
        let bounds = try XCTUnwrap(icon.bounds)
        XCTAssertEqual(bounds.minX, 55.9, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 197.43, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 848.89, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 565.13, accuracy: 0.01)
    }

    func testPreviousBounds() throws {
        let icon = TransportIconPaths.icon(TransportIconPaths.previousData)
        let bounds = try XCTUnwrap(icon.bounds)
        XCTAssertEqual(bounds.minX, 57.21, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 197.5, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 845.49, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 564.99, accuracy: 0.01)
    }

    func testStopBounds() throws {
        let icon = TransportIconPaths.icon(TransportIconPaths.stopData)
        let bounds = try XCTUnwrap(icon.bounds)
        XCTAssertEqual(bounds.minX, 240.0, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 240.0, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 480.0, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 480.0, accuracy: 0.01)
    }

    // MARK: - Malformed and unsupported data

    func testEmptyDataYieldsAnEmptyIcon() {
        let icon = TransportIconPaths.icon("")
        XCTAssertTrue(icon.subpaths.isEmpty)
        XCTAssertNil(icon.bounds)
    }

    func testUnknownCommandsRejectTheData() {
        // Q (a quadratic curve) is outside the supported subset.
        XCTAssertTrue(TransportIconPaths.icon("M10,10 Q5,5 0,0").subpaths.isEmpty)
        // Lowercase letters are relative commands — not supported.
        XCTAssertTrue(TransportIconPaths.icon("m10,10 l5,5").subpaths.isEmpty)
    }

    func testTruncatedParametersRejectTheData() {
        XCTAssertTrue(TransportIconPaths.icon("M10,10 L20").subpaths.isEmpty)
        XCTAssertTrue(TransportIconPaths.icon("M10,10 A56,56 0 0").subpaths.isEmpty)
    }

    func testEllipticalArcsRejectTheData() {
        // rx ≠ ry
        XCTAssertTrue(TransportIconPaths.icon("M0,0 A56,40 0 0 1 10,10").subpaths.isEmpty)
        // A non-zero axis rotation.
        XCTAssertTrue(TransportIconPaths.icon("M0,0 A56,56 45 0 1 10,10").subpaths.isEmpty)
    }

    func testAnOversizedChordScalesTheRadiusUp() throws {
        // SVG scales a too-small radius up to the chord's half: the arc
        // from (0,0) to (100,0) with r 1 becomes a semicircle of r 50.
        let icon = TransportIconPaths.icon("M0,0 A1,1 0 0 1 100,0")
        XCTAssertEqual(icon.subpaths.count, 1)
        let arc = try XCTUnwrap(icon.subpaths.first?.segments.first { if case .arc = $0 { return true }; return false })
        guard case .arc(let centerX, let centerY, let radius, _, _, _) = arc else {
            return XCTFail("the segment should be an arc")
        }
        XCTAssertEqual(centerX, 50, accuracy: 0.001)
        XCTAssertEqual(centerY, 0, accuracy: 0.001)
        XCTAssertEqual(radius, 50, accuracy: 0.001)
    }
}
