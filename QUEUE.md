# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M1** — Auth: Blowfish password, partner login, user login, Keychain
persistence, auto-login, typed errors. (M0 complete.)

## User Feedback Pending

_(none yet)_

## In Flight / Last Push

- M0 verified green on CI: `Core Tests` run 39807086811 ✅ (1m37s),
  `iOS Build` run 39807086129 ✅ (43s), artifact `amphora-ipa-1` (613 KB)
  from commit `1ec069e`.
- This commit: correct partner constants from the pithos reference
  (`pithos/pandora/data.py` — my initial `partnerPassword` was wrong,
  `encryptKey`/`decryptKey` were missing).

## Pending Queue

1. **M1 crypto** — Blowfish-ECB wrapper over CryptoSwift + known-answer test
   vectors. Key derivation exactly as pithos: request bodies are encrypted
   with `encryptKey` (`6#26FRL$ZWD`), `syncTime` responses decrypted with
   `decryptKey` (`R=U!LH$O2B#`), PKCS-style 8-byte pad, hex-encoded output.
2. `URLBuilder`/param building (query args + JSON body + encryption).
3. `auth.partnerLogin` endpoint + response decoding test (fixture JSON).
4. `SessionManager`: partner login → user login → token storage →
   session-expiry retry-once.
5. Typed error mapping (pithos `ApiError` table → `PandoraError` cases).
6. Login screen with mocked success.

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

## Protocol Notes (reference-verified)

- Request encryption: PKCS-pad plaintext to 8 bytes → Blowfish-ECB with
  `encryptKey` → hex string. Applied to the JSON request body
  (`pithos.pandora.json_call`, `blowfish=True`).
- `syncTime` in `auth.partnerLogin` response is hex-encoded ciphertext;
  decrypt with `decryptKey`, strip padding, take bytes `[4:14]` as the
  10-digit Pandora timestamp; `time_offset = pandora_time - now`.
- `auth.userLogin` body: `username`, `password`, `loginType: "user"`,
  `returnIsSubscriber: true` — encrypted; also carries `partnerAuthToken`
  or `userAuthToken` when present, plus `syncTime`.
