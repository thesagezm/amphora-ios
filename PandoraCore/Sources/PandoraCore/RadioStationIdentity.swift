//
//  RadioStationIdentity.swift
//  PandoraCore
//
//  The identity behind the generated radio-station artwork.
//
//  Plenty of internet-radio stations have no favicon at all, and the
//  ones that have one usually serve a 16×16 pixel icon — blown up to
//  full-player size that reads as "no artwork" (or worse, as a blurry
//  smudge). The fallback is a generated tile: the station's initials on
//  a deterministic gradient.
//
//  "Deterministic" is the important word: the same station must get
//  the same color on every launch and on every device. Swift's
//  `hashValue` is seeded per process, so it cannot be used here — the
//  name is hashed with FNV-1a instead, which is a fixed algorithm over
//  the UTF-8 bytes.
//
//  Pure Foundation, no UI — the app target turns the hue into colors;
//  the Android port mirrors the same numbers.
//

import Foundation

/// The generated identity of a radio station: its monogram and its hue.
public enum RadioStationIdentity {

    /// The monogram shown on the generated tile — the first letter of
    /// up to two words of the station name, uppercased.
    ///
    /// "Radio Paradise" → "RP", "KEXP" → "K". An empty name falls back
    /// to "R" (radio) so the tile is never blank.
    public static func initials(for name: String) -> String {
        let words = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return "R" }

        let letters = words.prefix(2).compactMap { word -> Character? in
            word.first
        }
        guard !letters.isEmpty else { return "R" }
        return String(letters).uppercased()
    }

    /// The station's hue in the 0...1 range, derived from its name.
    ///
    /// The same name always yields the same hue — on every launch, on
    /// every device, on every port of the app.
    public static func hue(for name: String) -> Double {
        let hash = fnv1a(name)
        // 3600 steps → a tenth of a degree, so neighbouring names land
        // on visibly different hues.
        return Double(hash % 3600) / 3600.0
    }

    /// The FNV-1a hash (32 bit) of a name, over its UTF-8 bytes.
    /// Lowercased first, so "KEXP" and "kexp" share one color.
    public static func fnv1a(_ name: String) -> UInt32 {
        var hash: UInt32 = 0x811c9dc5
        for byte in name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }
}
