//
//  SweptLyricLine.swift
//  Amphora
//
//  BitChord's swept lyric line, SwiftUI-adapted and wrap-safe. The
//  line is a flow of words; each word carries the three-copy
//  treatment:
//
//    1. a dim copy — the unsung remainder,
//    2. a blurred glow copy, alive only while the wavefront crosses
//       the word (BitChord restricts its glow to held words the same
//       way),
//    3. a bright copy masked to the word's sung fraction behind a
//       feathered wipe — the highlight reads as a wavefront, never a
//       hard cut.
//
//  Word boundaries are interpolated across the line's window
//  (line-timed data has no word timings), weighted by word length so
//  longer words hold the wavefront longer. Each word's mask lives in
//  its own bounds, so wrapping never shifts the highlight — the
//  row-aware clipping BitChord needed falls out of the per-word
//  structure here. The sung word lifts 2 pt as it is sung.
//
//  The whole line runs on one `TimelineView`, paused when playback
//  is: per-frame work is the sweeping word's mask alone, and nothing
//  at all while paused.
//

import PandoraCore
import SwiftUI

struct SweptLine: View {
    @Environment(AppStore.self) private var store
    /// The line's words.
    let text: String
    /// The sweep window: the line's own timestamp and the next
    /// line's (the caller derives both from the lyrics).
    let start: TimeInterval
    let end: TimeInterval
    let font: Font

    var body: some View {
        TimelineView(.animation(paused: !store.player.isPlaying)) { context in
            let now = LyricClock.elapsed(at: context.date, in: store.player)
            SweptWords(text: text, start: start, end: end, now: now, font: font)
                // The word flow carries the line three times over (dim,
                // glow, bright) — VoiceOver reads the line once.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        }
    }
}

// MARK: - Word math

/// The flow of words with the sweep math applied per word.
private struct SweptWords: View {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let now: TimeInterval
    let font: Font

    /// The sweep's clock position as a fraction of the line window.
    private var progress: Double {
        min(max((now - start) / max(end - start, 0.3), 0), 1)
    }

    private var words: [(offset: Int, word: String)] {
        Array(text.split(separator: " ", omittingEmptySubsequences: false)
            .enumerated().map { ($0.offset, String($0.element)) })
    }

    /// The sung fraction at which word `index` begins, weighted by
    /// character counts (longer words own more of the window).
    private func boundary(_ index: Int) -> Double {
        let weights = words.map { Double(max($0.word.count, 1)) }
        let total = max(weights.reduce(0, +), 1)
        let before = weights.prefix(index).reduce(0, +)
        return before / total
    }

    var body: some View {
        WordFlow(spacing: 6) {
            ForEach(words, id: \.offset) { index, word in
                let wordStart = boundary(index)
                let wordEnd = boundary(index + 1)
                let local = min(
                    max((progress - wordStart) / max(wordEnd - wordStart, 0.001), 0),
                    1
                )
                SweptWord(
                    word: word.isEmpty ? " " : word,
                    sung: local,
                    font: font
                )
            }
        }
    }
}

// MARK: - One word, three copies

private struct SweptWord: View {
    let word: String
    /// The word's own sweep progress, 0...1.
    let sung: Double
    let font: Font

    /// BitChord's word rise, eased in as the wavefront passes.
    private var rise: CGFloat {
        CGFloat(-2 * min(sung * 3, 1))
    }

    /// The feather the wipe trails behind the wavefront, as a fraction
    /// of the word — roughly the 1.5 characters BitChord feathers.
    private static let feather: Double = 0.3

    var body: some View {
        ZStack(alignment: .leading) {
            // The unsung remainder — what the wavefront has not
            // reached yet.
            baseText
                .foregroundStyle(Color.primary.opacity(0.45))
            if sung > 0, sung < 1 {
                // The glow: a blurred bright copy, masked to the sung
                // fraction, alive only while the wavefront is here.
                baseText
                    .foregroundStyle(Color.primary)
                    .blur(radius: 5)
                    .mask(sungMaskView)
                    .opacity(0.62)
                    .allowsHitTesting(false)
            }
            if sung >= 1 {
                baseText
                    .foregroundStyle(Color.primary)
            } else if sung > 0 {
                baseText
                    .foregroundStyle(Color.primary)
                    .mask(sungMaskView)
            }
        }
        .offset(y: rise)
        .animation(.spring(duration: 0.3, bounce: 0.25), value: rise)
    }

    private var baseText: some View {
        Text(word)
            .font(font)
            .fixedSize()
    }

    /// The feathered wipe mask, in the word's own bounds — full white
    /// behind the wavefront, a ramp over the feather width, clear
    /// ahead of it.
    private var sungMaskView: some View {
        let leading = max(0, sung - Self.feather)
        return LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: leading),
                .init(color: .clear, location: sung),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - The flow

/// A word-wrapping flow layout — the one piece of layout machinery the
/// sweep needs, since a word must be able to break to the next visual
/// row while its mask stays inside its own bounds. Positions respect
/// the layout direction, so right-to-left scripts flow correctly.
struct WordFlow: Layout {
    var spacing: CGFloat = 6
    @Environment(\.layoutDirection) private var layoutDirection

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let isRTL = layoutDirection == .rightToLeft
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            let leading = isRTL ? bounds.maxX - x - size.width : bounds.minX + x
            subview.place(
                at: CGPoint(x: leading, y: bounds.minY + y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
