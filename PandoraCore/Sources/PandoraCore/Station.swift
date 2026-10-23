//
//  Station.swift
//  PandoraCore
//
//  Decodable models for `user.getStationList` results. Field names are the
//  wire keys from the legacy JSON API (v5), cross-checked against both
//  references:
//
//  - `pithos/pandora/pandora.py` `Station.__init__` — the minimal required
//    set every response carries (`stationId`, `stationToken`, `isShared`,
//    `isQuickMix`, `stationName`, plus `quickMixStationIds` on quickmix).
//  - pydora's `pandora/models/station.py` `Station`/`StationList` — the
//    optional set (`artUrl`, `isThumbprint`, `isGenreStation`, allow* flags,
//    `checksum`), decoded here as optionals so a sparse response never
//    fails the whole list.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

/// One station from `user.getStationList` (or a `station.createStation`
/// result — same wire shape, pithos constructs `Station(d)` from both).
public struct Station: Codable, Sendable, Equatable, Identifiable {
    /// `stationId` — stable numeric id (pithos `Station.id`).
    public let id: String
    /// `stationToken` — what later calls (`station.getPlaylist`,
    /// feedback, rename, delete) pass as `stationToken`.
    public let token: String
    /// `stationName` (pithos `Station.name`).
    public let name: String
    /// `isShared` — shared stations are not the user's own
    /// (pithos: `isCreator = not isShared`; rename transforms them first).
    public let isShared: Bool
    /// `isQuickMix` — the QuickMix aggregator station.
    public let isQuickMix: Bool
    /// `isThumbprint` — seeded from the user's thumbs (pydora).
    public let isThumbprint: Bool
    /// `isGenreStation` — a genre station rather than a personal one.
    public let isGenreStation: Bool
    /// `artUrl` — station artwork when the response carries it (pydora
    /// `art_url`; pithos doesn't read it). `includeStationArtUrl=true`.
    public let artUrl: String?
    /// `quickMixStationIds` — present only on the quickmix station;
    /// the ids of the stations feeding it (pithos reads it there).
    public let quickMixStationIds: [String]

    public init(
        id: String,
        token: String,
        name: String,
        isShared: Bool,
        isQuickMix: Bool,
        isThumbprint: Bool = false,
        isGenreStation: Bool = false,
        artUrl: String? = nil,
        quickMixStationIds: [String] = []
    ) {
        self.id = id
        self.token = token
        self.name = name
        self.isShared = isShared
        self.isQuickMix = isQuickMix
        self.isThumbprint = isThumbprint
        self.isGenreStation = isGenreStation
        self.artUrl = artUrl
        self.quickMixStationIds = quickMixStationIds
    }

    /// Decodes one station from an unwrapped result object (e.g.
    /// `station.createStation`'s reply).
    public init(result: [String: AnyJSON]) throws {
        self = try JSONDecoder().decode(Station.self, from: JSONEncoder().encode(AnyJSON.object(result)))
    }

    /// Wire-key decoding: `stationId`/`stationToken` map onto the Swift
    /// names above; ids arrive as either JSON string or number (pithos
    /// formats with `%s`, accepting both).
    private enum CodingKeys: String, CodingKey {
        case id = "stationId"
        case token = "stationToken"
        case name = "stationName"
        case isShared
        case isQuickMix
        case isThumbprint
        case isGenreStation
        case artUrl
        case quickMixStationIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.stringId(c, .id)
        token = try Self.stringId(c, .token)
        name = try c.decode(String.self, forKey: .name)
        isShared = try c.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        isQuickMix = try c.decodeIfPresent(Bool.self, forKey: .isQuickMix) ?? false
        isThumbprint = try c.decodeIfPresent(Bool.self, forKey: .isThumbprint) ?? false
        isGenreStation = try c.decodeIfPresent(Bool.self, forKey: .isGenreStation) ?? false
        artUrl = try c.decodeIfPresent(String.self, forKey: .artUrl)
        quickMixStationIds = try c.decodeIfPresent([String].self, forKey: .quickMixStationIds) ?? []
    }

    /// `stationId`/`stationToken` are string-or-number on the wire.
    private static func stringId(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let n = try? c.decode(Int.self, forKey: key) { return String(n) }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: c, debugDescription: "missing or non-numeric \(key.stringValue)"
        )
    }
}

/// The `user.getStationList` result: `stations` plus a `checksum` that
/// later `user.getStationListChecksum` calls compare against (pydora
/// `StationList.has_changed`; unused for now, decoded so it isn't lost).
public struct StationList: Codable, Sendable, Equatable {
    public let stations: [Station]
    public let checksum: String?

    public init(stations: [Station], checksum: String? = nil) {
        self.stations = stations
        self.checksum = checksum
    }

    private enum CodingKeys: String, CodingKey {
        case stations
        case checksum
    }

    /// Decodes from the already-unwrapped `[String: AnyJSON]` result of
    /// `ResponseEnvelope.result(from:)` — the same shape pydora feeds its
    /// model layer.
    public init(result: [String: AnyJSON]) throws {
        guard let array = result["stations"]?.arrayValue else {
            throw PandoraMalformedResponseError(detail: "station list missing stations array")
        }
        let data = try JSONEncoder().encode(array)
        stations = try JSONDecoder().decode([Station].self, from: data)
        checksum = result["checksum"]?.stringValue
    }
}
