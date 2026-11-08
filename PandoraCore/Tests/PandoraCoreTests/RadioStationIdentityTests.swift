//
//  RadioStationIdentityTests.swift
//  PandoraCoreTests
//
//  The generated radio-station artwork: the monogram and the hue that
//  comes with it. The hue must be stable across launches (Swift's
//  `hashValue` is seeded per process and would change colors on every
//  launch), so the hash is pinned by these vectors.
//

import XCTest
@testable import PandoraCore

final class RadioStationIdentityTests: XCTestCase {

    // MARK: - Initials

    func testInitialsUseTheFirstLetterOfTwoWords() {
        XCTAssertEqual(RadioStationIdentity.initials(for: "Radio Paradise"), "RP")
    }

    func testInitialsUseOneLetterForASingleWord() {
        XCTAssertEqual(RadioStationIdentity.initials(for: "KEXP"), "K")
    }

    func testInitialsIgnoreSurroundingAndRepeatedWhitespace() {
        XCTAssertEqual(RadioStationIdentity.initials(for: "  Radio   Paradise  "), "RP")
    }

    func testInitialsFallBackToRForAnEmptyName() {
        XCTAssertEqual(RadioStationIdentity.initials(for: ""), "R")
        XCTAssertEqual(RadioStationIdentity.initials(for: "   "), "R")
    }

    func testInitialsKeepNonLatinLetters() {
        // The first letter is taken as a whole character, not a byte.
        XCTAssertEqual(RadioStationIdentity.initials(for: "Радио Рекорд"), "РР")
    }

    // MARK: - Hue

    func testHueIsInTheUnitRange() {
        for name in ["Radio Paradise", "KEXP", "BBC Radio 4", "Éire FM", ""] {
            let hue = RadioStationIdentity.hue(for: name)
            XCTAssertGreaterThanOrEqual(hue, 0)
            XCTAssertLessThan(hue, 1)
        }
    }

    func testHueIsStableForTheSameName() {
        // The same station must not change color between launches — the
        // whole point of hashing the name instead of using `hashValue`.
        XCTAssertEqual(
            RadioStationIdentity.hue(for: "Radio Paradise"),
            RadioStationIdentity.hue(for: "Radio Paradise")
        )
    }

    func testHueIgnoresCaseAndSurroundingWhitespace() {
        XCTAssertEqual(
            RadioStationIdentity.hue(for: "Radio Paradise"),
            RadioStationIdentity.hue(for: "  radio paradise  ")
        )
    }

    func testDifferentNamesGetDifferentHues() {
        XCTAssertNotEqual(
            RadioStationIdentity.hue(for: "Radio Paradise"),
            RadioStationIdentity.hue(for: "Radio Skywave")
        )
    }

    func testHashIsTheKnownFNV1aValue() {
        // FNV-1a over the UTF-8 bytes, lowercased first. Pinned so a
        // change in the hashing algorithm (which would recolor every
        // station on every device) cannot slip through.
        XCTAssertEqual(RadioStationIdentity.fnv1a("kexp"), 0xfc4c_4c1d)
    }
}
