//
//  ArtworkColorsTests.swift
//  PandoraCoreTests
//
//  Palette extraction from synthetic RGBA8 pixels: solid colors, dominant
//  hue election, grayscale rejection, the fixed accent/background clamps,
//  and HSV round-trips. The same algorithm runs on every Amphora port, so
//  these vectors pin the derived values exactly.
//

import XCTest
@testable import PandoraCore

final class ArtworkColorsTests: XCTestCase {

    /// A solid RGBA8 image of one color.
    private func solidPixels(
        _ red: UInt8, _ green: UInt8, _ blue: UInt8,
        width: Int = 8, height: Int = 8
    ) -> [UInt8] {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            pixels.append(contentsOf: [red, green, blue, 255])
        }
        return pixels
    }

    func testExtractsSolidColorAsDominant() throws {
        let colors = try XCTUnwrap(
            ArtworkColors.extract(fromRGBA8: solidPixels(220, 40, 40), width: 8, height: 8)
        )
        // Weighted average of identical pixels is the pixel itself.
        XCTAssertEqual(colors.dominant.red, 220.0 / 255, accuracy: 0.001)
        XCTAssertEqual(colors.dominant.green, 40.0 / 255, accuracy: 0.001)
        XCTAssertEqual(colors.dominant.blue, 40.0 / 255, accuracy: 0.001)
    }

    func testDominantHueWinsOverScatteredOtherColors() throws {
        // 60 of 64 pixels green, 4 red: the green bucket must win even
        // though red is more saturated per pixel.
        var pixels = solidPixels(30, 200, 60)
        for i in 0..<4 {
            pixels[i * 4] = 220
            pixels[i * 4 + 1] = 20
            pixels[i * 4 + 2] = 20
        }
        let colors = try XCTUnwrap(
            ArtworkColors.extract(fromRGBA8: pixels, width: 8, height: 8)
        )
        XCTAssertGreaterThan(colors.dominant.green, colors.dominant.red)
        XCTAssertGreaterThan(colors.dominant.green, colors.dominant.blue)
    }

    func testGrayscaleImageReturnsNil() {
        XCTAssertNil(
            ArtworkColors.extract(fromRGBA8: solidPixels(128, 128, 128), width: 8, height: 8)
        )
    }

    func testNearBlackImageReturnsNil() {
        XCTAssertNil(
            ArtworkColors.extract(fromRGBA8: solidPixels(10, 12, 14), width: 8, height: 8)
        )
    }

    func testTinyColoredLogoDoesNotTheme() {
        // 4 colored pixels out of 1024 is below the chromatic threshold.
        var pixels = solidPixels(20, 20, 24)
        for i in 0..<4 {
            pixels[i * 4] = 230
            pixels[i * 4 + 1] = 30
            pixels[i * 4 + 2] = 30
        }
        XCTAssertNil(
            ArtworkColors.extract(fromRGBA8: pixels, width: 32, height: 32)
        )
    }

    func testRejectsUnusableInput() {
        XCTAssertNil(ArtworkColors.extract(fromRGBA8: [], width: 0, height: 0))
        XCTAssertNil(ArtworkColors.extract(fromRGBA8: [0, 0, 0, 255], width: 2, height: 2))
    }

    func testAccentIsMidBrightnessAndSaturated() throws {
        // A dark muted blue cover: the accent must be lifted into the
        // fixed clamp window, not stay murky.
        let colors = try XCTUnwrap(
            ArtworkColors.extract(fromRGBA8: solidPixels(30, 40, 90), width: 8, height: 8)
        )
        let (h, s, v) = ArtworkColors.rgbToHSV(
            colors.accent.red, colors.accent.green, colors.accent.blue
        )
        XCTAssertEqual(h, ArtworkColors.rgbToHSV(30.0 / 255, 40.0 / 255, 90.0 / 255).hue,
                       accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(s, 0.45)
        XCTAssertGreaterThanOrEqual(v, 0.55)
        XCTAssertLessThanOrEqual(v, 0.80)
    }

    func testAccentCapsNeonDominants() throws {
        let colors = try XCTUnwrap(
            ArtworkColors.extract(fromRGBA8: solidPixels(255, 0, 255), width: 8, height: 8)
        )
        let (_, _, v) = ArtworkColors.rgbToHSV(
            colors.accent.red, colors.accent.green, colors.accent.blue
        )
        XCTAssertLessThanOrEqual(v, 0.80)
    }

    func testBackgroundsAreDarkerThanDominant() throws {
        let colors = try XCTUnwrap(
            ArtworkColors.extract(fromRGBA8: solidPixels(200, 120, 40), width: 8, height: 8)
        )
        let dominantV = ArtworkColors.rgbToHSV(
            colors.dominant.red, colors.dominant.green, colors.dominant.blue
        ).value
        let topV = ArtworkColors.rgbToHSV(
            colors.backgroundTop.red, colors.backgroundTop.green, colors.backgroundTop.blue
        ).value
        let bottomV = ArtworkColors.rgbToHSV(
            colors.backgroundBottom.red, colors.backgroundBottom.green, colors.backgroundBottom.blue
        ).value
        XCTAssertLessThan(topV, dominantV)
        XCTAssertLessThan(bottomV, topV)
        XCTAssertGreaterThanOrEqual(bottomV, 0.04)
    }

    func testBrandPaletteIsComplete() {
        XCTAssertEqual(ArtworkColors.brand.dominant.red, 0.424, accuracy: 0.001)
        XCTAssertEqual(ArtworkColors.brand.accent.green, 0.698, accuracy: 0.001)
        let bottom = ArtworkColors.brand.backgroundBottom
        XCTAssertLessThan(
            ArtworkColors.rgbToHSV(bottom.red, bottom.green, bottom.blue).value, 0.1
        )
    }

    func testHSVRoundTrip() {
        // hsv→rgb→hsv must be the identity away from the gray axis.
        for step in 0..<12 {
            let hue = Double(step) / 12
            let rgb = ArtworkColors.hsvToColor(hue, 0.7, 0.6)
            let back = ArtworkColors.rgbToHSV(rgb.red, rgb.green, rgb.blue)
            XCTAssertEqual(back.hue, hue, accuracy: 0.001)
            XCTAssertEqual(back.saturation, 0.7, accuracy: 0.001)
            XCTAssertEqual(back.value, 0.6, accuracy: 0.001)
        }
    }

    func testRGBToHSVHandlesAxisColors() {
        XCTAssertEqual(ArtworkColors.rgbToHSV(0, 0, 0).value, 0)
        XCTAssertEqual(ArtworkColors.rgbToHSV(1, 1, 1).saturation, 0)
        XCTAssertEqual(ArtworkColors.rgbToHSV(1, 0, 0).hue, 0, accuracy: 0.001)
        XCTAssertEqual(ArtworkColors.rgbToHSV(1, 0, 0.5).hue, 11.0 / 12, accuracy: 0.01)
    }
}
