//
//  TrackStatsSheet.swift
//  Amphora
//
//  BitChord's "stats for nerds" sheet, adapted to what Pandora
//  actually exposes: the stream variant the player is really using
//  (bitrate, encoding — the same chip data the header carries, now
//  with the full story), the track's length, its album and station,
//  where the audio is going, and what the lyrics lookup found. Every
//  row is honest data from the store — nothing invented for the sake
//  of the aesthetic (the protocol has no bit depth or sample rate to
//  report; a live stream has no length).
//

import PandoraCore
import SwiftUI

struct TrackStatsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var theme: ArtworkThemeController { ArtworkThemeController.shared }

    /// The track behind the sheet — nil on radio until a song is
    /// identified, in which case the stats describe the stream itself.
    private var track: Track? { store.player.currentTrack }
    private var isRadio: Bool { track?.isRadio == true }

    var body: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    if let track {
                        row("Title", track.title)
                        row("Artist", track.artist)
                        if !isRadio, !track.album.isEmpty {
                            row("Album", track.album)
                        }
                        row(
                            "Length",
                            isRadio
                                ? "Live"
                                : AmphoraTimeFormat.string(TimeInterval(track.duration))
                        )
                        row("Quality", qualityDescription)
                    } else {
                        row("State", "Nothing playing")
                    }
                    if let station = stationName {
                        row("Station", station)
                    }
                    if let route = store.player.outputRouteName {
                        row("Output", route)
                    } else {
                        row("Output", "Phone speaker")
                    }
                }
                if let lyrics = store.lyrics {
                    Section("Lyrics") {
                        if lyrics.isSynced {
                            row("Source", "Synchronised · \(lyrics.lines.count) lines")
                        } else if let plain = lyrics.plainText, !plain.isEmpty {
                            row("Source", "Plain text")
                        } else if lyrics.instrumental {
                            row("Source", "Instrumental")
                        } else {
                            row("Source", "None found")
                        }
                        if store.lyricsOffset != 0 {
                            row("Timing offset", String(format: "%+.1f s", store.lyricsOffset))
                        }
                    }
                }
            }
            .navigationTitle("Track Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var stationName: String? {
        if isRadio {
            return store.currentRadioStation?.name ?? track?.title
        }
        return store.currentStation?.name
    }

    /// The variant the player streams, spelled out — "128 kbps · MP3".
    /// A live stream reports itself honestly: the directory does not
    /// carry a guaranteed bitrate.
    private var qualityDescription: String {
        guard let track else { return "—" }
        guard !track.isRadio else { return "Live stream" }
        guard let variant = track.preferredVariant else { return "—" }
        let encoding: String
        switch variant.encoding.lowercased() {
        case "mp3": encoding = "MP3"
        case "aacplus": encoding = "AAC+"
        case "aac": encoding = "AAC"
        default: encoding = variant.encoding.uppercased()
        }
        return "\(variant.bitrate) kbps · \(encoding)"
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(label)
        }
    }
}
