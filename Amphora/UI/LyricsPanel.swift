//
//  LyricsPanel.swift
//  Amphora
//
//  Lyrics in the full player — BitChord's scroll engine, adapted:
//  synchronised lines scroll ahead of playback on an interpolated
//  clock (the `LyricClock` spreads the 0.5 s position readings across
//  frames), the highlight follows the sung line precisely, long
//  instrumental gaps draw filling dots, and the reader can drag
//  anywhere without the panel yanking back — it resumes to the live
//  line after five idle seconds. Plain lyrics scroll freely; loading
//  shows a skeleton; the unavailable case offers a retry. All state
//  comes from `AppStore` — the view holds no fetching or business
//  logic.
//

import PandoraCore
import SwiftUI

struct LyricsPanel: View {
    @Environment(AppStore.self) private var store

    /// Reported on every user interaction (drag, tap, seek) so the
    /// player can hold its controls visible while the reader is
    /// engaged. nil when nobody listens (tests, previews).
    var onUserInteraction: (() -> Void)?

    /// The shared ambient theme — the romanization line is tinted with
    /// the artwork accent, like the player's other accent surfaces.
    private var theme: ArtworkThemeController { ArtworkThemeController.shared }

    /// BitChord's run-up: the panel scrolls to the line that will sing
    /// within this window, so the scroll lands as the line begins
    /// instead of chasing it.
    private static let scrollLead: TimeInterval = 0.45
    /// BitChord's settle: the run-up eases in over 400 ms on the same
    /// curve their scroll engine uses.
    private static let scrollAnimation = Animation.timingCurve(
        0.41, 0, 0.12, 0.99, duration: 0.4
    )
    /// Drag-to-browse resumes to the live line after this much idle.
    private static let browseResumeAfter: Duration = .seconds(5)

    @State private var highlightIndex: Int?
    @State private var isBrowsing = false
    /// The owned resume task — cancelled and replaced on every drag,
    /// cancelled when the panel goes away.
    @State private var browseResumeTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let lyrics = store.lyrics, !lyrics.isEmpty {
                VStack(spacing: 0) {
                    translationBar
                    content(for: lyrics)
                }
            } else if store.isLoadingLyrics {
                skeleton
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            browseResumeTask?.cancel()
            browseResumeTask = nil
        }
    }

    /// The translate control: a **Translate** button while there is
    /// something to translate, a "Translating…" state while the request
    /// is in flight, and the result once it is known — translated,
    /// already English, or failed (with a retry).
    private var translationBar: some View {
        HStack(spacing: 12) {
            translationStatus
            Spacer(minLength: 0)
            translateButton
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var translationStatus: some View {
        switch store.lyricsTranslationState {
        case .none:
            EmptyView()
        case .translating:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Translating…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .translated:
            Label("Translated", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.colors.accent.color)
        case .alreadyEnglish:
            Label("Already in English", systemImage: "character.bubble")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private var translateButton: some View {
        switch store.lyricsTranslationState {
        case .none, .failed:
            Button {
                Haptics.light()
                noteInteraction()
                store.send(.translateLyrics)
            } label: {
                Label(
                    store.lyricsTranslationState == .none ? "Translate" : "Retry",
                    systemImage: "character.bubble"
                )
            }
            .buttonStyle(.bordered)
            .tint(theme.colors.accent.color)
            .accessibilityLabel("Translate the lyrics into English")
        case .translating, .translated, .alreadyEnglish:
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(for lyrics: Lyrics) -> some View {
        if lyrics.isSynced {
            syncedLyrics(lyrics)
        } else if let plain = lyrics.plainText, !plain.isEmpty {
            plainLyrics(plain, translation: lyrics.plainTranslation)
        } else if lyrics.instrumental {
            ContentUnavailableView(
                "Instrumental",
                systemImage: "music.note",
                description: Text("This track has no words.")
            )
        } else {
            unavailable
        }
    }

    // MARK: - Synchronised lyrics

    /// The scroll engine. The rows live *outside* the per-frame clock:
    /// a zero-size trigger view inside its own `TimelineView` observes
    /// the interpolated playhead and drives both the highlight (per
    /// line) and the run-up scroll (450 ms before each line), so the
    /// per-frame evaluation never re-diffs the row list.
    private func syncedLyrics(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .topLeading) {
                rows(for: lyrics, highlightIndex: highlightIndex)
                TimelineView(.animation) { context in
                    let clock = LyricClock.elapsed(at: context.date, in: store.player)
                    let live = lyrics.activeLineIndex(at: clock)
                    let lead = lyrics.activeLineIndex(at: clock + Self.scrollLead)
                    Color.clear
                        .frame(width: 0, height: 0)
                        .onChange(of: live) { _, index in
                            highlightIndex = index
                        }
                        .onChange(of: lead) { _, index in
                            guard !isBrowsing else { return }
                            scrollTo(index, in: lyrics, proxy: proxy)
                        }
                        .onAppear {
                            highlightIndex = live
                            // Arriving mid-track: land on the live line.
                            if let index = live {
                                proxy.scrollTo(lyrics.lines[index].id, anchor: .center)
                            }
                        }
                }
            }
            .id(lyrics)
            // Drag-to-browse: the auto-scroll stands down while the
            // reader is in control and resumes after the idle window.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in beginBrowsing(lyrics: lyrics, proxy: proxy) }
                    .onEnded { _ in beginBrowsing(lyrics: lyrics, proxy: proxy) }
            )
            // Any tap holds the controls visible for the reader.
            .simultaneousGesture(TapGesture().onEnded { noteInteraction() })
        }
    }

    private func rows(for lyrics: Lyrics, highlightIndex: Int?) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(lyricElements(lyrics)) { element in
                    switch element {
                    case .line(let index):
                        lineRow(lyrics.lines[index], isActive: index == highlightIndex)
                    case .gap(let start, let end):
                        GapDotsRow(start: start, end: end)
                            .id("gap-\(start)-\(end)")
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 100)
        }
        .scrollIndicators(.hidden)
    }

    /// The active line is highlighted and kept centred; tapping a line
    /// seeks to its start. (The sweep rendering arrives with L2 — the
    /// highlight is line-accurate already.)
    private func lineRow(_ line: LyricLine, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let romanization = line.romanization, !romanization.isEmpty {
                // Non-Latin-script lyrics: the original script stays as
                // a reference line, the romanization is the reading
                // line the user sings along with (accent-tinted), and
                // the English translation sits beneath both.
                Text(line.text)
                    .font(.subheadline)
                    .foregroundStyle(
                        isActive ? Color.secondary : Color.secondary.opacity(0.6)
                    )
                Text(romanization)
                    .font(.title3.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(
                        isActive
                            ? theme.colors.accent.color
                            : theme.colors.accent.color.opacity(0.7)
                    )
                if let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(
                            isActive ? Color.secondary : Color.secondary.opacity(0.6)
                        )
                }
            } else {
                Text(line.text)
                    .font(.title3.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                if let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(
                            isActive ? Color.secondary : Color.secondary.opacity(0.6)
                        )
                }
            }
        }
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            noteInteraction()
            isBrowsing = false
            browseResumeTask?.cancel()
            store.player.seek(to: line.timestamp)
        }
        .accessibilityHint("Double-tap to jump here")
    }

    private func scrollTo(
        _ index: Int?, in lyrics: Lyrics, proxy: ScrollViewProxy
    ) {
        guard !isBrowsing, let index, lyrics.lines.indices.contains(index) else { return }
        withAnimation(Self.scrollAnimation) {
            proxy.scrollTo(lyrics.lines[index].id, anchor: .center)
        }
    }

    /// Drag-to-browse: the auto-scroll pauses while the reader is in
    /// control and resumes — snapping back to the live line — five
    /// seconds after the last drag. Every new drag replaces the resume
    /// task, so a held page stays put.
    private func beginBrowsing(lyrics: Lyrics, proxy: ScrollViewProxy) {
        noteInteraction()
        isBrowsing = true
        browseResumeTask?.cancel()
        browseResumeTask = Task { @MainActor in
            try? await Task.sleep(for: Self.browseResumeAfter)
            guard !Task.isCancelled else { return }
            isBrowsing = false
            scrollTo(lyrics.activeLineIndex(at: store.player.elapsed), in: lyrics, proxy: proxy)
        }
    }

    /// BitChord's instrumental-gap dots: in any inter-line space longer
    /// than `minimumGap` the panel draws three dots that fill as the
    /// window passes, saturating as the next line begins. Line-timed
    /// data has no per-line end, so the fill runs across the whole
    /// window between the two lines.
    private enum LyricElement: Identifiable {
        case line(Int)
        case gap(start: TimeInterval, end: TimeInterval)

        var id: String {
            switch self {
            case .line(let index): "line-\(index)"
            case .gap(let start, let end): "gap-\(start)-\(end)"
            }
        }
    }

    private func lyricElements(_ lyrics: Lyrics, minimumGap: TimeInterval = 8) -> [LyricElement] {
        var elements: [LyricElement] = []
        for (index, line) in lyrics.lines.enumerated() {
            if let last = elements.last, case .line(let previous) = last {
                let gap = line.timestamp - lyrics.lines[previous].timestamp
                if gap > minimumGap {
                    elements.append(
                        .gap(start: lyrics.lines[previous].timestamp, end: line.timestamp)
                    )
                }
            }
            elements.append(.line(index))
        }
        return elements
    }

    /// The dots row — its own `TimelineView`, so the per-frame fill
    /// never touches anything else. Three dots over thirds of the
    /// window: each rests at a quarter opacity until its third arrives.
    private struct GapDotsRow: View {
        @Environment(AppStore.self) private var store
        let start: TimeInterval
        let end: TimeInterval

        var body: some View {
            TimelineView(.animation) { context in
                let now = LyricClock.elapsed(at: context.date, in: store.player)
                let span = max(end - start, 0.001)
                let progress = min(max((now - start) / span, 0), 1)
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 11, height: 11)
                            .opacity(max(0.25, min((progress * 3) - Double(index), 1)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .accessibilityLabel("Instrumental break")
            }
        }
    }

    // MARK: - Plain lyrics

    /// Un-synchronised lyrics: the original words, with the English
    /// translation underneath once it has been fetched.
    private func plainLyrics(_ plain: String, translation: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(plain)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                if let translation, !translation.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                    Text(translation)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .lineSpacing(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .simultaneousGesture(TapGesture().onEnded { noteInteraction() })
    }

    // MARK: - Loading & unavailable

    /// BitChord's skeleton: plausible lyric-width bars behind a slow
    /// shimmer — honest "something is coming" instead of a spinner,
    /// and it never claims "no lyrics" prematurely.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(Self.skeletonWidths.enumerated()), id: \.offset) { index, width in
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: width, height: 26)
                    .shimmer(delay: Double(index) * 0.12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("Looking up lyrics")
    }

    private static let skeletonWidths: [CGFloat] = [240, 270, 190, 260, 150, 230, 90]

    private var unavailable: some View {
        ContentUnavailableView {
            Label("No lyrics", systemImage: "text.quote")
        } description: {
            Text("Couldn't find lyrics for this track.")
        } actions: {
            Button("Retry") {
                noteInteraction()
                store.send(.refreshLyrics)
            }
            .buttonStyle(.bordered)
        }
    }

    private func noteInteraction() {
        onUserInteraction?()
    }
}

/// The skeleton's shimmer: a soft highlight sweeping each bar over
/// BitChord's 1.4 s period. Under Reduce Motion the bars pulse gently
/// in place instead of sweeping.
private struct Shimmer: ViewModifier {
    let delay: Double
    @State private var isSweeping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(isSweeping ? 0.55 : 1)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(delay)
                    ) { isSweeping = true }
                }
        } else {
            content
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.16), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: isSweeping ? 320 : -320)
                )
                .clipShape(Capsule())
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.4).repeatForever(autoreverses: false).delay(delay)
                    ) { isSweeping = true }
                }
        }
    }
}

private extension View {
    func shimmer(delay: Double) -> some View {
        modifier(Shimmer(delay: delay))
    }
}
