# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M1** — Auth: Blowfish password, partner login, user login, Keychain
persistence, auto-login, typed errors. (M0 complete.)

## User Feedback Pending

_(none yet)_

## In Flight / Last Push

- This push (3 commits): **red-CI repair + M1 partnerLogin transport +
  workflow failure summaries (user-approved).**
  - Repair: `JSONValue.escape` static-member call (both runs of 61027a1
    were red — Core Tests had been a FALSE GREEN: missing `set -o pipefail`
    let `tee`'s exit 0 mask the compile failure); URL query builder switched
    to `percentEncodedQuery` (the `query` setter re-encoded our %XX);
    encrypted-roundtrip test trims zero-padding before comparing; literal
    U+0001 byte in a test expectation replaced with `\u0001`.
  - New: `Errors.swift` (pithos ApiError table → typed `PandoraAPIError`,
    friendlier curated messages), `ResponseEnvelope.swift` (ok/fail
    unwrap), `AnyJSON.swift` (typed Codable JSON), `LegacyPandoraClient.swift
    ` (injected `HTTPTransport`, URLSession impl, partner/user login request
    shapes). 13 tests via mock transport — no network.
  - CI: both workflows gain `set -o pipefail`, failure-summary steps
    (speechnotes-ios pattern: grep errors → `::error title=…::` annotation,
    logs uploaded as artifacts), concurrency cancel-in-progress.
    User approved workflow edits for this (2026-10-22).
- Previous: URLBuilder `61027a1` (both runs red — repaired here);
  crypto `a852955` green (Core Tests 39816015922, iOS Build 39816015943).

## Pending Queue

1. `SessionManager`: partner login → syncTime offset → user login →
   token storage → session-expiry retry-once (1001 → re-login → replay).
2. Login screen with mocked success (app target).

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
- **M1 partner transport** — this push: typed errors, envelope decoding,
  `LegacyPandoraClient` with mock-transport tests; workflow failure
  summaries + pipefail fix.

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
