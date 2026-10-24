//
//  TimeFormat.swift
//  Amphora
//
//  `m:ss` (or `h:mm:ss` for long tracks) — shared by the player's
//  scrubber labels and progress surfaces.
//

import Foundation

enum AmphoraTimeFormat {
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
