# Amphora

A personal, unofficial Pandora streaming client for iOS. Native Swift/SwiftUI,
built against Pandora's legacy JSON API (v5). Personal use only — not for
App Store distribution.

Feature parity targets the Pithos Linux client: stations, playback, thumbs
with reasons, bookmarks, history, background audio, lock-screen controls.

## Structure

- `PandoraCore/` — Swift package: protocol logic, crypto, session management.
  Pure, testable, no UI or AVFoundation.
- `Amphora/` — the iOS app target: `AppStore`, `PlayerService`, SwiftUI views.
- `project.yml` — xcodegen input; the `.xcodeproj` is generated on CI and
  never committed.

## Development

Builds run entirely on GitHub Actions (`Core Tests` on Linux,
`iOS Build` on macOS). Each green `iOS Build` uploads an unsigned
`Amphora-unsigned.ipa` artifact, installable via LiveContainer.
