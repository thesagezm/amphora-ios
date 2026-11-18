//
//  PlayerQueuePanel.swift
//  Amphora
//
//  BitChord's queue panel, read-only. Pandora's station queue is
//  server-driven — the server decides what comes next and the client
//  cannot reorder it, so the rows are the Pithos-style Up Next rows
//  in a frosted panel instead of the old collapsed disclosure. The
//  panel rides in the player's flexible region in place of the
//  artwork; the header, scrubber and transport stay live underneath,
//  because playback continues while the queue is open.
//

import PandoraCore
import SwiftUI

struct PlayerQueuePanel: View {
    @Environment(AppStore.self) private var store

    private var upcoming: [Track] { store.player.upcomingTracks }

    var body: some View {
        Group {
            if upcoming.isEmpty {
                ContentUnavailableView(
                    "Nothing queued",
                    systemImage: "music.note.list",
                    description: Text("The station's next tracks will appear here.")
                )
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, track in
                                row(track, position: index + 1)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            upcoming.isEmpty
                ? "Nothing queued"
                : "Up next: \(upcoming.map(\.title).joined(separator: ", "))"
        )
    }

    /// "Up Next" with the immediate title — the header the collapsed
    /// disclosure carried, kept so nothing is lost in the swap.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Up Next")
                .font(.footnote.weight(.semibold))
            Text(upcoming.first?.title ?? "")
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func row(_ track: Track, position: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .accessibilityHidden(true)
            CachedArtwork(
                urlString: track.artworkUrl,
                cornerRadius: 6,
                fallbackSystemImage: "music.note"
            )
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if track.isAdvertisement {
                Text("AD")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
