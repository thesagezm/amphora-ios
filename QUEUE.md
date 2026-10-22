# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M1** — Auth: Blowfish password, partner login, user login, Keychain
persistence, auto-login, typed errors. (M0 complete.)

## User Feedback Pending

_(none yet)_

## In Flight / Last Push

- **This push (handover point, 2026-10-22): M1 SessionManager + Core Tests
  repair.** Origin/main before this push was `dd0c0d5`:
  - `dd0c0d5` **iOS Build ✅** (39830370491) but **Core Tests ❌**
    (39830374094): `URLSession`/`URLRequest` live in `FoundationNetworking`
    on Linux — `LegacyPandoraClient` needs `#if canImport(FoundationNetworking)`,
    plus the corelibs `URLSession` isn't Sendable → `@unchecked Sendable`
    `SessionBox`. **Fixed in this push.**
  - This push adds **`SessionManager`** (actor): full pithos-connect flow
    (partner login plain → decrypt syncTime → offset → user login
    encrypted → store), `restore()` warm-start, and **1001 retry-once**
    in `authenticatedRequest` (re-login → replay exactly once → surface).
    `SessionStore` protocol + `InMemorySessionStore` (Keychain impl lands
    in the app target — PandoraCore stays portable).
  - 12 SessionManager tests: login pair + request shapes asserted from
    decrypted bodies, credential rejection, malformed/short/unparsable
    syncTime, restore w/ zero network, requires-session, retry-once (4
    requests, fresh token), second-1001 no-loop, offset math.
    `MockTransport` extracted to a shared test file (class, not actor —
    sync `requests` accessor; Swift 6: no `await` inside XCT* autoclosures,
    all actor-property reads hoisted).
  - Crypto fixtures for syncTime tests generated from the vendored pithos
    Blowfish pipeline (main/short/unparsable — see SessionManagerTests).

**FIRST ACTION next session:** `gh run list --limit 5`. If Core Tests is
red on this push, read the failure summary annotation (step now works and
logs upload as `core-tests-log`) and repair before any new unit.

## Pending Queue

1. Verify this push green (Core Tests + iOS Build). Repair first if red.
2. **M1 login screen** (app target): wire `SessionStore` → Keychain
   (`KeychainStore` already scaffolded at `Amphora/Persistence/`),
   `AppStore` gains login intent → `SessionManager.login`/`restore`,
   login form UI with mocked-success path, typed errors surfaced.
3. Warm-launch path: `restore()` on app start → station list later (M2).

## Milestones

- [x] **M0** — skeleton, green CI
- [ ] **M1** — auth (partner login, Blowfish, user login, Keychain, auto-login)
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
