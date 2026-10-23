# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M1** — Auth: Blowfish password, partner login, user login, Keychain
persistence, auto-login, typed errors. (M0 complete. All M1 units are
pushed; milestone stays open until the user confirms login + auto-login
on their phone.)

## User Feedback Pending

_(none — both resolved below)_

**Resolved feedback:**

1. **"Installing Amphora: error — the folder 'payload' doesn't exist"**
   (2026-10-23, LiveContainer) — fixed by `4dd1fbf`: zip `Payload` from the
   workspace root; artifact `amphora-ipa-10` verified to contain
   `Payload/Amphora.app/…`. **User then signed in on device — install
   confirmed working.**
2. **M1 confirmed on device** (2026-10-23): user reports real sign-in
   succeeded and app shows the signed-in placeholder. **M1 milestone
   complete.**

## In Flight / Last Push

- **This push (2026-10-23): repair Core Tests after station-list core push.**
  - `10abb9c`: **iOS Build ✅** (39879789581), **Core Tests ❌**
    (39879789613) — 1 failure: `StationTests.testDecodesFullStationFields`
    threw `undecodable response body`. Cause: the fixture was assembled by
    concatenating string literals and a doubled `,"` broke the JSON.
    Fixed by making `fullStationJSON` one literal.

- `10abb9c` (2026-10-23): **M2 unit 1 — station list core**. PandoraCore
  only (no app changes yet):
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

**M2** — Stations: fetch / list / create / rename / delete + list UI.
(M0 ✅, M1 ✅ — user signed in on device 2026-10-23.)

## Pending Queue

1. Verify this push green (Core Tests + iOS Build). Repair first if red.
2. **M2 unit 2**: wire `getStationList` into `AppStore` (stations state +
   refresh intent) + station list UI (artwork, quick-mix, explicit badge,
   sorting) — the signed-in placeholder becomes the real list.
3. M2 units after that: create / rename / delete station.

**FIRST ACTION next session:** `gh run list --limit 5`. If Core Tests is
red on this push, read the failure summary annotation (step now works and
logs upload as `core-tests-log`) and repair before any new unit.

## Milestones

- [x] **M0** — skeleton, green CI
- [x] **M1** — auth (partner login, Blowfish, user login, Keychain, auto-login)
      — confirmed signed-in on device 2026-10-23
- [ ] **M2** — stations (fetch/list/create/rename/delete + list UI)
- [ ] **M3** — playback (playlist, AVPlayer, background audio, Now Playing)
- [ ] **M4** — feedback & bookmarks
- [ ] **M5** — UI/design pass
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
