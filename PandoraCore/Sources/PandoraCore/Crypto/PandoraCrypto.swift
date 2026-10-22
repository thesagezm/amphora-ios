//
//  PandoraCrypto.swift
//  PandoraCore
//
//  Blowfish-ECB primitives for Pandora's legacy JSON API (v5).
//
//  Protocol shape, derived from `pithos.pandora` (verified against the
//  vendored `pithos/pandora/blowfish.py` + `pandora.py`):
//
//  - Request bodies: zero-pad each 8-byte chunk (pad only a partial final
//    chunk, never a full extra block) → Blowfish-ECB with `encryptKey`
//    → lowercase hex string, sent as the POST body.
//  - Response fields (e.g. `syncTime`): hex string → Blowfish-ECB decrypt
//    with `decryptKey` → raw bytes (callers strip trailing zero bytes).
//
//  Hard rule: no UI, no AVFoundation — pure logic for the Android port.
//

import Foundation
import CryptoSwift

public enum PandoraCryptoError: Error, Equatable, Sendable {
    /// Input was not valid hexadecimal, or had an odd number of digits.
    case invalidHex
    /// Ciphertext length was not a multiple of the 8-byte Blowfish block.
    case notBlockAligned(actual: Int)
}

public enum PandoraCrypto {

    /// Blowfish block size in bytes.
    public static let blockSize = 8

    /// Encrypts `plaintext` with Blowfish-ECB under `key`.
    /// Zero-pads to the block boundary first; an already-aligned input is
    /// left untouched (matching pithos' per-chunk `pad`), so a message whose
    /// length is a multiple of 8 gains no extra block.
    public static func encrypt(_ plaintext: Data, key: String) throws -> Data {
        guard !plaintext.isEmpty else { return Data() }
        var padded = plaintext
        let remainder = padded.count % blockSize
        if remainder != 0 {
            padded.append(Data(count: blockSize - remainder))
        }
        let cipher = try Blowfish(key: Array(key.utf8), blockMode: ECB(), padding: .noPadding)
        return try Data(cipher.encrypt(padded))
    }

    /// Decrypts Blowfish-ECB `ciphertext` under `key`.
    /// Trailing zero-padding from the encrypt path is NOT stripped here —
    /// callers slice fields exactly as pithos does (`syncTime[4:14]`).
    public static func decrypt(_ ciphertext: Data, key: String) throws -> Data {
        guard !ciphertext.isEmpty else { return Data() }
        guard ciphertext.count % blockSize == 0 else {
            throw PandoraCryptoError.notBlockAligned(actual: ciphertext.count)
        }
        let cipher = try Blowfish(key: Array(key.utf8), blockMode: ECB(), padding: .noPadding)
        return try Data(cipher.decrypt(ciphertext))
    }

    /// Encrypts then hex-encodes — the exact wire form of a request body.
    public static func encryptToHex(_ plaintext: Data, key: String) throws -> String {
        try hexString(from: encrypt(plaintext, key: key))
    }

    /// Hex-decodes then decrypts — the exact inverse of `encryptToHex`.
    public static func decryptFromHex(_ hex: String, key: String) throws -> Data {
        try decrypt(data(fromHex: hex), key: key)
    }

    // MARK: - Wire conveniences keyed with `PandoraAPI` constants

    /// Encrypts a JSON request body for transmission (uses `encryptKey`).
    public static func encryptRequestBody(_ json: Data) throws -> String {
        try encryptToHex(json, key: PandoraAPI.encryptKey)
    }

    /// Decrypts a hex-encoded response field such as `syncTime`
    /// (uses `decryptKey`).
    public static func decryptHexField(_ hex: String) throws -> Data {
        try decryptFromHex(hex, key: PandoraAPI.decryptKey)
    }

    // MARK: - Hex helpers (owned locally: lowercase output, strict input)

    static func hexString(from data: Data) -> String {
        // Int (not UInt8): %x varargs promotion is unreliable in
        // swift-corelibs-foundation on Linux CI.
        data.map { String(format: "%02x", Int($0)) }.joined()
    }

    static func data(fromHex hex: String) throws -> Data {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count % 2 == 0 else { throw PandoraCryptoError.invalidHex }
        var bytes = Data(capacity: trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<next], radix: 16) else {
                throw PandoraCryptoError.invalidHex
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
