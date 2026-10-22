//
//  PandoraAPIClient.swift
//  PandoraCore
//

import Foundation

/// The protocol surface `LegacyPandoraClient` implements, so a modern-API
/// implementation can be swapped in later without touching the app.
public protocol PandoraAPIClient: Sendable {

    /// Issues one JSON-RPC call against the legacy endpoint and returns the
    /// decoded `result` object. Decoding into typed models happens above
    /// this layer, so a swapped-in implementation only has to move bytes.
    func request(
        method: String,
        parameters: [String: JSONValue]
    ) async throws -> [String: AnyJSON]
}
