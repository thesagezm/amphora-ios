//
//  NetworkMonitor.swift
//  Amphora
//
//  The app's knowledge of the network path. `NWPathMonitor` watches
//  the path, so the app knows it is offline *before* a request fails
//  — a failed request is a guess about why, a dropped path is a fact
//  — and can recover the moment the path comes back.
//
//  The app target owns this: Network.framework is Apple-specific, and
//  PandoraCore stays portable (it only classifies transport failures,
//  which is a different question).
//

import Foundation
import Network

/// Watches the network path and reports the changes to the app.
@MainActor
final class NetworkMonitor {

    /// Called on the main actor whenever the path's connectivity
    /// changes (`true` = reachable).
    var onChange: ((Bool) -> Void)?

    /// `true` when the path is satisfied — the network is reachable.
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.personal.amphora.network-path")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isConnected != connected else { return }
                self.isConnected = connected
                self.onChange?(connected)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
