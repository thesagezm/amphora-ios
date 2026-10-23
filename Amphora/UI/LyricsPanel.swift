//
//  LyricsPanel.swift
//  Amphora
//
//  Lyrics in the full player. Synchronised lines scroll with playback
//  and seek on tap; plain lyrics scroll freely; the unavailable case
//  offers a retry. All state comes from `AppStore` — the view holds no
//  fetching or business logic.
//

import PandoraCore
import SwiftUI

struct LyricsPanel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let lyrics = store.lyrics, !lyrics.isEmpty {
                content(for: lyrics)
            } else if store.isLoadingLyrics {
                loading
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for lyrics: Lyrics) -> some View {
        if lyrics.isSynced {
            syncedLyrics(lyrics)
        } else if let plain = lyrics.plainText, !plain.isEmpty {
            ScrollView {
                Text(plain)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
            }
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

    /// Synchronised lines: the active line is highlighted and kept
    /// centred; tapping a line seeks to its start.
    private func syncedLyrics(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    let activeIndex = lyrics.activeLineIndex(at: store.player.elapsed)
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = index == activeIndex
                        Text(line.text)
                            .font(.title3.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? Color.primary : Color.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { store.player.seek(to: line.timestamp) }
                            .accessibilityHint("Double-tap to jump here")
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 100)
            }
            .onChange(of: activeIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(lyrics.lines[index].id, anchor: .center)
                }
            }
            .task {
                // Arriving mid-track: land on the current line. A short
                // delay lets the scroll view lay out first.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled,
                      let index = lyrics.activeLineIndex(at: store.player.elapsed) else { return }
                proxy.scrollTo(lyrics.lines[index].id, anchor: .center)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Looking up lyrics…")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("No lyrics", systemImage: "text.quote")
        } description: {
            Text("Couldn't find lyrics for this track.")
        } actions: {
            Button("Retry") { store.send(.refreshLyrics) }
                .buttonStyle(.bordered)
        }
    }
}
