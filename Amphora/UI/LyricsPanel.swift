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
    /// BitChord's sub-line toggles: the romanization and the English
    /// translation are readable on demand and hideable again — the
    /// discs above the panel carry both states.
    @State private var isRomanizationVisible = true
    @State private var isTranslationVisible = true
    /// BitChord's offset sheet, reached from the timing disc.
    @State private var isShowingOffset = false

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
        .sheet(isPresented: $isShowingOffset) {
            LyricsOffsetSheet()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            browseResumeTask?.cancel()
            browseResumeTask = nil
        }
    }

    /// The sub-line control bar — BitChord's discs, adapted: the
    /// romanization and the English translation toggle as frosted
    /// discs on the right, the state text sits on the left. A disc
    /// shows a spinner while its request is in flight. The 34 pt disc
    /// rides a 44 pt hit target — BitChord's 34 dp discs are below the
    /// app's touch-target floor.
    private var translationBar: some View {
        HStack(spacing: 12) {
            statusText
            Spacer(minLength: 0)
            if romanizationAvailable {
                disc(
                    icon: "globe",
                    isActive: isRomanizationVisible,
                    isLoading: false,
                    label: isRomanizationVisible
                        ? "Hide romanization" : "Show romanization"
                ) {
                    withAnimation(Self.subLineAnimation) {
                        isRomanizationVisible.toggle()
                    }
                }
            }
            translationDisc
            // The timing disc: accent while an offset is applied, so
            // "why are the lyrics weird?" has a visible answer.
            disc(
                icon: "clock",
                isActive: store.lyricsOffset != 0,
                isLoading: false,
                label: "Adjust lyrics timing"
            ) {
                isShowingOffset = true
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
    }

    /// Whether any line carries a romanization — the disc earns its
    /// place only when there is something to toggle.
    private var romanizationAvailable: Bool {
        store.lyrics?.lines.contains { !($0.romanization ?? "").isEmpty } == true
    }

    /// The English text under each line: on screen only when the
    /// translation exists and the disc has not hidden it.
    private var isTranslationShown: Bool {
        store.lyricsTranslationState == .translated && isTranslationVisible
    }

    @ViewBuilder
    private var statusText: some View {
        switch store.lyricsTranslationState {
        case .translating:
            Text("Translating…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .alreadyEnglish:
            Text("Already in English")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.yellow)
        case .none, .translated:
            EmptyView()
        }
    }

    @ViewBuilder
    private var translationDisc: some View {
        switch store.lyricsTranslationState {
        case .none, .failed:
            // Something to ask for, or a failed request to retry.
            disc(
                icon: "character.bubble",
                isActive: false,
                isLoading: false,
                label: store.lyricsTranslationState == .none
                    ? "Translate the lyrics into English"
                    : "Retry the translation"
            ) {
                noteInteraction()
                store.send(.translateLyrics)
            }
        case .translating:
            // A no-op disc — the spinner is the whole message, so the
            // button is disabled and never haptic-fires.
            disc(icon: "character.bubble", isActive: false, isLoading: true, label: "Translating") {
            }
            .disabled(true)
        case .translated:
            disc(
                icon: "character.bubble",
                isActive: isTranslationVisible,
                isLoading: false,
                label: isTranslationVisible
                    ? "Hide the translation" : "Show the translation"
            ) {
                withAnimation(Self.subLineAnimation) {
                    isTranslationVisible.toggle()
                }
            }
        case .alreadyEnglish:
            // Nothing to ask for — the status text says why.
            EmptyView()
        }
    }

    /// BitChord's disc: a 34 pt circle with a spinner while loading,
    /// accent-filled while its content is on screen. The frosted
    /// material matches the player's dock discs.
    private func disc(
        icon: String,
        isActive: Bool,
        isLoading: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.primary)
                } else {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(isActive ? Theme.accentGlyph : Color.primary)
            .frame(width: 34, height: 34)
            .background(
                isActive
                    ? AnyShapeStyle(Theme.accent)
                    : AnyShapeStyle(.ultraThinMaterial),
                in: Circle()
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// BitChord's sub-line motion: 540 ms rise-and-fade when a
    /// translation or romanization toggles on.
    static let subLineAnimation = Animation.timingCurve(
        0.215, 0.61, 0.355, 1, duration: 0.54
    )

    static let subLineTransition: AnyTransition = .opacity.combined(
        with: .offset(y: -6)
    )

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
                    let clock = LyricClock.elapsed(
                        at: context.date, in: store.player, offset: store.lyricsOffset
                    )
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
            // The scroll view's identity is the lyrics' first line — a
            // new song resets the scroll and re-runs the landing scroll
            // (a re-fetch of the same song keeps the position, which is
            // right). `Lyrics` is only Equatable; the first line's id
            // is the identity without dragging Hashable into the core.
            .id(lyrics.lines.first?.id ?? "")
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
                        lineRow(lyrics, index: index, highlightIndex: highlightIndex)
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

    /// BitChord's falloff from the sung line — static per row, so a
    /// distant line renders once and never again until the distance
    /// changes. Alphas from their table; the blur ramps only in the
    /// near field and vanishes beyond it.
    private func falloffAlpha(_ distance: Int?, isActive: Bool) -> Double {
        guard !isActive else { return 1 }
        switch distance ?? 99 {
        case 1: 0.8
        case 2: 0.7
        case 3: 0.58
        case 4: 0.46
        default: 0.35
        }
    }

    private func falloffBlur(_ distance: Int?, isActive: Bool) -> CGFloat {
        guard !isActive else { return 0 }
        switch distance ?? 99 {
        case 1, 2: 1
        case 3: 1.7
        case 4: 2.4
        default: 0
        }
    }

    /// One lyric line. The sung line is BitChord's swept line — the
    /// bright wavefront crossing word by word, unsung text dim beneath;
    /// every other line is static text at its falloff. Tapping a line
    /// seeks to its start.
    private func lineRow(
        _ lyrics: Lyrics, index: Int, highlightIndex: Int?
    ) -> some View {
        let line = lyrics.lines[index]
        let isActive = index == highlightIndex
        let distance = highlightIndex.map { abs($0 - index) }
        return VStack(alignment: .leading, spacing: 4) {
            if isActive {
                SweptLine(
                    text: line.text,
                    start: line.timestamp,
                    end: nextLineStart(lyrics, after: index),
                    font: .title3.weight(.bold)
                )
            } else {
                Text(line.text)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(3)
            }
            if isRomanizationVisible, let romanization = line.romanization, !romanization.isEmpty {
                // Non-Latin-script lyrics: the original script stays as
                // a reference line, the romanization is the reading
                // line the user sings along with (accent-tinted), and
                // the English translation sits beneath both.
                Text(romanization)
                    .font(.title3.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(
                        isActive
                            ? theme.colors.accent.color
                            : theme.colors.accent.color.opacity(0.7)
                    )
                    .lineLimit(3)
                if isTranslationShown, let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .lineLimit(3)
                        .transition(Self.subLineTransition)
                }
            } else if isTranslationShown, let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .lineLimit(3)
                    .transition(Self.subLineTransition)
            }
        }
        .animation(Self.subLineAnimation, value: isTranslationShown)
        .animation(Self.subLineAnimation, value: isRomanizationVisible)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            noteInteraction()
            isBrowsing = false
            browseResumeTask?.cancel()
            store.player.seek(to: line.timestamp)
        }
        .opacity(falloffAlpha(distance, isActive: isActive))
        .blur(radius: falloffBlur(distance, isActive: isActive))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap to jump here")
    }

    /// The sweep window's end: the next line's start, or a short hold
    /// for a last line or a repeated timestamp.
    private func nextLineStart(_ lyrics: Lyrics, after index: Int) -> TimeInterval {
        let next = lyrics.lines.index(after: index)
        if next < lyrics.lines.endIndex,
            lyrics.lines[next].timestamp > lyrics.lines[index].timestamp {
            return lyrics.lines[next].timestamp
        }
        return lyrics.lines[index].timestamp + 4
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
                let now = LyricClock.elapsed(
                    at: context.date, in: store.player, offset: store.lyricsOffset
                )
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
    /// translation underneath once it has been fetched — toggleable
    /// like the synced sub-lines.
    private func plainLyrics(_ plain: String, translation: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(plain)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                if isTranslationShown, let translation, !translation.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                    Text(translation)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .lineSpacing(6)
                        .transition(Self.subLineTransition)
                }
            }
            .animation(Self.subLineAnimation, value: isTranslationShown)
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
