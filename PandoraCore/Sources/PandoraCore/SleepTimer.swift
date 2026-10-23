//
//  SleepTimer.swift
//  PandoraCore
//
//  The sleep timer (AGENTS.md feature set: "Sleep timer").
//
//  Pure logic, no timers of its own: the caller supplies the current
//  time and the timer reports when the deadline has passed. Two modes
//  match what music apps do:
///
///  - `duration` — stop after N minutes.
///  - `endOfTrack` — stop when the current track finishes (the caller
///    fires `fire()` when the track ends).
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

/// A sleep timer with an optional deadline.
public struct SleepTimer: Codable, Sendable, Equatable {

    /// How the timer ends.
    public enum Mode: String, Codable, Sendable {
        /// No timer is set.
        case off
        /// Stop after a fixed number of minutes.
        case duration
        /// Stop when the current track ends.
        case endOfTrack
    }

    /// The timer is off (no deadline set).
    public static let off = SleepTimer()

    public let mode: Mode
    /// When the timer fires (epoch seconds). Nil for `endOfTrack` until
    /// the track actually ends.
    public let deadline: Date?
    /// Minutes requested by the user (0 when the timer is off).
    public let minutes: Int

    private init(mode: Mode = .off, deadline: Date? = nil, minutes: Int = 0) {
        self.mode = mode
        self.deadline = deadline
        self.minutes = minutes
    }

    /// A timer that stops after `minutes` minutes from `now`.
    public init(minutes: Int, now: Date = Date()) {
        let clamped = max(1, minutes)
        self.mode = .duration
        self.deadline = now.addingTimeInterval(TimeInterval(clamped * 60))
        self.minutes = clamped
    }

    /// A timer that stops when the current track ends.
    public init(endOfTrack: Bool) {
        self.mode = .endOfTrack
        self.deadline = nil
        self.minutes = 0
    }

    /// `true` when no timer is set.
    public var isOff: Bool { mode == .off }

    /// `true` when the deadline has passed (duration mode).
    public func hasExpired(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// Seconds left before the deadline (0 when off or expired).
    public func remaining(now: Date = Date()) -> TimeInterval {
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// The timer as it should be after the current track ended: a
    /// duration timer has expired, an end-of-track timer is done.
    public func fired() -> SleepTimer {
        .off
    }

    /// A short label for the UI ("12 min left", "End of track", "Off").
    public func label(now: Date = Date()) -> String {
        switch mode {
        case .off:
            return "Off"
        case .endOfTrack:
            return "End of track"
        case .duration:
            guard let deadline else { return "Off" }
            let remaining = max(0, deadline.timeIntervalSince(now))
            let totalMinutes = Int((remaining / 60).rounded(.up))
            if totalMinutes <= 0 { return "Off" }
            return "\(totalMinutes) min left"
        }
    }
}
