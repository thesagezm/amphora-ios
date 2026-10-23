//
//  KeychainSessionStore.swift
//  Amphora
//
//  `SessionStore` backed by the Keychain: persists credentials + tokens so
//  warm launch can auto-login without a password round trip. No secret ever
//  reaches UserDefaults. PandoraCore stays portable — this is the Apple-side
//  half of the injected store seam.
//

import Foundation
import PandoraCore

struct KeychainSessionStore: SessionStore {
    private let keychain: KeychainStore
    private let account = "session"

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func save(_ record: SessionRecord) throws {
        let data = try JSONEncoder().encode(record)
        try keychain.set(data, for: account)
    }

    func load() -> SessionRecord? {
        // A missing item or undecodable blob both mean "no usable session" —
        // the user sees the login screen and the next save overwrites it.
        guard let data = try? keychain.data(for: account) else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }

    func clear() throws {
        try keychain.remove(account)
    }
}
