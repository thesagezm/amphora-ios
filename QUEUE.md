# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M0** — Repo skeleton: xcodegen project + PandoraCore package, empty app
builds, both CI workflows green.

## User Feedback Pending

_(none yet)_

## In Flight / Last Push

- Unit 1: repo skeleton (Amphora app target, PandoraCore package, both CI
  workflows, project.yml) — pushed, awaiting first CI run.

## Pending Queue

1. **Unit 2** — Repair loop: get `Core Tests` + `iOS Build` both green.
   Check `gh run list --limit 5` (non-blocking); if red, read failed log,
   fix the specific error, push, repeat.
2. **Unit 3** — M1 Blowfish-ECB with CryptoSwift + known-answer test vectors
   (libpiano key derivation).
3. **M1 continuation** — `URLBuilder`/param encoding → `auth.partnerLogin`
   endpoint + decoding test → `SessionManager` with re-auth retry-once →
   typed error mapping → login screen with mocked success.

## Milestones

- [ ] **M0** — skeleton, green CI
- [ ] **M1** — auth (partner login, Blowfish, user login, Keychain, auto-login)
- [ ] **M2** — stations (fetch/list/create/rename/delete + list UI)
- [ ] **M3** — playback (playlist, AVPlayer, background audio, Now Playing)
- [ ] **M4** — feedback & bookmarks
- [ ] **M5** — UI/design pass
- [ ] **M6** — performance & robustness

## Completed Units

_(none yet)_
