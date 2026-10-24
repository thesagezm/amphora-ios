//
//  PlayerScrubber.swift
//  Amphora
//
//  The full player's scrubber: a capsule progress bar with a drag knob.
//  Custom-drawn instead of `Slider` so the look is Amphora's own — a
//  shape the Android port can mirror exactly — with the knob and fill
//  tinted by the artwork accent. VoiceOver-adjustable (±10 s steps).
//

import SwiftUI

struct PlayerScrubber: View {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @GestureState private var dragFraction: Double?

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    /// What the bar shows: the dragged position while dragging, else
    /// live playback.
    private var displayFraction: Double { dragFraction ?? fraction }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 6)
                Capsule()
                    .fill(accent)
                    .frame(width: max(6, width * displayFraction), height: 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .opacity(dragFraction == nil ? 0 : 1)
                    .offset(x: min(max(width * displayFraction, 8), width - 8) - 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: 28)
        .opacity(duration > 0 ? 1 : 0.35)
        .allowsHitTesting(duration > 0)
        .animation(dragFraction == nil ? .linear(duration: 0.2) : nil, value: displayFraction)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(AmphoraTimeFormat.string(max(0, elapsed)))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            switch direction {
            case .increment: onSeek(min(duration, elapsed + 10))
            case .decrement: onSeek(max(0, elapsed - 10))
            @unknown default: break
            }
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragFraction) { value, state, _ in
                state = min(1, max(0, Double(value.location.x / width)))
            }
            .onEnded { value in
                guard duration > 0 else { return }
                let fraction = min(1, max(0, Double(value.location.x / width)))
                onSeek(fraction * duration)
            }
    }
}
