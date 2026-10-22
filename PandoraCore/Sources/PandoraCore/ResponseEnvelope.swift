//
//  ResponseEnvelope.swift
//  PandoraCore
//
//  Decodes Pandora's JSON-RPC envelope, mirroring `pithos.pandora.json_call`
//  response handling:
//
//      {"stat": "ok",   "result": {...}}
//      {"stat": "fail", "code": 1001, "message": "..."}
//
//  `stat == "fail"` → typed `PandoraAPIError` (never crash).
//  `stat == "ok"`   → the `result` value.
//
//  No logging of tokens or full bodies: only the fault code and message.
//

import Foundation

public enum ResponseEnvelope: Sendable {

    /// Decodes `payload` and returns the `result` object, or throws a typed
    /// error for a fault or a malformed body.
    public static func result(from payload: Data) throws -> [String: AnyJSON] {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: payload)
        } catch {
            throw PandoraMalformedResponseError(detail: "undecodable response body")
        }
        switch envelope.stat {
        case "ok":
            guard let result = envelope.result else {
                throw PandoraMalformedResponseError(detail: "ok response missing result")
            }
            return result
        case "fail":
            guard let code = envelope.code else {
                throw PandoraMalformedResponseError(detail: "fail response missing code")
            }
            throw PandoraAPIError(
                code: code,
                message: envelope.message ?? "unknown error"
            )
        default:
            throw PandoraMalformedResponseError(detail: "unknown stat \(envelope.stat)")
        }
    }

    private struct Envelope: Decodable {
        let stat: String
        let code: Int?
        let message: String?
        let result: [String: AnyJSON]?
    }
}
