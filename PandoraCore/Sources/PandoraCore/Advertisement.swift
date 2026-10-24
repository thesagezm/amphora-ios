//
//  Advertisement.swift
//  PandoraCore
//
//  Audio advertisements on free accounts, after pydora
//  `pandora/models/ad.py` (pithos has no ad handling at all):
//
//  - A playlist ad entry is a stub — `adToken` + display fields, usually
//    no audio. It is resolved with `ad.getAdMetadata` (params
//    `returnAdTrackingTokens=true`, `supportAudioAds=true`).
//  - The impression is registered with `ad.registerAd`, carrying the
//    station id and the tracking tokens from the metadata reply — pydora
//    `AdItem.prepare_playback` / `register_ad`.
//
//  No UI, no AVFoundation — PandoraCore stays portable.
//

import Foundation

public enum AdvertisementError: Error, Equatable, Sendable {
    /// `registerAd` refuses empty tracking-token lists before any network
    /// (pydora `ParameterMissing`: "No ad tracking tokens provided").
    case missingTrackingTokens
    /// The track passed to `prepareAd` is not an advertisement.
    case notAnAdvertisement
}

/// One resolved audio advertisement (pydora `AdItem` fields).
public struct Advertisement: Codable, Sendable, Equatable {
    public let adToken: String
    public let title: String
    public let companyName: String
    /// Tracking tokens from the metadata reply
    /// (`returnAdTrackingTokens=true`); empty when the reply omitted them.
    public let trackingTokens: [String]
    public let audioURL: String?
    public let imageURL: String?
    public let clickThroughURL: String?

    public init(
        adToken: String,
        title: String = "",
        companyName: String = "",
        trackingTokens: [String] = [],
        audioURL: String? = nil,
        imageURL: String? = nil,
        clickThroughURL: String? = nil
    ) {
        self.adToken = adToken
        self.title = title
        self.companyName = companyName
        self.trackingTokens = trackingTokens
        self.audioURL = audioURL
        self.imageURL = imageURL
        self.clickThroughURL = clickThroughURL
    }

    /// Decodes the `ad.getAdMetadata` result object — pydora builds its
    /// `AdItem` straight from that dict. Missing display fields are
    /// tolerated (pydora fields default to None); the adToken is the one
    /// the request was made with.
    public init(adToken: String, result: [String: AnyJSON]) {
        self.adToken = adToken
        self.title = result["title"]?.stringValue ?? ""
        self.companyName = result["companyName"]?.stringValue ?? ""
        self.trackingTokens = (result["adTrackingTokens"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }
        self.audioURL = result["audioUrl"]?.stringValue
        self.imageURL = result["imageUrl"]?.stringValue
        self.clickThroughURL = result["clickThroughUrl"]?.stringValue
    }

    /// The ad as a player-queue slot. pydora's `AudioField` treats a bare
    /// `audioUrl` as a 64 kbps aacplus high-quality stream — same shape
    /// here. `streamURL` is nil when the metadata carried no audio, in
    /// which case the player steps over the ad.
    public func asTrack(stationId: String) -> Track {
        Track(
            trackToken: "ad.\(adToken)",
            title: title,
            artist: companyName,
            album: "",
            artworkUrl: imageURL,
            duration: 0,
            stationId: stationId,
            rating: .none,
            gain: 0,
            isAdvertisement: true,
            adToken: adToken,
            variants: audioURL.map {
                [AudioVariant(quality: .highQuality, encoding: "aacplus", bitrate: 64, url: $0)]
            } ?? []
        )
    }
}
