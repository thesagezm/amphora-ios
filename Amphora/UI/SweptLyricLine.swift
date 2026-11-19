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
//    3. a bright copy revealed as the wavefront crosses.
//
//  Where the wavefront is inside each word is the core's math, not
//  ours: `LyricSweep.wordStates` follows word-exact timings when the
//  provider carries them (rich sync) and otherwise interpolates across
//  the line weighted by word length — the same division the UI's first
//  sweep used, so line-timed songs render exactly as they always did.
//
//  While the wavefront is inside a word, all three copies render
//  per-letter: each letter's progress comes from
//  `LyricSweep.letterProgress`, the bright letter swells
//  `1 + 0.07·sin(π·p)` (a transform-only `scaleEffect` — it rises and
//  settles without any layout ripple), the glow letter's opacity
//  follows the same curve so the glow rides the wavefront like a
//  comet, and the per-letter fade *is* the feather — the word-level
//  gradient mask is gone. The letter stacks are built identically
//  (spacing 0, `.fixedSize()`) so the copies stay aligned; at sung 0
//  or 1 the word falls back to the static three-copy `Text` rendering,
//  so per-frame cost stays bounded to the crossing word's letters.
//
//  Each word's highlight lives in its own bounds, so wrapping never
//  shifts it — the row-aware clipping BitChord needed falls out of the
//  per-word structure here. The sung word lifts 2 pt as it is sung.
//
//  The whole line runs on one `TimelineView`, paused when playback
//  is: per-frame work is the sweeping word's letters alone, and
//  nothing at all while paused.
//

import PandoraCore
import SwiftUI

struct SweptLine: View {
    @Environment(AppStore.self) private var store
    /// The line's text (the accessibility label and the interpolation
    /// fallback's token source).
    let text: String
    /// Word-exact timings when the provider carries them; nil for
    /// line-timed data (the sweep interpolates).
    let words: [LyricWord]?
    /// The sweep window: the line's own timestamp and the next
    /// line's (the caller derives both from the lyrics).
    let start: TimeInterval
    let end: TimeInterval
    let font: Font

    var body: some View {
        TimelineView(.animation(paused: !store.player.isPlaying)) { context in
            let now = LyricClock.elapsed(at: context.date, in: store.player, offset: store.lyricsOffset)
            SweptWords(
                text: text, words: words, start: start, end: end, now: now, font: font
            )
            // The word flow carries the line three times over (dim,
            // glow, bright) — VoiceOver reads the line once.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
        }
    }
}

// MARK: - Word math

/// The flow of words with the sweep states applied per word. The
/// states come from the core's `LyricSweep`, which owns both regimes;
/// the flow renders whatever `WordState.text` says.
private struct SweptWords: View {
    let text: String
    let words: [LyricWord]?
    let start: TimeInterval
    let end: TimeInterval
    let now: TimeInterval
    let font: Font

    private var states: [LyricSweep.WordState] {
        LyricSweep.wordStates(words: words, text: text, at: now, window: start...end)
    }

    var body: some View {
        WordFlow(spacing: 6) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                SweptWord(word: state.text, sung: state.sungFraction, font: font)
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

    /// How far the bright letter swells past its natural size at the
    /// peak of its crossing — transform-only, so layout never moves.
    private static let swell: Double = 0.07
    /// The glow copy's base opacity (the word-level value it always
    /// carried).
    private static let glowOpacity: Double = 0.62

    var body: some View {
        ZStack(alignment: .leading) {
            if sung > 0, sung < 1 {
                // The wavefront is inside the word: all three copies
                // per-letter, identically laid out so they align.
                dimLetters
                glowLetters
                brightLetters
            } else {
                // Static word — today's three-copy Text rendering.
                baseText
                    .foregroundStyle(Color.primary.opacity(0.45))
                if sung >= 1 {
                    baseText
                        .foregroundStyle(Color.primary)
                }
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

    /// The word's letters as grapheme clusters — combining marks and
    /// emoji sequences stay one letter.
    private var letters: [String] {
        word.map(String.init)
    }

    /// Each letter's crossing progress, from the core: letters divide
    /// the word's progress equally, so the swell pops in reading order.
    private func letterProgress(_ index: Int) -> Double {
        LyricSweep.letterProgress(
            wordSung: sung, letterIndex: index, letterCount: letters.count
        )
    }

    /// The unsung remainder, per-letter — same 0.45 dim as the static
    /// copy, in the same stack structure so the copies align.
    private var dimLetters: some View {
        letterStack { letter, _ in
            Text(letter)
                .font(font)
                .fixedSize()
                .foregroundStyle(Color.primary.opacity(0.45))
        }
    }

    /// The glow: one blurred bright copy whose letters ride the
    /// wavefront — opacity follows the swell curve, so the crossing
    /// letter glows hardest and the comet settles as it passes. One
    /// blur on the whole copy, not per letter.
    private var glowLetters: some View {
        letterStack { letter, index in
            Text(letter)
                .font(font)
                .fixedSize()
                .foregroundStyle(Color.primary)
                .opacity(Self.glowOpacity * sin(.pi * letterProgress(index)))
        }
        .blur(radius: 5)
        .allowsHitTesting(false)
    }

    /// The bright copy, revealed letter by letter — the letter
    /// granularity *is* the feather — with the crossing letter swelled
    /// `1 + 0.07·sin(π·p)`, a transform-only scale.
    private var brightLetters: some View {
        letterStack { letter, index in
            let progress = letterProgress(index)
            Text(letter)
                .font(font)
                .fixedSize()
                .foregroundStyle(Color.primary)
                .opacity(progress)
                .scaleEffect(1 + Self.swell * sin(.pi * progress))
        }
    }

    /// The identical letter layout all three copies share: spacing 0,
    /// every letter fixed to its ideal width — identical structure, so
    /// the stacked copies stay aligned.
    private func letterStack(
        @ViewBuilder content: @escaping (String, Int) -> some View
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                content(letter, index)
            }
        }
    }
}

// MARK: - The flow

/// A word-wrapping flow layout — the one piece of layout machinery the
/// sweep needs, since a word must be able to break to the next visual
/// row while its highlight stays inside its own bounds. Positions
/// respect the layout direction, so right-to-left scripts flow
/// correctly.
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
