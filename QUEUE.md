# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M1** — Auth: Blowfish password, partner login, user login, Keychain
persistence, auto-login, typed errors. (M0 complete.)

## User Feedback Pending

1. **"Installing Amphora: error — the folder 'payload' doesn't exist"**
   (2026-10-23, LiveContainer). Diagnosed: the packaging step zipped from
   *inside* `Payload/`, so the archive's entries were `Amphora.app/…` with
   no `Payload/` prefix — and the IPA must contain `Payload/`. Fixed by
   zipping `Payload` from the parent dir (one-line workflow fix, user-
   reported = approved). **Awaiting user re-test** with the next artifact.

## In Flight / Last Push

- **This push (2026-10-23): IPA packaging fix** (see User Feedback 1).
  One-line change in `ios-build.yml`: `zip -qry Amphora-unsigned.ipa
  Payload` run from the workspace root, replacing
  `cd Payload && zip … .`. Verified locally: old form yields entries
  `Amphora.app/…` (broken); new form yields `Payload/Amphora.app/…`.

- `a48f70e` (2026-10-23): repair Core Tests after SessionManager push.
  Swift 6 marks `NSLock.lock/unlock` `noasync` — `MockTransport.post`
  called them inline; moved the locked work into a sync helper.
  Result: iOS Build ✅ (39868695533), Core Tests ❌ again (39868695527)
  with 2 assertion failures → repaired by `83af041`.

- `83af041` (2026-10-23): the two assertions: (1) decrypted request body
  carries the per-chunk NUL pad — trim before comparing (same convention
  as URLBuilderTests); (2) `URL.path` drops the trailing slash on Linux
  Foundation — assert `baseURL.absoluteString` instead.

**FIRST ACTION next session:** `gh run list --limit 5`. If Core Tests is
red on this push, read the failure summary annotation (step now works and
logs upload as `core-tests-log`) and repair before any new unit. Confirm
the new IPA artifact contains `Payload/Amphora.app/` entries.

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
- **M1 SessionManager** — `6139d4c`: actor with pithos-connect flow,
  `restore()`, 1001 retry-once, `SessionStore`/`InMemorySessionStore`,
  12 tests, syncTime fixtures. iOS Build ✅; Core Tests red (NSLock-noasync
  in MockTransport) — repaired by the next push.

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
