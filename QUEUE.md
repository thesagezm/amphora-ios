# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M6** — performance & robustness. (M0–M5 code complete; M2 confirmed on
device 2026-10-23 "everything so far works". M3–M5 device check pending —
superseded by the crash report below.)

## User Feedback Pending

**2026-10-23 station-tuning request (this session's driver):**

> "there is an app called panedora… which has the ability to customise
> the station i.e deep cuts etc… is there anyway to allow the tuning of
> the station … everything should be for a free pandora account"

**Answer: yes — free accounts can tune stations.** Panedora's "Tune your
station" is Pandora's *listening modes* (My Mix / Deep Cuts / Crowd
Faves / Discovery / …). The endpoints live on the modern web API but
accept the **legacy session's `userAuthToken`** — pandoCast logs in with
the very same android-generic legacy flow Amphora uses and then drives
them (see Protocol Notes). Free accounts get every mode except the
`isPremiumOnly` one ("Artist Only", id 5). Core unit landed this push;
the app UI unit is next (Pending Queue item 3).

**2026-10-23 device report (prior session's driver; units A–C + lyrics
landed, device test still pending):**

1. **Crash**: "once I start to play a station it's only a matter of
   seconds before the app crashes LiveContainer". One song did show its
   artwork first. → Likely cause identified and fixed in `ArtworkCache`
   (see unit B below); crash capture added so the next report is
   precise (unit A).
2. **Song artwork not showing** in the player (station thumbnails and
   recently-played artwork are fine — same URL class, so the URL works;
   the player path was the broken one). → Unit B.
3. **"The mini player is very buggy as I switch tabs."** → Unit C.
4. **"Why are there no logs for the app… how will I paste what is
   happening?"** → Unit A (the app previously logged nothing at all).
5. **"Where are the lyrics working from?"** → They are not: the
   lrclib.net + translation core landed in `5ef40ab` but nothing in the
   app calls it. Lyrics UI is the next unit (see Pending Queue).

**Older resolved feedback:** mini-player covered the tab bar (`316b6c9`);
IPA missing `Payload/` (`4dd1fbf`); artwork never cached (base64 file
names, `a7dbe49`); sleep timer never fired (`a7dbe49`); bookmark buttons
gave no feedback (`a7dbe49`). M1/M2 confirmed on device 2026-10-23.

## In Flight / Last Push

**(this push — station-tuning UI, app target):**

- `AppStore`: `stationModes` / `isLoadingModes` / `isChangingMode` /
  `stationModeChangedTick` state; `isSubscriber` now set from
  `SessionManager` on restore + login; intents `loadStationModes`
  (sheet's `.task`, always refetches so the current mode is never
  stale) and `setStationMode(StationMode)`. On success: modes updated,
  tick bumped (sheet dismisses), "Tuned to X" confirmation, then
  `restartWithNewPlaylist` — a fresh `getPlaylist` + `player.play`
  ("changing modes starts a new song"; the queued tracks belonged to
  the old mode). Switching stations clears the cached modes.
  `StationModesError` mapped to short user copy.
- `TuneStationSheet` (new `Amphora/UI/`): modes list with the current
  mode checked, premium-only rows disabled with a "Premium" badge
  (free accounts can use everything else — Deep Cuts included),
  loading / unavailable (`interactiveRadioAvailable == false`, e.g.
  QuickMix) / error+Retry states, "Changing modes starts a new song."
  footer that becomes "Changing mode…" while in flight.
- `NowPlayingView`: slider-icon toolbar button opens the sheet next to
  the sleep timer.
- Local checks: all six touched app files parse-clean in Docker;
  PandoraCore untouched since the 161/161 run.

**(previous push — iOS Build repair, units B/C leftovers):** the iOS Build
had been red since the lyrics-UI push — two errors below the ones the
prior session was repairing when it ran out:

- `LyricsPanel.swift:87` — `activeIndex` was a `let` **inside** the
  LazyVStack's ViewBuilder but referenced by the ScrollView's
  `.onChange` (out of scope; the `(_, _)` Equatable errors were
  cascades). Hoisted the computation to the top of `syncedLyrics` with
  an explicit `return` — reading `elapsed` at that level is also what
  re-renders the panel as playback advances.
- `MainTabView.swift:40` — **`tabViewBottomAccessory` is an iOS 26 API**
  (Liquid-Glass floating tab bar, WWDC25), not iOS 18; CI is Xcode 16.4
  (iOS 18.4 SDK) → "has no member". Verified via GitHub code search
  (800+ users, all post-WWDC25) + superwall's backport. Rewritten:
  mini-player rides each tab's content as a bottom `safeAreaInset`
  (the proven 316b6c9 layout — `MiniPlayerInset`), while the
  **full-player sheet moved to `MainTabView`** (`MiniPlayer` now takes
  an `onOpen` closure instead of owning `@State` + `.sheet`). One sheet
  instance for the shell ⇒ tab switches no longer tear it down — the
  actual complaint behind "mini player is very buggy as I switch tabs",
  fixed without the unavailable API. Do not re-add
  `tabViewBottomAccessory` until the CI toolchain passes iOS 18.

**(previous push — station-tuning core + AppLog repair):**

- **Repair first (`4b60252`)**: iOS Build was red on the lyrics-unit-C
  push — `AppLog.startedAt` was `private` while `LogBuffer.store` (same
  file) references it; now `fileprivate`. The fix was found uncommitted
  in the tree and committed as-is.
- **Station tuning core (PandoraCore, `StationModes.swift` new)**:
  - `StationMode` / `StationModes` decode the `interactiveradio` reply
    (`modeId` number-or-digit-string, sparse flags defaulted, entries
    without id/name dropped, duplicate ids keep first, missing
    `availableModes` only valid when `interactiveRadioAvailable` is
    false, `errorCode`/`stat:fail` → malformed).
  - `PandoraModesClient`: POSTs plain JSON to
    `https://www.pandora.com/api/v1/interactiveradio/
    getAvailableModesSimple` (`{"stationId": …}`) and
    `setAndGetAvailableModes` (`{"stationId": …, "modeId": …,
    "previousModeId": …}`) with `X-AuthToken` (the **legacy**
    `userAuthToken`) + `X-CsrfToken` + browser-like headers;
    401/403 → fresh csrf → retry once → `.unauthorized`; 200 with an
    unmoved `currentModeId` → `.modeNotOffered`. `CookieCSRFProvider`
    bootstraps the `csrftoken` cookie (HEAD then GET on
    `https://www.pandora.com/`, pandoCast `EnsureCsrfTokenAsync`).
  - `SessionManager`: `getStationModes(for:)` /
    `setStationMode(_:for:previousModeID:)`; refuses premium-only modes
    on free accounts (`isSubscriber`) and unoffered modes **before any
    network**; `.unauthorized` → transparent re-login, retry once (same
    contract as the 1001 path).
  - Protocol evidence (both clients read from source this session):
    pandoCast (`lennyxc/PandoCast`, `PandoraRestApi.cs`) does the legacy
    android-generic login then calls these endpoints with that token and
    the numeric station id; Panedora (`MitchellBrovarnik/Panedora`,
    `pandora-api.js`) calls the same two endpoints from a web session
    and hard-codes id 5 / `isPremiumOnly` as the Premium gate. Free
    accounts can use the rest (Deep Cuts included).
  - Tests: 23 new (decoding 9, client 8, SessionManager facade 6) —
    **161/161 green** in Docker (`swift:6.0`).
- Remaining risk: iOS Build compiles PandoraCore under macOS Swift 6 —
  new code mirrors the proven `SessionBox`/`LogBuffer` patterns; still,
  verify the run before trusting it.

**(previous push — lyrics unit C, translation):**

- `AppStore`: after a successful synced-lyrics fetch,
  `translateIfNeeded` fires `GoogleTranslateClient.englishTranslation(of:)`
  (endpoint auto-detects the source language; `nil` = English → original
  stays). The translation is **non-blocking** — lyrics display first,
  `translation` fills in when it arrives. `translationTask` is cancelled on
  track change / superseding fetch; `applyTranslation` is guarded by line
  count (no shifting alignment) and only writes live state if the track is
  still current. The translated `Lyrics` replaces the cache entry, so
  repeat listens show translations instantly with no second call.
- `LyricsPanel`: `LyricLine.translation` renders under the original line,
  smaller and secondary (brighter on the active line).
- Local checks: both files parse-clean. (SwiftUI-surface type errors still
  CI-only.)

**(previous push — snprintf repair round 2 + lyrics unit B):**

- **iOS Build round 2 (`badf68f`) still red, one error**: `snprintf` in
  `CrashReporter.handleSignal` — C variadic functions are unavailable in
  Swift on **all** platforms (not a Linux quirk; round 1 masked it because
  the concurrency errors poisoned the file's type-check). The crash header
  is now built with Swift interpolation + `withCString`.
  - **New strongest local check**: the real file `-typecheck`s clean under
    `swiftc -swift-version 6` on Linux after an `import Darwin` →
    `import Glibc` sed plus small shims (`strlcpy`, `NSException`,
    `NSSetUncaughtExceptionHandler`). This catches name-lookup,
    unavailability, and concurrency errors `-parse` never sees — both red
    rounds would have been caught locally this way. Reusable: swap the
    import, append the shims from this session's history, typecheck.
- **Lyrics unit B landed** (app target) — the lyrics core is now called:
  - `AppStore`: `lyrics` / `isLoadingLyrics` state, per-`trackToken`
    cache (not-found cached too), fetch task cancelled + replaced on
    track change, hooked into `onTrackChanged`; `.refreshLyrics` intent
    for manual retry; provider injected (default `LRCLibClient`).
  - `Amphora/UI/LyricsPanel.swift` (new): synced lines auto-scroll with
    playback (`activeLineIndex(at: player.elapsed)`), active line
    highlighted, tap-to-seek; plain text scrolls; instrumental and
    not-found states, Retry on unavailable.
  - `NowPlayingView`: quote-bubble toolbar toggle swaps the
    artwork+scrubber region for `LyricsPanel`; transport/feedback stay.
  - Local checks: all three files parse-clean; CrashReporter now
    type-checks clean on Linux. LyricsPanel/NowPlayingView type errors
    (SwiftUI) still only surface on CI.

**(previous pushes):** CI repair round 1 (`badf68f`, strict-concurrency in
CrashReporter); units A–C of the crash/feedback round (`883f636` — logging,
crash capture, Diagnostics screen, bounded artwork decode, single
mini-player); lyrics core `5ef40ab`.

**Units A–C detail (from `883f636`):**

- **Unit A — logging + crash capture + Diagnostics screen.** The app had
  zero logging (grep: no `Logger`/`print`/`NSLog` anywhere), so a device
  crash left nothing to paste.
  - `Amphora/Support/AppLog.swift` (new): `os.Logger` per category
    (subsystem `dev.personal.amphora`) + a 400-line in-memory ring
    buffer + a disk mirror (`Application Support/Amphora/amphora.log`,
    debounced 2 s flush) + a raw-memory tail for the crash handler.
    Lines carry seconds-since-launch. **Redaction contract:** URLs are
    logged scheme+host+path only — never the signed query; no tokens.
  - `Amphora/Support/CrashReporter.swift` (new): signal handlers
    (SIGABRT/ILL/SEGV/BUS/FPE/TRAP) write a header + log tail with
    async-signal-safe calls only, then re-raise so iOS still records its
    crash; `NSSetUncaughtExceptionHandler` records NSException name/
    reason/stack (and marks the report so the following SIGABRT doesn't
    overwrite it). The next launch reads `last-crash.txt` back before
    resetting it.
  - `Amphora/UI/DiagnosticsView.swift` (new): last crash + device info +
    log, with Copy (clipboard) and Share. Opened from the **stethoscope
    toolbar button on the Stations tab**. This is how the user pastes
    what happened.
  - Instrumented: `AppStore` (restore, station list, play, prefetch,
    track start, errors), `PlayerService` (state transitions, item
    failure, interruption/route, media-services reset), `NowPlayingService`
    (track change, artwork applied), `AmphoraApp` (launch).
- **Unit B — artwork robustness (`ArtworkCache` rework).** Primary crash
  suspect: every artwork was decoded at full source size
  (`UIImage(data:)`); Pandora song art can be far larger than any slot
  shows it, the player holds several decoded copies at once (mini player,
  full player, lock screen), and the spike right after pressing play fits
  the "crashes within seconds" report in LiveContainer's tighter memory
  budget.
  - All decodes now go through ImageIO's thumbnail API capped at 1200 px
    (`kCGImageSourceThumbnailMaxPixelSize`) — a bounded bitmap, never a
    full-size one (disk reads included).
  - Fetch tries **candidate URLs** in order: the normalized HTTPS form
    first, then the raw URL as-is if distinct; every attempt is logged
    (status/bytes/decoded size/failure) so "song artwork not showing"
    becomes diagnosable from the log.
  - `image(for:)` now takes the **raw URL string** and normalizes
    internally; callers (`CachedArtwork`, `NowPlayingService`) simplified.
- **Unit C — mini-player is now one instance** (`MainTabView`): replaced
  the per-tab `safeAreaInset` (three `MiniPlayer` instances, each with
  its own sheet state, torn down on every tab switch, stacked insets with
  the station error banner) with **`tabViewBottomAccessory`** (iOS 18):
  one player, system-laid-out above the tab bar on every tab.

**(previous push, `03648ae`/`c658c40`):** handover bookkeeping; both
workflows green. Lyrics core (`5ef40ab`) — LRC parser, `LRCLibClient`,
`GoogleTranslateClient`, 24 tests — **nothing calls it yet**.

## Pending Queue

1. Verify this push green (Core Tests + iOS Build). Repair first if red.
2. **User device test of the latest IPA** — the critical one: play a
   station for >30 s (crash?), song artwork in mini player + full player,
   tab switching with the mini player (full-player sheet now survives
   tab switches), lyrics panel (quote-bubble toggle — synced scroll,
   tap-to-seek, translation under non-English lines), **Tune Station
   (slider icon in the full player): modes load, picking Deep Cuts
   starts a new song from the tuned station, QuickMix shows "no tuning
   options"**, then **open Diagnostics (stethoscope, Stations toolbar)
   → Copy → paste the log** if anything is still wrong. If the app
   crashed and relaunched, the "Last crash" section is already filled
   in.
3. App icon (no asset catalog; `ASSETCATALOG_COMPILER_APPICON_NAME: ""`).
4. Beautify pass (theme, typography, gradients).
5. Session-expiry surfacing + ad handling (protocol notes at the bottom).

**FIRST ACTION next session:** `gh run list --limit 5`. If red, read the
failure summary annotation and repair before any new unit.

## Session handover (2026-10-23, second session)

**State:** units A–C pushed on this session's last commit; local checks
green before push: `swiftc -parse` clean over the whole app target,
PandoraCore **138/138** in Docker (`swift:6.0`). Working tree clean.

**Why the crash is (probably) artwork memory — reasoning chain:**
station thumbnails and history artwork work (small slots, same URL
class); song artwork "not showing" but one appeared right before the
crash; crash is seconds after playback starts — i.e. when the current
track's artwork finishes downloading and several consumers decode it at
full size simultaneously. Unit B removes the full-size decode entirely
and Unit A makes the next failure (if it is something else) pasteable.
**Do not assume it is fixed** — the device test in Pending Queue item 4
decides.

**Not done yet:** lyrics UI (items 2–3 above), app icon, beautify pass,
session-expiry surfacing, ad handling.

**Traps that cost cycles before (still apply):**

- App-target type errors only surface on CI — `swiftc -parse` catches
  syntax only. Keep app-target changes small and idiomatic (`some View`,
  never bare `View`; explicit `Self.` for static members called from
  instance context).
- Swift 6: extract notification payload values before hopping to
  `@MainActor`; `@Observable` callback properties are arrays and use
  `.append`; NSLock only inside sync helpers.
- PandoraCore must stay Linux-buildable: **no `os`/`AppLog` in the core
  package** — logging lives in the app target only.
- Never log URLs with their query (signed tokens) — `AppLog.redactedURL`.
- lrclib answers **503** when busy — retry, don't error.
- The `[offset:]` LRC tag is milliseconds, shifts lyrics earlier for
  positive values.

## Milestones

- [x] **M0** — skeleton, green CI
- [x] **M1** — auth — confirmed on device 2026-10-23
- [x] **M2** — stations — confirmed on device 2026-10-23
- [x] **M3** — playback — code complete, device check pending
- [x] **M4** — feedback & bookmarks (+ history) — code complete, device
      check pending
- [x] **M5** — UI/design pass (artwork cache, sleep timer, tab shell,
      station ordering, mini-player shell) — device check pending
- [ ] **M6** — performance & robustness (lyrics core landed; lyrics UI,
      session-expiry surfacing, ad handling remain; crash triage in
      progress this session)

## Completed Units (condensed; full detail in git log)

- **M0** `1ec069e` skeleton; **M1** crypto/URL/session/login
  (`890933c`…`4ebb29e`); **M2** stations core+UI+CRUD+search
  (`10abb9c`…`74472e0`); **M3** playlist core, `PlayerService`, Now
  Playing + remote commands (`396258c`…`cefeb2f`); **M4** feedback/
  bookmarks core+UI, history (`ed4b9bc`…`c131620`); **M5** artwork cache,
  sleep timer, tab shell, station ordering, mini-player placement
  (`efcd062`…`f39c4b2`); **M6** fixes (mini-player/tab bar `316b6c9`,
  artwork cache/sleep timer/bookmarks `a7dbe49` + repair `03e89ff`),
  lyrics core `5ef40ab`.
- **This session:** units A–C above (logging/crash capture/Diagnostics,
  artwork bounded decode + candidates + logging, single mini-player
  accessory).

## Protocol Notes (reference-verified)

- **Listening modes (station tuning)** — modern web API, plain JSON (no
  Blowfish), verified from pandoCast `PandoraRestApi.cs` and Panedora
  `pandora-api.js`:
  - `POST https://www.pandora.com/api/v1/interactiveradio/
    getAvailableModesSimple` body `{"stationId": "<numeric stationId>"}`
    → `{interactiveRadioAvailable, currentModeId, availableModes:
    [{modeId, modeName, modeDescription, isModeAvailable,
    isPremiumOnly}], availableModesHeader, hasTakeoverModes, …}`.
  - `POST …/setAndGetAvailableModes` body `{"stationId": …, "modeId":
    n, "previousModeId": n}` (panedora omits `previousModeId`; optional)
    → same reply shape. Pandora can answer 200 while keeping the old
    mode — re-check `currentModeId`.
  - Auth: header `X-AuthToken: <legacy userAuthToken>` — pandoCast
    obtains it from the legacy android-generic `auth.userLogin` and
    calls these endpoints with it; the numeric `stationId` is shared by
    both API generations. CSRF: `X-CsrfToken` = the `csrftoken` cookie
    from `https://www.pandora.com/` (HEAD, then GET); on 401/403
    re-bootstrap the cookie and retry once.
  - Free accounts: all modes except `isPremiumOnly` (id 5 "Artist
    Only" — panedora also hard-codes id 5 when the flag is missing).
    `interactiveRadioAvailable: false` → station cannot be tuned
    (e.g. QuickMix).
- Request encryption: zero-pad each partial 8-byte chunk → Blowfish-ECB
  with `encryptKey` → hex (`pithos.pandora.json_call`, `blowfish=True`).
  Not PKCS — trailing zeros are never stripped on decrypt.
- `syncTime` in `auth.partnerLogin` is hex ciphertext; decrypt with
  `decryptKey`, strip padding, bytes `[4:14]` are the 10-digit Pandora
  timestamp; `time_offset = pandora_time - now`.
- `auth.userLogin` body: `username`, `password`, `loginType: "user"`,
  `returnIsSubscriber: true` — encrypted; carries the partner/user auth
  token when present, plus `syncTime`.
- **Skip limits are NOT exposed as a numeric field by any reference**
  (pithos, pydora, libpiano, gopiano, PandoraSharp, sonos-http-api).
  Implement as server-fault detection on `station.getPlaylist`
  (`PLAYLIST_END`, `DAILY_SKIP_LIMIT_REACHED` — Elpis `Station.cs:232`).
- **Explicit content is an account-level filter** (`user.getSettings` →
  `isExplicitContentFilterEnabled`), not a per-item flag — a badge has no
  protocol source.
- **Ads**: an entry with `adToken` is an ad (pydora `is_ad`); resolution
  is `ad.getAdMetadata` + `ad.registerAd` (pydora). Amphora keeps ads in
  the playlist and flags them; neither resolves nor registers yet.
- Station `allow*` flags exist on the wire (pydora); Amphora hard-codes
  the pithos rule (quickmix/thumbprint not renameable/deletable).
