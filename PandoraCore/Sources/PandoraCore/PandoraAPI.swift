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
/// Every value here is taken from the reference implementation
/// (`pithos/pandora/data.py`, `android-generic` client entry) rather than
/// guessed. Methods that vary per request are declared on `PandoraAPIClient`.
public enum PandoraAPI {

    /// Hostname of the legacy JSON-RPC endpoint. Pandora has no separate TLS
    /// path: every call is a TLS-encrypted POST to this host.
    public static let baseURL = URL(string: "https://tuner.pandora.com/services/json/")!

    /// The `method` values this client issues.
    public enum Method {
        public static let partnerLogin = "auth.partnerLogin"
        public static let userLogin = "auth.userLogin"
        public static let getStationList = "user.getStationList"
        public static let createStation = "station.createStation"
        public static let renameStation = "station.renameStation"
        public static let deleteStation = "station.deleteStation"
        public static let transformSharedStation = "station.transformSharedStation"
        public static let musicSearch = "music.search"
        public static let getGenreStations = "station.getGenreStations"
        public static let getPlaylist = "station.getPlaylist"
        public static let addFeedback = "station.addFeedback"
        public static let deleteFeedback = "station.deleteFeedback"
        public static let getBookmarks = "user.getBookmarks"
        public static let addSongBookmark = "bookmark.addSongBookmark"
        public static let addArtistBookmark = "bookmark.addArtistBookmark"
        public static let deleteSongBookmark = "bookmark.deleteSongBookmark"
        public static let deleteArtistBookmark = "bookmark.deleteArtistBookmark"
        public static let sleepSong = "user.sleepSong"
        public static let getAdMetadata = "ad.getAdMetadata"
        public static let registerAd = "ad.registerAd"
    }

    /// Extra stream formats requested alongside a playlist, in the order
    /// pithos asks for them: `additionalAudioUrl[0]` = 32 kbps AAC+,
    /// `additionalAudioUrl[1]` = 128 kbps MP3.
    public static let additionalAudioURLs = "HTTP_32_AACPLUS,HTTP_128_MP3"

    /// Client-side identity used by `auth.partnerLogin`, matching the
    /// `android-generic` entry in `pithos/pandora/data.py`.
    public static let partnerUsername = "android"
    public static let partnerPassword = "AC7IBG09A3DTSYM4R41UJWL07VLN8JI7"
    public static let partnerDeviceModel = "android-generic"
    public static let version = "5"

    /// Blowfish key used to *encode* request bodies (password encryption,
    /// `station.getPlaylist` payload). Source: `encryptKey`,
    /// `pithos/pandora/data.py`.
    public static let encryptKey = "6#26FRL$ZWD"

    /// Blowfish key used to *decode* server responses (`syncTime`).
    /// Source: `decryptKey`, `pithos/pandora/data.py`.
    public static let decryptKey = "R=U!LH$O2B#"
}
