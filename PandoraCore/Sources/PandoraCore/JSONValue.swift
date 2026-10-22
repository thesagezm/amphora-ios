//
//  JSONValue.swift
//  PandoraCore
//
//  Minimal typed JSON scalar for building request bodies without `Any`.
//  Bodies are serialized with sorted keys so tests can assert exact bytes —
//  Pandora's server ignores object key order.
//

import Foundation

public enum JSONValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)

    /// Encodes a parameter dictionary as JSON with lexicographically sorted
    /// keys. Deterministic across platforms.
    public static func encoded(_ parameters: [String: JSONValue]) -> Data {
        let body = parameters.keys.sorted().map { key in
            escape(key) + ":" + (parameters[key] ?? .string("")).literal
        }.joined(separator: ",")
        return Data("{\(body)}".utf8)
    }

    /// This value's JSON text (not including surrounding braces).
    private var literal: String {
        switch self {
        case .string(let value): return escape(value)
        case .int(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }

    /// RFC 8259 string escaping. Control characters use the short forms
    /// where they exist; everything else below 0x20 uses \u00XX.
    private static func escape(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0C: out += "\\f"
            case 0x0D: out += "\\r"
            case 0x00...0x1F: out += String(format: "\\u%04x", Int(scalar.value))
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }
}
