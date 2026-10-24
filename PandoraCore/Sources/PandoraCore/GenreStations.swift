//
//  GenreStations.swift
//  PandoraCore
//
//  Pandora's featured "genre" stations — the curated, Pandora-created
//  stations ("Today's Hits", "Classic Rock", …) shown on Pandora's own
//  front page, grouped into browse categories. Legacy v5:
//
//    station.getGenreStations   (no parameters)
//      → {"categories": [
//           {"categoryName": "Pop",
//            "stations": [{"stationId": …, "stationToken": …,
//                          "stationName": …, "categoryName": …}]}],
//         "checksum": …}
//
//  A genre station has no playlist of its own — a personal station is
//  created from it with `station.createStation {"musicToken":
//  <that stationToken>}`. Verified 2026-10-24 against four independent
//  clients:
//
//  - pydora (`mcrute/pydora`): `client.py` `get_genre_stations` calls the
//    method with no parameters; `models/station.py` `GenreStation` maps
//    `stationId`/`stationName`/`stationToken`/`categoryName` and
//    refuses playlists ("Create a real station using the token").
//  - pancake (`FancyFurret/pancake`): `GenreStations` — `categories` /
//    `categoryName` / `stations` keys, stations decode as full stations.
//  - python-pandora (`02strich`) and the Sonos Indigo plugin: same call,
//    no parameters.
//  - xivpiano (`Spaceghost/xivpiano-dalamud`, `PandoraClient.cs:261`):
//    "Pandora's genre stations, by category; making one uses its token
//    as the music token" — the create flow. pithos's search-genre
//    results use the same `musicToken` create shape
//    (`add_station_by_music_id`).
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

/// One Pandora-created station inside a browse category.
public struct GenreStation: Sendable, Equatable, Identifiable {
    /// `stationToken` — the value passed as `musicToken` to
    /// `station.createStation` when the user wants this station.
    public let token: String
    /// `stationId` — the numeric web id, when the reply carries one
    /// (number or string tolerated).
    public let stationId: String
    /// `stationName`, e.g. "Today's Hits".
    public let name: String
    /// `categoryName` — repeated on the station entry by the API; when
    /// the entry omits it, the decoder fills in the category's own.
    public let categoryName: String
    /// `artUrl` when the reply carries one; the UI falls back to a
    /// generic glyph when absent.
    public let artUrl: String?

    public var id: String { token }

    public init(
        token: String,
        stationId: String = "",
        name: String,
        categoryName: String,
        artUrl: String? = nil
    ) {
        self.token = token
        self.stationId = stationId
        self.name = name
        self.categoryName = categoryName
        self.artUrl = artUrl
    }
}

/// A browse category and its stations (one `categories` entry).
public struct GenreCategory: Sendable, Equatable, Identifiable {
    /// `categoryName`, e.g. "Pop".
    public let name: String
    public let stations: [GenreStation]

    public var id: String { name }

    public init(name: String, stations: [GenreStation]) {
        self.name = name
        self.stations = stations
    }
}

/// The `station.getGenreStations` reply.
public struct GenreStations: Sendable, Equatable {
    public let categories: [GenreCategory]

    public init(categories: [GenreCategory]) {
        self.categories = categories
    }

    /// Decodes from the request's `result` object (also the test seam).
    /// Missing/not-array `categories` is malformed (the method has no
    /// other failure mode on the wire); inside, decoding is tolerant —
    /// entries without a token or name are dropped, duplicate tokens
    /// within a category keep the first, empty categories are dropped.
    public init(result: [String: AnyJSON]) throws {
        guard let entries = result["categories"]?.arrayValue else {
            throw PandoraMalformedResponseError(detail: "genre stations missing categories array")
        }
        var parsed: [GenreCategory] = []
        for entry in entries {
            guard let object = entry.objectValue else { continue }
            guard let name = object["categoryName"]?.stringValue, !name.isEmpty else { continue }
            var stations: [GenreStation] = []
            var seen = Set<String>()
            for station in object["stations"]?.arrayValue ?? [] {
                guard let stationObject = station.objectValue else { continue }
                guard let token = stationObject["stationToken"]?.stringValue, !token.isEmpty else { continue }
                guard let stationName = stationObject["stationName"]?.stringValue, !stationName.isEmpty else { continue }
                guard !seen.contains(token) else { continue }
                seen.insert(token)
                stations.append(
                    GenreStation(
                        token: token,
                        stationId: Self.idString(stationObject["stationId"]),
                        name: stationName,
                        categoryName: stationObject["categoryName"]?.stringValue ?? name,
                        artUrl: stationObject["artUrl"]?.stringValue
                    )
                )
            }
            guard !stations.isEmpty else { continue }
            parsed.append(GenreCategory(name: name, stations: stations))
        }
        self.init(categories: parsed)
    }

    /// `stationId` arrives as JSON number or string.
    private static func idString(_ value: AnyJSON?) -> String {
        value?.stringValue ?? value?.intValue.map(String.init) ?? ""
    }
}
