//
//  StationOrder.swift
//  PandoraCore
//
//  The user's station ordering (AGENTS.md persistence: "station order").
//
//  Pure logic: an ordered list of station ids with a custom-position map.
//  Stations the user has never touched keep the server's order; the
//  stored ids only pin the ones the user reordered.
//

import Foundation

/// Persisted station ordering.
public struct StationOrder: Codable, Sendable, Equatable {

    /// The stations the user moved, in their chosen order. Ids not in
    /// this list keep the server's relative order.
    public private(set) var orderedIds: [String]

    public init(orderedIds: [String] = []) {
        self.orderedIds = orderedIds
    }

    /// `true` when the user has not reordered anything.
    public var isEmpty: Bool { orderedIds.isEmpty }

    /// Applies the stored order to a station list.
    ///
    /// Stations the user moved come first (in their stored order), then
    /// the remaining stations in the order the server sent them. Ids in
    /// the store that no longer exist are dropped.
    public func apply(to stations: [Station]) -> [Station] {
        guard !orderedIds.isEmpty else { return stations }
        let byId = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [Station] = []
        var used: Set<String> = []
        for id in orderedIds {
            if let station = byId[id], !used.contains(id) {
                result.append(station)
                used.insert(id)
            }
        }
        for station in stations where !used.contains(station.id) {
            result.append(station)
        }
        return result
    }

    /// Records a new order (the ids as the user sees them).
    public mutating func setOrder(_ ids: [String]) {
        orderedIds = ids
    }

    /// Moves a station to a new position — the ids as the user sees them
    /// *before* the move, plus the station to move and its destination
    /// index.
    public mutating func move(stationId: String, to destination: Int, currentOrder: [String]) {
        var ids = currentOrder
        guard let from = ids.firstIndex(of: stationId) else { return }
        ids.remove(at: from)
        let target = min(max(0, destination), ids.count)
        ids.insert(stationId, at: target)
        orderedIds = ids
    }
}
