//
//  ArtworkURLTests.swift
//  PandoraCoreTests
//
//  The artwork candidate list is the fix for radio stations whose favicon
//  never loaded: the HTTPS-preferred URL is tried first and the raw URL
//  (scheme preserved) is the last resort, so an HTTP-only favicon host
//  still gets a chance.
//
//  These vectors pin the exact candidate lists — the order matters (the
//  raw URL is only reached when the HTTPS attempt failed) and the
//  scheme of the second candidate must survive untouched.
//

import XCTest
@testable import PandoraCore

final class ArtworkURLTests: XCTestCase {

    // MARK: - The raw-HTTP case (the radio favicon)

    func testHTTPRawURLYieldsHTTPSFirstAndRawHTTPSecond() throws {
        let candidates = ArtworkURLCandidates.candidates(for: "http://example.com/favicon.png")
        XCTAssertEqual(candidates.count, 2)
        let first = try XCTUnwrap(candidates.first)
        let second = try XCTUnwrap(candidates.dropFirst().first)
        XCTAssertEqual(first.absoluteString, "https://example.com/favicon.png")
        XCTAssertEqual(second.absoluteString, "http://example.com/favicon.png")
    }

    func testHTTPRawURLKeepsTheQueryStringOnBothCandidates() throws {
        let candidates = ArtworkURLCandidates.candidates(
            for: "http://example.com/favicon.png?v=2"
        )
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].absoluteString, "https://example.com/favicon.png?v=2")
        XCTAssertEqual(candidates[1].absoluteString, "http://example.com/favicon.png?v=2")
    }

    // MARK: - Already-HTTPS URLs

    func testHTTPSRawURLYieldsASingleCandidate() {
        let candidates = ArtworkURLCandidates.candidates(for: "https://example.com/favicon.png")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.absoluteString, "https://example.com/favicon.png")
    }

    // MARK: - Scheme-less URLs (Pandora's artwork URLs are not always absolute)

    func testSchemelessURLYieldsOneHTTPSCandidate() {
        let candidates = ArtworkURLCandidates.candidates(for: "example.com/favicon.png")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.absoluteString, "https://example.com/favicon.png")
    }

    func testSchemelessURLWithPathOnlyYieldsOneHTTPSCandidate() {
        let candidates = ArtworkURLCandidates.candidates(for: "images.example.com/favicon.png")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.absoluteString, "https://images.example.com/favicon.png")
    }

    // MARK: - Malformed input

    func testSpacesArePercentEncoded() {
        let candidates = ArtworkURLCandidates.candidates(for: "https://example.com/my icon.png")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.absoluteString, "https://example.com/my%20icon.png")
    }

    func testSpacesInAnHTTPRawURLArePercentEncodedOnBothCandidates() {
        let candidates = ArtworkURLCandidates.candidates(for: "http://example.com/my icon.png")
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].absoluteString, "https://example.com/my%20icon.png")
        XCTAssertEqual(candidates[1].absoluteString, "http://example.com/my%20icon.png")
    }

    func testEmptyStringYieldsNoCandidates() {
        XCTAssertTrue(ArtworkURLCandidates.candidates(for: "").isEmpty)
    }

    func testWhitespaceOnlyStringYieldsNoCandidates() {
        XCTAssertTrue(ArtworkURLCandidates.candidates(for: "   \n ").isEmpty)
    }

    func testSurroundingWhitespaceIsTrimmed() {
        let candidates = ArtworkURLCandidates.candidates(for: "  http://example.com/favicon.png  ")
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].absoluteString, "https://example.com/favicon.png")
        XCTAssertEqual(candidates[1].absoluteString, "http://example.com/favicon.png")
    }

    // MARK: - The two halves on their own

    func testHTTPSPreferredURLUpgradesHTTP() throws {
        let url = try XCTUnwrap(
            ArtworkURLCandidates.httpsPreferredURL(from: "http://example.com/favicon.png")
        )
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.absoluteString, "https://example.com/favicon.png")
    }

    func testRawURLPreservesTheHTTPItWasGiven() throws {
        let url = try XCTUnwrap(
            ArtworkURLCandidates.rawURL(from: "http://example.com/favicon.png")
        )
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.absoluteString, "http://example.com/favicon.png")
    }

    func testRawURLIsNilWithoutAScheme() {
        // Nothing to preserve — the scheme-less form is handled by the
        // HTTPS-preferred candidate alone.
        XCTAssertNil(ArtworkURLCandidates.rawURL(from: "example.com/favicon.png"))
    }

    func testRawURLIsNilForAnEmptyString() {
        XCTAssertNil(ArtworkURLCandidates.rawURL(from: ""))
    }
}
