import PandoraCore
import SwiftUI

/// "Recently played" — the local playback history, newest first.
struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.history.isEmpty {
                ContentUnavailableView {
                    Label("Nothing played yet", systemImage: "clock")
                } description: {
                    Text("Tracks you listen to will show up here.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Recently Played")
    }

    private var list: some View {
        List(store.history) { entry in
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary.opacity(0.5))
                    if let urlString = entry.artworkUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            icon
                        }
                    } else {
                        icon
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(entry.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(entry.playedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        }
        .listStyle(.plain)
    }

    private var icon: some View {
        Image(systemName: "music.note")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
