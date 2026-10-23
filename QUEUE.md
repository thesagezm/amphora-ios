# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M3** — Playback: `station.getPlaylist` core → `PlayerService`/`AVPlayer`
→ background audio, Now Playing, remote commands, prefetch next.
(M0 ✅, M1 ✅, M2 ✅ — user confirmed "everything so far works" 2026-10-23.)

## User Feedback Pending

_(none)_

**Resolved feedback:**

1. **"Installing Amphora: error — the folder 'payload' doesn't exist"**
   (2026-10-23, LiveContainer) — fixed by `4dd1fbf`: zip `Payload` from the
   workspace root; artifact `amphora-ipa-10` verified to contain
   `Payload/Amphora.app/…`. **User then signed in on device — install
   confirmed working.**
2. **M1 confirmed on device** (2026-10-23): user reports real sign-in
   succeeded and app shows the signed-in placeholder. **M1 milestone
   complete.**
3. **M2 confirmed** (2026-10-23): "everything so far works" — station list,
   rename/delete, add-station search all good on device. **M2 complete.**

## In Flight / Last Push

- **This push (2026-10-23): M5 unit 2 — sleep timer**:
  - `SleepTimer.swift` (new, PandoraCore): `SleepTimer` with `off` /
    `duration` / `endOfTrack` modes, deadline math, remaining minutes and
    a UI label. `SleepTimerTests`: 9 tests (expiry, countdown, clamping,
    end-of-track, fired, off state, labels, Codable round-trip).
  - `AppStore`: `setSleepTimer` / `cancelSleepTimer` intents; an
    end-of-track timer pauses playback when the track changes; an expired
    duration timer stops playback.
  - `SleepTimerSheet` (new `Amphora/UI/`): 15/30/45/60/90 minutes,
    "End of current track", cancel; opened from the Now Playing toolbar
    (moon icon shows filled while a timer is set).

- **391aae8** (2026-10-23): repair red iOS Build from M5 unit 1 —
  **Core Tests ✅** (39936912918), **iOS Build ✅** (39936912923):
  - `HistoryView` used `store.history.isEmpty` and `List(store.history)`,
    but `PlayHistory` is a plain struct, not a collection. Fixed to
    `store.history.entries` / `store.history.items`; `PlayHistory` also
    grew `isEmpty`, `count` and `items` accessors.

- **efcd062** (2026-10-23): M5 unit 1 — artwork cache**:
  - `ArtworkCache.swift` (new `Amphora/Persistence/`): an actor with a
    memory tier (NSCache of decoded images, 64 MB budget) and a disk tier
    (raw bytes in Caches); concurrent requests for the same URL share one
    in-flight fetch, so a list scroll never re-downloads artwork.
  - `CachedArtwork.swift` (new `Amphora/UI/`): the view all artwork
    slots use — placeholder while loading, fallback icon on failure, the
    load is cancelled when the view disappears.
  - `StationsView`, `MiniPlayer`, `BookmarksView`, `HistoryView`,
    `NowPlayingView` now use the cached artwork instead of `AsyncImage`
    (which re-fetched on every list render).

- **c131620** (2026-10-23): M4 unit 3 — playback history ("recently
  played")**:
  - `HistoryStore.swift` (new, PandoraCore): `PlayHistory` — a bounded
    (100 entries), newest-first list of plays; a repeated track moves to
    the front instead of duplicating; `Codable` for disk persistence.
    `PlayHistoryTests`: 5 tests (order, de-dup, capacity, metadata,
    Codable round-trip).
  - `Amphora/Persistence/HistoryStore.swift` (new): JSON file in
    Application Support (`Amphora/history.json`); missing/unreadable file
    ⇒ empty history, saves are best-effort.
  - `AppStore`: loads the history at launch and records every track the
    player starts.
  - `HistoryView` (new `Amphora/UI/`): recently-played list with artwork,
    artist caption and relative time.
  - `RootView`: a "More" menu in the toolbar (Bookmarks / Recently Played).

- **39746b8** (2026-10-23): M4 unit 2 — feedback + bookmarks UI**
  (app target):
  - `AppStore`: `rateCurrentTrack` / `removeCurrentRating` /
    `sleepCurrentTrack` / `bookmarkCurrentSong` /
    `bookmarkCurrentArtist` / `refreshBookmarks` / `deleteBookmark`
    intents; the current track's rating is tracked per track (the
    `feedbackId` belongs to the song — pithos' `Song.rate` deletes the
    old feedback before adding a new one); the rating is seeded from the
    playlist entry's `songRating`.
  - `PlayerService.onTrackChanged` / `onPlaybackStateChanged` are now
    **lists** of observers (the now-playing service and the store both
    subscribe — neither may overwrite the other).
  - `FeedbackBar` (new): thumbs up / thumbs down / hide-this-song; the
    active rating is highlighted and tapping it again removes the rating.
  - `BookmarksView` (new): song + artist bookmark lists with delete,
    pull-to-refresh; reachable from the toolbar bookmark icon.
  - `NowPlayingView`: feedback bar + bookmark song/artist buttons.

- **ed4b9bc** (2026-10-23): M4 unit 1 — feedback + bookmarks core —
  **Core Tests ✅** (39934322752), **iOS Build ✅** (39934322742):
  - `Feedback.swift` (new): `FeedbackRating` (loved/banned/none),
    `FeedbackReceipt` (the `feedbackId` needed to undo a rating),
    `Bookmark` (song/artist bookmarks with `bookmarkToken`, `musicToken`,
    artist/song/album names, art, `dateCreated`).
  - `SessionManager`: `addFeedback` (`station.addFeedback` with
    `trackToken` + `stationToken` + `isPositive`), `deleteFeedback`
    (`station.deleteFeedback`), `sleepSong` (`user.sleepSong`),
    `getBookmarks` (`user.getBookmarks`), `addSongBookmark` /
    `addArtistBookmark` / `deleteSongBookmark` / `deleteArtistBookmark`.
  - **Protocol note:** the legacy v5 API has **no "why"/reason parameter**
    for dislikes in any reference (pithos, pydora, libpiano, PandoraSharp,
    gopiano, volumio, sonos-http-api all send only `isPositive`). Amphora
    therefore does not invent a reason field — the "why" reason list is
    out of scope until a reference documents it.
  - `FeedbackTests`: 8 tests (thumbs up/down request shape, missing
    feedbackId → malformed, delete shape, sleep shape, bookmarks
    decoding, malformed bookmark skip, add/delete bookmark endpoints).
  - **Local Docker Swift 6.0.3 run: 93/93 tests green.**

- **cefeb2f** (2026-10-23): repair red iOS Build from M3 unit 3 —
  **Core Tests ✅** (39931996059), **iOS Build ✅** (39931995916):
  - `MiniPlayer.swift` — `private var fallbackIcon: View` (an existential)
    was passed to `AsyncImage`'s `placeholder:` closure, which needs a
    concrete `View`. Fixed to `some View`. (Lesson: never type a SwiftUI
    helper as bare `View` — use `some View`.)
  - `AppStore.player` is now an explicitly initialized `let` so the
    `NowPlayingService` wiring is unambiguous.

- **f919e24** (2026-10-23): M3 unit 3 — Now Playing + remote commands —
  **Core Tests ✅** (39931443915), **iOS Build ❌** (39931443965 — the
  `fallbackIcon: View` error above):
  - `NowPlayingService` (new `Amphora/Player/`): publishes title/artist/
    album/duration/elapsed/rate to `MPNowPlayingInfoCenter`, loads lock-screen
    artwork off the main actor, wires `MPRemoteCommandCenter` (play, pause,
    toggle, next, ±15 s, scrub) to the player.
  - `PlayerService`: `skipForward` / `skipBackward` / `seek`, plus
    `onTrackChanged` / `onPlaybackStateChanged` hooks.
  - `NowPlayingView` (new `Amphora/UI/`): artwork, title/artist/album,
    scrubber with times, transport controls; opened from the mini-player.

- **24d8464** (2026-10-23): M3 unit 2 — `PlayerService` + tap-to-play —
  **Core Tests ✅** (39929262651), **iOS Build ❌** (39929262603 — the
  same `fallbackIcon: View` error, repaired in `cefeb2f`):
  - `PlayerService` (real implementation now): `AVQueuePlayer` with a
    two-slot queue (current + prefetched next → near-gapless hand-over),
    `AVAudioSession(.playback, .default)` activation, `preferredForwardBufferDuration
    = 30`, periodic time observer (0.5s) for elapsed time, KVO on
    `timeControlStatus` for play/pause/buffering state.
  - Interruption / route-change / `mediaServicesWereReset` handling:
    pause on interruption, resume when `.shouldResume`, re-activate the
    session on route changes, rebuild the player + queue after a media
    services reset.
  - `AppStore`: `playStation` / `togglePlayback` / `skipToNext` intents,
    `currentStation`, `isLoadingPlaylist`; `play` fetches the playlist,
    starts the first playable track and prefetches the next; the player's
    "queue running low" callback fetches the next playlist (pithos
    preloads when one song remains) and queues only unseen tracks.
  - `StationsView`: tapping a station plays it (tapping the playing
    station toggles), "now playing" indicator on the active row.
  - `MiniPlayer` (new): compact bar with artwork, title/artist, play/pause
    and next, shown above the tab bar while something plays.

- **396258c** (2026-10-23): M3 unit 1 — `station.getPlaylist` core —
  **Core Tests ✅** (39927947866), **iOS Build ✅** (39927948033):
  - `Playlist.swift` (new): `Track` (token, title, artist, album, artwork,
    duration, station id, rating, gain, ad flag) + `AudioVariant`
    (quality bucket, encoding, bitrate, URL) + `Playlist` (tracks + fetched
    time, 1h validity per pithos `PLAYLIST_VALIDITY_TIME`).
  - Quality selection mirrors both references: pithos' promotion rule —
    the extra `HTTP_128_MP3` URL becomes the new `highQuality` when the
    server's high quality is < 128 kbps (old high → `mediumQuality`),
    otherwise the extra `HTTP_32_AACPLUS` becomes a `lowQuality` fallback;
    pydora's `AudioField` — a bare `audioUrl` with no map is treated as
    64 kbps aacplus high quality. Variants are ordered best-quality first.
  - Entries without `songName` are dropped (pithos' filter); ads are kept
    and flagged (`adToken` → `isAdvertisement`).
  - `SessionManager.getPlaylist(for:)` — `station.getPlaylist` with pithos'
    exact params (`stationToken`, `includeTrackLength: true`,
    `additionalAudioUrl: 'HTTP_32_AACPLUS,HTTP_128_MP3'`).
  - `PlaylistTests`: 10 tests (full entry, songName filter, non-object
    entries, both promotion branches, bare URL, no-audio entry, variant
    ordering, 1h expiry, request shape + encrypted-body asserts).
  - **Local Docker Swift 6.0.3 run: 85/85 tests green** (the `swift:6.0`
    image on this workstation — same toolchain as the CI Linux runner).

- **71cbad7** (2026-10-23): M2 unit 6 — add-station sheet UI (search/create
  intents, debounced `AddStationView`). Both workflows ✅ (39886272967 /
  39886272956).

- **b0f4526** (2026-10-23): **repair red music.search push** —
  **Core Tests ✅** (39885481763), **iOS Build ✅** (39885481856):
  - `ab4e887` (runs 39884553000 / 39884553004) **and** the QUEUE-only
    follow-up `6641ace` (39884917062 / 39884916740): **both red, same
    compile error in both workflows** — `MusicSearch.swift:67/71` passed
    `AnyJSON` array elements where `artistOrSong` takes
    `[String: AnyJSON]`. Fixed via `entry.objectValue.flatMap(…)`.
    (Lesson: array elements are `AnyJSON`; unwrap with `objectValue`.)


- `6641ace` (2026-10-23): QUEUE-only bookkeeping for the green
  row-actions run.

- **This push (2026-10-23): M2 unit 5 — `music.search` core**
  (runs 39884553000/39884553004 queued at push; verify first next session):
  - `MusicSearchResult` (new `MusicSearch.swift`): `kind`
    (artist/song/genre), `score`, `musicToken`, `title`, `subtitle`;
    `searchResults(from:)` mirrors pithos `Pandora.search()` — artist/song
    kept at score ≥ 80, genreStations passed through, merged and sorted
    score-desc with original merge order as tiebreak (pithos leans on
    Python's stable sort); malformed entries dropped, not fatal.
  - `SessionManager.search(_:)` — `music.search` with pithos' exact params
    (`includeGenreStations`, `includeNearMatches`, `searchText`); new
    `PandoraAPI.Method.musicSearch`.
  - `MusicSearchTests`: 5 parsing tests (filter, tie stability, field
    mapping, malformed-skip, empty) + request-shape test (restore path,
    one call, NUL-trimmed body asserts).

- `74472e0` (2026-10-23): **M2 unit 4 — station row actions UI** —
  **Core Tests ✅** (39883344481), **iOS Build ✅** (39883344520).
  - `AppStore`: `renameStation`/`deleteStation` intents →
    `SessionManager` calls; rename trims + rejects empty, reloads list
    for sort order; delete removes locally by id; `isMutatingStations`
    guard against overlapping mutations; errors via `userMessage`.
  - `StationsView`: long-press context menu (Rename / Delete — hidden for
    quickmix + thumbprint, matching pithos' StationsDialog filter), rename
    alert with text field, destructive confirm for delete, error banner
    safe-area inset for post-load failures (M5 restyles).

- `a6a6f59` (2026-10-23): repair Core Tests after CRUD core — covered
  green by the `74472e0` run above:
  - `797c2a0`: **iOS Build ✅** (39882133244), **Core Tests ❌**
    (39882133242) — 5 failures, all `missing id field partnerId`: the new
    CRUD tests scripted only the operation reply, but `login()` consumes
    two responses first (partner + user). Prepended `partnerOK()` +
    `userOK()` to all five fixtures; expected request counts already
    assumed partner+user+op, so they now match.

- `797c2a0` (2026-10-23): **M2 unit 3 — stations CRUD core** (PandoraCore).
  - `SessionManager`: `createStation(musicToken:)` and
    `createStation(trackToken:musicType:)` (pithos `add_station_by_music_id`
    / `add_station_by_track_token`), `renameStation(_:to:)` — transforms a
    shared station first (`station.transformSharedStation`, pithos
    `transformIfShared`), no-op when the name is unchanged — and
    `deleteStation(_:)` (list membership only, like pithos).
    `Station(result:)` decodes the `createStation` reply (same wire shape
    as list entries). New `PandoraAPI.Method` constants.
  - 5 new tests: create×2 (params asserted in decrypted bodies, NUL-trimmed
    helper), rename shared→transform-then-rename ordering, personal skip +
    same-name no-op, delete token.

- `46276e4` (2026-10-23): **M2 unit 2 — stations list UI** (runs 39882019409
  / 39882019499 in flight at this push; verify first next session):
  - `AppStore`: `stations` / `isLoadingStations` state, `refreshStations`
    intent (guarded against concurrent loads); auto-refresh after login
    success and after warm-launch restore; error kept only when the list
    is empty (keeps a loaded list usable on background refetch failure).
  - `StationsView` (new `Amphora/UI/`): plain `List` + `refreshable`
    pull-to-refresh; rows = 52pt artwork (`AsyncImage`, URLCache until the
    dedicated cache lands in M6) + name + badges (QuickMix shuffle icon /
    "Quick mix", "Thumbprint station", shared `person.2` icon);
    44pt rows, combined VoiceOver elements. Sorting: QuickMix pinned first,
    then case-insensitive name, id tiebreak (stable across reloads).
    Empty (`ContentUnavailableView`), loading, and error+Retry states.
  - `RootView`: signed-in phase now hosts `NavigationStack { StationsView() }`
    (placeholder removed).

- `7b602fe` (2026-10-23): repair Core Tests after station-list core —
  **Core Tests ✅** (39881169360), **iOS Build ✅** (39881169362). Cause:
  `StationTests` fixture assembled from split string literals had a doubled
  comma → undecodable envelope; now one literal.

- `10abb9c` (2026-10-23): **M2 unit 1 — station list core**. PandoraCore
  only:
  - `Station`/`StationList` models (`Station.swift`): wire keys from
    pithos `Station.__init__` (required: `stationId`, `stationToken`,
    `stationName`, `isShared`, `isQuickMix`, `quickMixStationIds`) +
    pydora's optional set (`artUrl`, `isThumbprint`, `isGenreStation`,
    allow* flags, `checksum`). String-or-number ids; sparse/minimal
    stations decode with defaults; `Identifiable` for SwiftUI.
  - `SessionManager.getStationList()` — `user.getStationList` with
    `returnAllStations=true` (pithos `get_stations`) +
    `includeStationArtUrl=true` (pydora), via `authenticatedRequest`
    (1001 retry-once applies). New `PandoraAPI.Method.getStationList`.
  - Tests: 4 StationTests (full/minimal/quickmix ids/typed error) +
    2 SessionManagerTests (params+encrypted-body assert with NUL-trim;
    1001 re-auth replay) + requires-session.

- `4ebb29e` (2026-10-23): **M1 SessionRecord store tests** —
  **Core Tests ✅** (39877281790), **iOS Build ✅** (39877281785).

- `fcbb245` (2026-10-23): **M1 login screen** — **Core Tests ✅**
  (39876459087), **iOS Build ✅** (39876459009).
  - `KeychainSessionStore` (`Amphora/Persistence/`): `SessionStore` conformance
    over the existing `KeychainStore` — JSON-encodes `SessionRecord`, missing
    or undecodable item ⇒ `nil` (fail closed to login screen).
  - `AppStore`: `AuthPhase` (restoring/signedOut/signingIn/signedIn),
    intents `restoreSession` / `login` / `dismissError`; login runs
    `SessionManager.login` off the UI's control flow (Task), maps typed
    PandoraCore errors (PandoraAPIError copy, transport, malformed,
    SessionManagerError) to short safe strings — no credentials/tokens in
    messages. Idempotent warm-launch `restoreSession` (zero network).
  - `LoginView` (new `Amphora/UI/`): email + password, focus chain,
    submit-on-return, in-flight spinner + disabled button, error text,
    44pt target, VoiceOver labels. No networking in the view — intents only.
  - `RootView`: switches on `authPhase` (restoring spinner → LoginView →
    signed-in placeholder for M2 station list); fires `restoreSession`
    once via `.task`.

## Current Milestone

**M3** — Playback (see top of file).

## Pending Queue

1. Verify this push green (Core Tests + iOS Build). Repair first if red.
2. **M5 unit 3** — design pass: tab bar (Stations / Bookmarks / History
   tabs instead of the "More" menu), empty/error state polish, station
   ordering persistence.
3. **M6** — robustness: offline/error copy, session-expiry surface
   (1001 → re-login → retry, already in `SessionManager`), long-session
   soak.
4. **User re-test** the IPA: play a station, lock-screen metadata, thumbs
   up/down, skip, backgrounding, bookmarks, sleep timer.

**FIRST ACTION next session:** `gh run list --limit 5`. If Core Tests is
red on this push, read the failure summary annotation and repair before
any new unit.

## Milestones

- [x] **M0** — skeleton, green CI
- [x] **M1** — auth (partner login, Blowfish, user login, Keychain, auto-login)
      — confirmed signed-in on device 2026-10-23
- [x] **M2** — stations (fetch/list/create/rename/delete + list UI)
      — confirmed on device 2026-10-23 ("everything so far works")
- [x] **M3** — playback (playlist, AVPlayer, background audio, Now Playing,
      remote commands, prefetch) — code complete, user device check pending
- [x] **M4** — feedback & bookmarks (+ playback history) — code complete,
      user device check pending
- [ ] **M5** — UI/design pass (artwork cache + sleep timer landed; tab bar
      and state polish remain)
- [ ] **M6** — performance & robustness

## Completed Units

- **M0 repo skeleton** — commit `1ec069e`: Amphora app target (AppStore,
  PlayerService, KeychainStore skeletons), PandoraCore package
  (`PandoraAPI` + `PandoraAPIClient`), `project.yml`, both CI workflows,
  `QUEUE.md`, README, `.gitignore`. Both workflows green on first run.
- **M1 constants** — commit `890933c`: partner password corrected,
  `encryptKey`/`decryptKey` added from `pithos/pandora/data.py`.
- **M1 crypto** — commit `a852955`: Blowfish-ECB + known-answer vectors;
  Core Tests 39816015922 ✅, iOS Build 39816015943 ✅.
- **M1 URLBuilder** — commit `61027a1`: sorted-key JSON bodies, pithos
  query order, syncTime/token injection, per-method encrypt flag.
  Initially red (static-member escape call); repaired in this push.
- **M1 partner transport** — `c239d0f`: typed errors, envelope decoding,
  `LegacyPandoraClient` with mock-transport tests; workflow failure
  summaries + pipefail fix. Repaired by `dd0c0d5` (bash shell + AnyJSON
  Codable); that push's own Core Tests red (URLSession/Linux) repaired by
  the SessionManager push.
- **M1 SessionManager** — `6139d4c`: actor with pithos-connect flow,
  `restore()`, 1001 retry-once, `SessionStore`/`InMemorySessionStore`,
  12 tests, syncTime fixtures. iOS Build ✅; Core Tests red (NSLock-noasync
  in MockTransport) — repaired by `a48f70e`.
- **Core Tests repair** — `a48f70e`: locked MockTransport work moved into a
  sync helper (Swift 6 `noasync` NSLock). Then 2 assertion failures →
  `83af041`: NUL-trim the decrypted-body assert (per-chunk pad survives);
  assert `baseURL.absoluteString` (`URL.path` drops the trailing slash on
  Linux Foundation). Both workflows green after `83af041`.
- **IPA packaging fix** — `4dd1fbf` (user report): zip `Payload` from the
  workspace root so the archive contains `Payload/Amphora.app/…`.
  Verified on artifact `amphora-ipa-10`; both workflows green.
- **M1 login screen** — `fcbb245`: `KeychainSessionStore`, `AppStore`
  auth phases/intents, `LoginView`, warm-launch restore. Both ✅;
  user signed in on device.
- **M1 SessionRecord tests** — `4ebb29e`: Codable round-trip, fixed-JSON
  fixture (guards stored-session compat), InMemory save/load/clear.
  Both ✅.

## Protocol Notes (reference-verified)

- Request encryption: zero-pad each partial 8-byte chunk (aligned inputs gain
  no extra block) → Blowfish-ECB with `encryptKey` → hex string. Applied to
  the JSON request body (`pithos.pandora.json_call`, `blowfish=True`).
  Not PKCS — trailing zeros are never stripped on decrypt.
- `syncTime` in `auth.partnerLogin` response is hex-encoded ciphertext;
  decrypt with `decryptKey`, strip padding, take bytes `[4:14]` as the
  10-digit Pandora timestamp; `time_offset = pandora_time - now`.
- `auth.userLogin` body: `username`, `password`, `loginType: "user"`,
  `returnIsSubscriber: true` — encrypted; also carries `partnerAuthToken`
  or `userAuthToken` when present, plus `syncTime`.
