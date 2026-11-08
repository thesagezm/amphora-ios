//
//  UserSettings.swift
//  PandoraCore
//
//  The account-level settings Pandora exposes (`user.getSettings`).
//
//  The field Amphora uses is the **explicit-content filter**. It is an
//  account-level switch, not a per-track flag: pithos reads it from
//  `Pandora.explicit_content_filter_state` — `user.getSettings` over
//  HTTPS with an encrypted body (the same shape as every other
//  authenticated call) — and the reply carries
//  `isExplicitContentFilterEnabled` plus
//  `isExplicitContentFilterPINProtected`.
//
//  Why this matters for the UI: there is **no per-item explicit flag on
//  the wire**, so a per-station badge would be invented data. The
//  honest surface is one account-level badge: when the filter is on,
//  explicit tracks are hidden for this account.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

/// The account's user settings (`user.getSettings`).
public struct UserSettings: Codable, Sendable, Equatable {

    /// `true` when Pandora hides explicit tracks for this account.
    public let isExplicitContentFilterEnabled: Bool

    /// `true` when the filter is locked behind a PIN. The app only
    /// reports it — changing the filter is out of scope.
    public let isExplicitContentFilterPINProtected: Bool

    public init(
        isExplicitContentFilterEnabled: Bool,
        isExplicitContentFilterPINProtected: Bool = false
    ) {
        self.isExplicitContentFilterEnabled = isExplicitContentFilterEnabled
        self.isExplicitContentFilterPINProtected = isExplicitContentFilterPINProtected
    }

    /// Decodes the `user.getSettings` result.
    ///
    /// A missing key means "off" — pithos reads the field with
    /// `.get('isExplicitContentFilterEnabled', False)`, so an older
    /// server that does not send the key is treated the same way.
    public init(result: [String: AnyJSON]) {
        isExplicitContentFilterEnabled =
            result["isExplicitContentFilterEnabled"]?.boolValue ?? false
        isExplicitContentFilterPINProtected =
            result["isExplicitContentFilterPINProtected"]?.boolValue ?? false
    }
}
