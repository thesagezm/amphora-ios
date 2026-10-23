# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M6** — performance & robustness. (M0–M5 code complete; M2 confirmed on
device 2026-10-23 "everything so far works". M3–M5 device check pending —
superseded by the crash report below.)

## User Feedback Pending

**2026-10-23 device report (this session's driver, top priority):**

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

**(this push — units A, B, C of the crash/feedback round):**

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
2. **Lyrics unit B (app target)** — wire the core in: `AppStore` gains
   `lyrics` state + a fetch keyed by `track.trackToken` (run from the
   track-changed path, cached per track, `LRCLibClient` with the 503
   retry), then a `LyricsPanel` in `NowPlayingView`: scroll `lyrics.lines`,
   highlight `lyrics.activeLine(at: store.player.elapsed)`, tap a line to
   seek. Core API: `PandoraCore/Lyrics.swift`, `PandoraCore/LyricsProvider.swift`.
3. **Lyrics unit C (translation)** — call `GoogleTranslateClient.englishTranslation(of:)`
   when the detected source language is not English; it returns `nil` for
   English → show the original only. Fill `LyricLine.translation`.
4. **User device test of this push's IPA** — the critical one: play a
   station for >30 s (crash?), song artwork in mini player + full player,
   tab switching with the mini player, then **open Diagnostics
   (stethoscope, Stations toolbar) → Copy → paste the log** if anything
   is still wrong. If the app crashed and relaunched, the "Last crash"
   section is already filled in.
5. App icon (no asset catalog; `ASSETCATALOG_COMPILER_APPICON_NAME: ""`).
6. Beautify pass (theme, typography, gradients).
7. Session-expiry surfacing + ad handling (protocol notes at the bottom).

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
