//
//  PandoraAPI.swift
//  PandoraCore
//
//  Legacy Pandora JSON API (v5) surface constants.
//
//  HARD RULE: PandoraCore never imports SwiftUI, UIKit or AVFoundation.
//  Pure protocol logic — the future Android-port surface.
//

import Foundation

/// Endpoints and fixed protocol constants for Pandora's legacy JSON API (v5).
///
/// Every value here is derived from the reference implementations
/// (`libpiano`, `pithos.pandora`) rather than guessed. Methods that vary per
/// request are declared on `PandoraAPIClient`.
public enum PandoraAPI {

    /// Hostname of the legacy JSON-RPC endpoint. Pandora has no separate TLS
    /// path: every call is a TLS-encrypted POST to this host with
    /// `Content-Type: application/x-www-form-urlencoded`.
    public static let baseURL = URL(string: "https://tuner.pandora.com/services/json/")!

    /// The `method` values this client issues.
    public enum Method {
        public static let partnerLogin = "auth.partnerLogin"
        public static let userLogin = "auth.userLogin"
    }

    /// Client-side identity used by `auth.partnerLogin`, as used by the
    /// reference clients. `deviceModel` is intentionally generic: this is an
    /// unofficial personal client, not a shipping commercial device.
    public static let partnerUsername = "android"
    public static let partnerPassword = "AC7IBG09A3DTSYM4R41UYWL7O76Z8J"
    public static let partnerDeviceModel = "android-generic"
    public static let version = "5"
}
