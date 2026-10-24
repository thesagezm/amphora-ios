//
//  Haptics.swift
//  Amphora
//
//  Lightweight haptics for the design spec's "haptics on rating/skip"
//  (and play/pause, bookmarks). Callers are SwiftUI views on the main
//  actor; generators are created per call — cheap, and avoids keeping
//  one alive across the app for a handful of taps a minute.
//

import UIKit

@MainActor
enum Haptics {
    /// Small taps: play/pause, bookmarks, ratings.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Confirmed actions: skipping a track.
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
