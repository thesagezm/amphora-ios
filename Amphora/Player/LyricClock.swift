//
//  LyricClock.swift
//  Amphora
//
//  The interpolated playhead the lyrics ride. `elapsed` advances in
//  0.5 s steps (the periodic time observer); BitChord's LyricClock
//  spreads each step across the frames between readings, so the
//  lyrics' scroll lead and its sweep move continuously instead of
//  jumping half a second at a time.
//
//  Interpolation is only sound while playing — paused, the last
//  reading is frozen — and every `elapsed` write stamps
//  `elapsedSampledAt`, so seeks and resets never leave the clock
//  extrapolating from a stale reading.
//

import Foundation

/// Main-actor by construction: it reads the player's position state,
/// and every caller (the lyrics' timeline views) runs on the main
/// actor anyway.
@MainActor
enum LyricClock {
    /// The display position at wall-clock `date`: the last reading
    /// plus the time since it was taken, frozen while paused.
    static func elapsed(at date: Date, in player: PlayerService) -> TimeInterval {
        guard player.isPlaying, player.elapsedSampledAt > 0 else {
            return player.elapsed
        }
        let drift = date.timeIntervalSinceReferenceDate - player.elapsedSampledAt
        // A reading much older than the observer interval means the
        // app was suspended or playback stalled — hold the position
        // rather than racing ahead of the audio.
        return player.elapsed + min(max(drift, 0), 1.0)
    }
}
