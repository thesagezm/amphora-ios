//
//  StationOrderTests.swift
//  PandoraCoreTests
//
//  The persisted station ordering.
//

import XCTest
@testable import PandoraCore

final class StationOrderTests: XCTestCase {

    private func station(_ id: String, name: String = "S") -> Station {
        Station(
            id: id,
            token: "T-\(id)",
            name: name,
            isShared: false,
            isQuickMix: false
        )
    }

    func testEmptyOrderKeepsServerOrder() {
        let stations = [station("1"), station("2"), station("3")]
        let order = StationOrder()
        XCTAssertTrue(order.isEmpty)
        XCTAssertEqual(order.apply(to: stations).map(\.id), ["1", "2", "3"])
    }

    func testStoredIdsComeFirstInStoredOrder() {
        let stations = [station("1"), station("2"), station("3")]
        let order = StationOrder(orderedIds: ["3", "1"])
        XCTAssertEqual(order.apply(to: stations).map(\.id), ["3", "1", "2"])
    }

    func testUnknownStoredIdsAreDropped() {
        let stations = [station("1"), station("2")]
        let order = StationOrder(orderedIds: ["ghost", "2"])
        XCTAssertEqual(order.apply(to: stations).map(\.id), ["2", "1"])
    }

    func testMoveReordersTheList() {
        var order = StationOrder()
        let current = ["1", "2", "3"]
        order.move(stationId: "1", to: 2, currentOrder: current)
        XCTAssertEqual(order.orderedIds, ["2", "3", "1"])
    }

    func testMoveClampsDestination() {
        var order = StationOrder()
        order.move(stationId: "1", to: 99, currentOrder: ["1", "2", "3"])
        XCTAssertEqual(order.orderedIds, ["2", "3", "1"])
        order.move(stationId: "3", to: -5, currentOrder: order.orderedIds)
        XCTAssertEqual(order.orderedIds, ["3", "2", "1"])
    }

    func testMoveOfUnknownStationIsIgnored() {
        var order = StationOrder()
        order.move(stationId: "ghost", to: 0, currentOrder: ["1", "2"])
        XCTAssertTrue(order.orderedIds.isEmpty)
    }

    func testCodableRoundTrip() throws {
        let order = StationOrder(orderedIds: ["a", "b"])
        let data = try JSONEncoder().encode(order)
        let restored = try JSONDecoder().decode(StationOrder.self, from: data)
        XCTAssertEqual(restored, order)
    }
}
