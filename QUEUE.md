# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

**Working style (2026-11-02, user):** no subagents — do the research
and the implementation directly in this session.

## Current Milestone

**M6** — performance & robustness. (M0–M5 code complete; M2 confirmed on
device 2026-10-23 "everything so far works". M3–M5 device check pending —
superseded by the crash report below.)

## User Feedback Pending

**2026-11-10 feedback round (this session's driver):** "fix the music
player viewer… the playback controls move separately from the artwork
when they should be fixed/move together… the icons for playback
controls are the substandard none elegant icons e.g play button… for
the radio channels there should be that large icon the way it is with
pandora for the last played station". Three asks, mapped to units:

1. **Controls move separately from the artwork** → **Unit A landed**
   (this push). Root cause: the full player had *two* containers —
   artwork/header/scrubber in a `ScrollView`, transport/volume/
   feedback pinned by `.safeAreaInset(edge: .bottom)` — and the
   content is taller than any phone screen, so every scroll moved the
   artwork under controls that stayed put. The player is now **one
   fixed stack**: artwork + header + scrubber + controls are children
   of the same `VStack`, so nothing can move independently; when
   everything fits, nothing scrolls at all, and if it overflows (huge
   Dynamic Type, Up Next expanded) the whole unit scrolls together.
   The artwork is the flexible element: it absorbs leftover height and
   yields it before the controls do — the Apple-Music behavior.
2. **Transport icons are substandard** (play.fill at 58 pt bold, the
   double-triangle forward.fill) → **Unit B landed** (this push): a
   drawn glyph family — play, pause, next, stop, back-15 — to one
   design language, in the full player, the mini player and the Home
   hero. Detail in In Flight / Last Push.
3. **Radio tab needs the large last-played tile** (the way Home has
   it) → **Unit C landed** (this push): the Radio tab root opens with
   the same hero Home carries — the most recent radio station's tile
   large and centered, its name, and a play/pause button. Detail in
   In Flight / Last Push.

**2026-11-07 GUI round (this session's driver):** "improve the gui of
the app… add and make the settings work and useful (last fm doesnt
work)… no artwork for radiostations?… the playback controls and player
dont look sophisticated… improve the gui". Four asks, mapped to units:

1. **Last.fm doesn't work** → **Unit 1 (this push)**. Root cause found
   and **verified live**: the client never sent `format=json`, so
   Last.fm replied in **XML** (the default) while the client only
   decodes JSON → every call failed as `.malformed` ("Last.fm sent an
   unexpected response"). Live probe 2026-11-07: the same signed
   `auth.getMobileSession` POST returns `<lfm …>` XML without the
   parameter and JSON with it. All 28 fixture tests stubbed JSON, so
   they never caught it. Second bug: a fresh sign-in set
   `scrobbler.isEnabled = true` in memory only — the preference was
   never persisted, so scrobbling was off again after relaunch.
2. **Radio station artwork missing** → **Unit 2 landed** (this push).
   Causes found in the previous session: (a) `ArtworkCache.normalizedURL`
   force-upgraded every URL to HTTPS and `candidateURLs` only ever emitted
   HTTPS variants, so radio favicons on HTTP-only hosts (common in
   radio-browser) failed both candidates; ATS also blocked cleartext.
   (b) Many stations have no favicon at all → the plain antenna glyph read
   as "no artwork". (c) Favicons are often 16×16, so even loaded ones
   looked bad scaled to fill. What landed: the raw HTTP URL is now a real
   last-resort candidate (`ArtworkURLCandidates` in PandoraCore, 17 new
   tests), the ATS exception now covers both the streams and the
   URLSession favicon loads, and every station without usable artwork
   gets a generated monogram/gradient tile (rows, mini player, full
   player, lock screen). Detail in In Flight / Last Push.
3. **Player doesn't look sophisticated** → **Unit 3 landed** (this
   push): the transport was rebuilt around the artwork accent (bigger
   play/pause, matched side buttons, a volume slider under the
   transport), and radio streams now get their own controls — a LIVE
   badge instead of a dead zero-length scrubber, no thumbs (a radio
   track has no song to rate — the intent would fire at a synthetic
   `radio.<uuid>` token), no back-15 (a live stream has no timeline)
   and a stop button instead of "next". The song-level actions that
   are no-ops on a stream (lyrics, tune station, bookmark, hide) are
   not offered either. Detail in In Flight / Last Push.
4. **Settings useful + general GUI polish** → Unit 4 (and Unit 1's
   scrobble status line + Last.fm profile link already add useful
   Settings content).

**2026-11-07 request (prior session's driver):** "add local/internet
radio to the app as the second tab — basically port Shortwave (Linux)
to this app; the recents tab can become a button along with adding a
station and sorting". Tracked as the **R units** below (radio-browser
directory in PandoraCore, playback through the existing PlayerService,
Home toolbar gains the Recents button beside Add + Sort). R1 (Recents
→ toolbar button) is in this push; R2–R5 follow.

**2026-11-02 request:** "add support for airplay to the app" → **the
AirPlay unit landed** (see In Flight / Last Push).

**2026-11-02 follow-up (this session's driver):** "selecting the tv to
be the audio output for just the music … its pausing the playback
instead" → **this push**: the handover no longer rebuilds the player
item (that tore down the handover the system was establishing) and the
system's pause during the switch is now resumed (see In Flight / Last
Push).

**2026-10-26 feedback round (this session's driver — four asks):**

1. **"Why is there no light mode for Amphora"** → **Unit A landed**:
   the theme system gained two light families (**Daylight** — cool
   neutral, **Paper** — warm cream) plus **Match System**, which
   follows the device's light/dark setting and re-resolves live.
   `ThemeController` now owns the `.system` resolution; `RootView`
   reads SwiftUI's `colorScheme` and feeds it in. The app's
   `.preferredColorScheme(.dark)` is gone (except on the full player,
   whose backdrop comes from the artwork and is always a dark scene).
   Scheme-aware tokens: `Theme.stroke` and `Theme.progressTrack`
   invert to soft black on a light floor, and `Theme.accentText`
   (new) is a darker sibling of the accent so accent-coloured *text*
   keeps its contrast against white — the bright fill colours wash out.
2. **"Pithos can like a song even after it has already played"** →
   **Unit B** (next): rating controls in the Recents list, plus the
   shared-station transform Pithos does before rating
   (`transformIfShared` → `station.transformSharedStation`) — without
   it, Pandora rejects feedback on a non-personal station.
3. **"Add some fallbacks in case the first source doesn't have
   lyrics"** → **Unit C** (next): lrclib's exact-match `/api/get`
   404s whenever album or duration differ. Fallback chain:
   lrclib `/api/search` (fuzzy, duration-matched) → a second provider
   (lyrics.ovh, verified live).
4. **"How are you handling lyrics for languages with symbols like
   Korean or Japanese … use alphabet"** → **Unit D landed**: Google's
   `dt=rm` romanization mode (verified live: "사랑해" → "salanghae",
   "君の名は" → "Kiminonaha"). Non-Latin-script lines now render the
   alphabet spelling as the primary reading line (accent-tinted) under
   the original script, with the English translation beneath.

**2026-10-24 UI feedback round (this session's driver — beautify):**
seven numbered points + a follow-up. Mapping to units:

1. **Settings expansion** — theme color customization, Last.fm as a
   setting, more settings (about page, acknowledgements, logs). →
   **Unit 1 landed**: full Settings tab (Appearance: background ×
   accent; Last.fm; Diagnostics & Logs; About + Acknowledgements;
   Sign Out).
2. **Home landing redesign** — large icon of the last-played station
   centered, list below. → **Unit 2**.
3. **Pandora colors + dark/true-black themes + gradients** → Unit 1's
   appearance themes (Amphora Dark / **Pandora Night** [brand blues
   #224099/#00A0EE] / True Black) × 5 accent gradients (Gold /
   Pandora Blue / Violet / Aqua / Rose).
4. **Player complaints** — two sleep timers (toolbar moon.zzz vs the
   FeedbackBar hide-song button's identical moon.zzz icon), borders
   too strong, static-feeling controls. Follow-up message: **"make
   the player look Apple Music-like … shades of matte black/grey
   (solid tones, not liquid glass) … even put the music quality"** →
   **Unit 3**: AM-style player (plain glyph transport, matte shades,
   press animations, one sleep control, quality chip from
   `Track.preferredVariant` bitrate/encoding).
5. **Bookmarks not working on device + remove as tab** — bookmarks
   verified protocol-correct against pydora this session (endpoints,
   params, decode); if it still fails on device, the Diagnostics log
   decides. Tab removed in Unit 1 — bookmarks now live behind the
   Recents tab's segmented control.
6. **Station list borders too hard** — use gentle opacity/matte shades
   instead of hard borders. → shared `amphoraCardRow` is now
   stroke-less (Unit 1); station-row states in Unit 2.
7. **Tab bar restructure** — Bookmarks out, Recents where Bookmarks
   was, Settings tab holds logs/Last.fm/appearance/about. → **Unit 1
   landed**: Home / Recents / Settings.
8. General beautify — continuous across all units.

**2026-10-24 feature requests (prior session's driver — all three landed):**
"last fm, pithos manages to show me the next upcoming like 4 songs…",
"landing page … popular pandora created main stations…", last.fm
scrobbling. All landed (see Completed Units / Last Push history and
the device-test checklist in the 2026-10-24 handover below).

**2026-10-24 device report (prior session's driver) — "DIAGNOSE CRASH AND
FIX":** the app crashed repeatedly on the phone (signal 5). Two Apple
crash reports + Amphora logs pasted; both signatures diagnosed:

1. **Playback crash — deterministic, ours, fixed this push.** Faulting
   thread (thread 9, `*/accessQueue`): `-[MPMediaItemArtwork
   jpegDataWithSize:]` → our requestHandler → `_swift_task_
   checkIsolatedSwift` → `dispatch_assert_queue` → brk #1. The artwork
   handler closure was formed inside a @MainActor method
   (`NowPlayingService.applyArtwork`), so Swift 6 attached a MainActor
   isolation check to it; MediaPlayer invokes artwork handlers on its
   own internal queue whenever the system renders the lock screen →
   the check fails → SIGTRAP. Matches the logs perfectly: crash hits
   right after "lock screen artwork applied", seconds into playback.
   Fix: the handler is now built in a `nonisolated static` helper
   (`lockScreenArtwork(for:)`), explicitly `@Sendable`, and scales the
   image to the requested size via `UIGraphicsImageRenderer`
   (thread-safe). Audited every other framework callback we register —
   remote commands (invoked on main), AVPlayer periodic time observer
   (`queue: .main`), all NotificationCenter observers (`queue: .main`),
   KVO (extract-value-then-`Task { @MainActor }`) — the artwork handler
   was the only one invoked off-main.
2. **Launch crash — one occurrence, ~13 s after launch, main thread,
   iOS 27.0 (24A437).** `_TaskValueModifier.Child.value.getter` →
   `InnerModifier.taskState.init` → `type metadata accessor for State`
   → data abort inside SwiftUI/AttributeGraph — no Amphora frames.
   `_TaskValueModifier` is the backing modifier of `.task(id:)`; the
   app had two sites, `CachedArtwork` (the launch path — every station
   row / history row / mini player) and `AddStationView`'s debounce.
   Both are now `.onAppear`/`.onChange` + an owned `@State` task
   (identical restart/cancel semantics), so the app contains **no
   `_TaskValueModifier` at all**. If this crash recurs after this push
   it is OS-side (iOS 27.0 SwiftUI metadata bug) and we say so.
3. Non-crash from the same logs: one artwork URL failed TLS
   (-1200) on `mediaserver-cont-dc6-1-v4v6.pandora.com` — the
   candidate-fallback worked (a sibling CDN URL loaded fine); lyrics
   lookup/translation behaved as designed; station modes worked on
   device (8 modes offered, "Crowd Faves" set).

**2026-10-23 station-tuning request (prior session's driver):**

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

**(this push — M6 unit: the Pandora transport has a timeout):** an M6
robustness unit while the 2026-11-10 round's device test is with the
user. The audit found a real hang hazard on the main request path.

- **The gap** — `URLSessionTransport` built its request with the bare
  `URLRequest(url:)` initializer, so it carried the system defaults:
  the *request* timeout is 60 s but the **resource timeout stays seven
  days**. On a connection that was accepted but never answers — a
  captive portal, a suspended socket, a hostile middlebox — the send
  hangs effectively forever and the UI shows a spinner that never
  stops. The radio transport has always named its interval (15 s);
  every other `URLSession` user in the package (lyrics, Last.fm,
  StationModes, the app's `ArtworkCache`) still inherits the default.
- **The fix** — `URLSessionTransport` gained a `timeoutInterval`
  (default **30 s**: long enough for a slow cellular playlist fetch,
  short enough that the offline retry UX actually engages) applied
  through the request factory. Request assembly was already a pure
  step, so it moved into `makeRequest(url:body:contentType:)` — pure,
  no I/O — and `post` now reads one line to build its request.
- **4 new tests** (network-free, via the factory): the default is on
  the wire, a custom interval is honored, the POST/headers/body
  assembly is unchanged, and the default is bounded (15–60 s) so
  neither a slow fetch nor a hang can silently break it. **319/319
  green in Docker** (315 + 4; the tight loop, 4 s).

Follow-up landed (this second push of the same hazard — one hazard
class, every remaining site):
- **`NetworkDefaults` (new, core)** — the shared `requestTimeoutInterval`
  (30 s) with the reasoning in one place; the main transport's
  `defaultTimeoutInterval` now *references* it, and a test asserts the
  two cannot drift apart.
- **Applied at every remaining bare-request site**: the lyrics GET
  transport (one fix covers lrclib, lyrics.ovh and Google translate,
  which all ride `HTTPGETTransport`), `LastFmClient`'s session
  transport, the station-modes transport, the CSRF bootstrap's
  HEAD/GET cookie probe, and the app's `ArtworkCache` (its request now
  carries the interval — without it, every artwork surface sat on a
  placeholder with no route to a retry on a hung connection).
- Radio keeps its own shorter 15 s by design (directory probes must
  fail fast so mirror rotation can kick in). **320/320 green** in
  Docker (315 before the pair, +4 first unit, +1 anti-drift here).

**Device expectation**: with Wi-Fi on but no actual route (captive
portal / after leaving the network), opening the app or pulling to
refresh now fails within ~30 s with the error banner and a working
Retry, instead of spinning indefinitely; artwork from a dead candidate
URL falls through to the next candidate within ~30 s rather than
stalling the row.

**M6 code audit (session-of-2026-11-11, no unit needed — recording the
clean results so they are not re-audited later):**

1. **Force-unwrap discipline** — the app target carries **no `try!`,
   `as!`, `.first!`/`.last!`** and no force unwraps in the audit
   patterns. Clean.
2. **Audio-quality selection** (priority 3) — `Track.variants` is
   genuinely best-first: the playlist parser sorts by quality-bucket
   rank then bitrate, so `preferredVariant = variants.first` really
   streams the best the account offers; the pithos 128-MP3 promotion
   is in place. `additionalAudioUrl: HTTP_32_AACPLUS,HTTP_128_MP3` is
   requested (wire params match the references). No change.
3. **Ad path** — playlist ad stubs are resolved (`session.prepareAd` →
   `ad.getAdMetadata` + impression registration) and registration
   failures never interrupt playback. Wired.
4. **Radio under a media-services reset** — `playLiveStream` fills
   `slots` exactly like `play`, so `handleMediaServicesReset` rebuilds
   the stream and resumes. Wired.
5. **Transport timeouts** — the hazard unit above + its follow-up
   cover every `URLSession` user in the project; radio keeps its own
   15 s for fast mirror rotation.

**CI state (this session, non-blocking checks only):** repair
(`6a5f494`) ✅✅ · transport timeout (`39096fb`) ✅✅ · the
follow-up (`5c768b4`) was in flight at the last check — confirm with
`gh run list --limit 5`.

**(previous push — Unit C of the 2026-11-10 round: the Radio tab's
last-played hero):** the user's "for the radio channels there should
be that large icon the way it is with pandora for the last played
station" — the Radio tab now opens with the same landing centerpiece
the Home tab has carried since the 2026-10-24 redesign.

- `RadioView.homeList` leads with a `radioHero` row above "My
  Stations": the most recent radio station (`store.radioRecents.first`)
  as a large centered tile — `RadioStationArtwork` at the hero slot
  (240 pt cap, `minimumArtworkPixels: 200`, so a real logo only wins
  when it is genuinely big; otherwise the drawn monogram tile, the
  same rule the full player uses) — the station name, and a "Now
  playing"/"Last played" caption.
- The play/pause button is the drawn glyph family's (23 pt in the
  58 pt accent circle, `TransportGlyph` from Unit B) and dispatches
  the existing `.playRadioStation` intent — the store already toggles
  playback when the tapped station is the one playing, so the hero
  doubles as pause.
- Hidden until something has played (no recents → no hero), same rule
  as Home; the hero station also stays in the "Recently Played"
  section below, as on Home. The texts combine into one VoiceOver
  element; the button keeps its own "Pause/Play <station>" label.
- No PandoraCore changes; `RadioController` untouched — the hero only
  reads state the store already publishes.

Local verification: `RadioView.swift` parse-clean in the `swift:6.0`
container; PandoraCore untouched (315/315 stands). The app target
compiles on CI only.

**Device expectation**: play any radio station, leave the Radio tab,
come back (or relaunch) → the tab opens with the last-played station
as a large centered tile with its name and a play button; tapping the
tile's button pauses/resumes; with no radio history the tab starts
directly at My Stations / Discover as before.

**CI state at the end of this round (2026-11-10):** Unit A (`2fbcc65`)
Core Tests ✅ / iOS Build *cancelled* — superseded by the Unit B push
minutes later, as was Unit B's (`cf7b66c`) by Unit C's (`bb28013`).
**The runs for `bb28013` are the ones that matter — check
`gh run list --limit 5` first thing next session** (fire-and-continue:
never waited on them). All four touched UI files parse-clean locally;
PandoraCore untouched (315/315 stands).

**(previous push — Unit B of the 2026-11-10 round: the drawn transport
glyph family):** the user's "the icons for playback controls are the
substandard none elegant icons e.g play button".

- **New `Amphora/UI/TransportGlyph.swift`** — five glyphs *drawn*, not
  borrowed: play (rounded triangle), pause (two rounded bars), next
  (triangle + bar, not the dated double-triangle `forward.fill`),
  stop (rounded square, radio streams), back-15 (a 290° arc with the
  gap at the upper left, a counterclockwise arrowhead at the top and
  "15" inside — the system gobackward.15's shape language, drawn to
  match the family's weight). Every proportion derives from the
  square the glyph is drawn in, so play at 17 pt and play at 44 pt
  are the same icon scaled; corners round proportionally
  (`RoundedTriangle` = 10% of the triangle's own size), the bars and
  gaps share one ratio system, and the visual weight is matched
  across the family. Pure SwiftUI, one file, no assets.
- **Wired into every transport surface**: the full player's transport
  (side glyphs at 27 pt in the 56 pt slots, play/pause at 44 pt in
  the 92×76 slot — slightly smaller than the old 58 pt bold symbol,
  which read as a heavy wedge), the mini player's accent-circle
  buttons (17 pt, `accentGlyph` on the accent fill) and the Home
  hero's play button (23 pt). The play/pause swap is a crossfade
  (the `if/else` under the existing `.animation(value:)`); the
  `.symbolEffect(.replace)` content transitions are gone with the
  Image views.
- VoiceOver labels, haptics, radio-specific behaviors (stop instead
  of next, no back-15) are unchanged.

**Repair (this push):** the Unit B iOS Build was red on two lines —
`missing argument label 'kind:' in call` — the synthesized memberwise
init labels its first parameter, so the leading-dot calls
(`TransportGlyph(.pause, size: 23)`, the same shape in the full
player, the mini player and the hero) did not compile. Fixed at the
source: `TransportGlyph` now has an explicit init with the kind
unlabeled, every call site unchanged. All five touched files
parse-clean; the app target compiles on CI only.

Local verification: the four touched files parse-clean in the
`swift:6.0` container; PandoraCore untouched (315/315 stands). The
app target compiles on CI only.

**Device expectation**: the transport reads as one drawn family — a
soft-cornered play triangle, matched pause/next/back-15, no chunky
system wedge; the mini player and the Home hero button use the same
icons.

**(previous push — Unit A of the 2026-11-10 round: the player is one fixed
layout):** the user's "the playback controls move separately from the
artwork when they should be fixed/move together".

- **The diagnosis** — `NowPlayingView` put the artwork, track header and
  scrubber in a `ScrollView` and pinned the transport, volume, feedback
  bar and Up Next below them via `.safeAreaInset(edge: .bottom)`. The
  artwork alone is nearly full width (~340 pt square) and the controls
  region adds ~300 pt more, so on every phone the content overflows and
  the two containers scrolled *independently* — the artwork slid under
  controls that never moved. That is exactly what the user saw.
- **The fix** — one stack. The main branch of `content` is now a single
  `VStack` (artwork → header → route → scrubber → controls) inside one
  `ScrollView`, framed to at least the screen height, so:
  - when everything fits, nothing scrolls at all (`scrollBounceBehavior
    (.basedOnSize)` keeps the rubber-band off) — a fixed player;
  - when it genuinely overflows (Up Next expanded, accessibility sizes),
    the whole unit scrolls *together* — artwork and controls can never
    move independently again.
- **The artwork is the flexible element** — `.aspectRatio(1, .fit)` in a
  `frame(maxWidth: .infinity, maxHeight: .infinity)`: it absorbs the
  leftover height and yields it before the controls do, so expanding Up
  Next or large Dynamic Type shrinks the cover — never the transport.
  This is the Apple-Music artwork behavior and also removes the old
  safe-area-inset juggling.
- `fixedControls` is now `playerControls` (it is no longer pinned); the
  lyrics layout keeps its own fixed-transport arrangement unchanged.

Local verification: `NowPlayingView.swift` parse-clean in the
`swift:6.0` container; PandoraCore untouched (315/315 stands). The app
target compiles on CI only.

**Device expectation**: open the full player → the artwork and the
controls sit on one fixed screen, no scrolling between them; expand Up
Next → the artwork shrinks, the controls stay put; nothing scrolls at
default sizes.

**(previous push — the station name on the Now Playing screen):** the last
item from AGENTS.md's Now Playing list ("artwork, title, artist,
**station**, progress, skips") that the screen did not have — the
header showed title, artist, album and the quality chip, but never the
station the track came from. The line sits under the album, in the
secondary colour, and VoiceOver reads it as "Playing on <station>". A
radio stream is skipped there (its title *is* the station name).

**(previous push — the GUI polish pass: every list row now reacts to a
touch):** the user's "improve the gui of the app". The audit found a
concrete, systematic gap rather than a taste question: **every list row
in the app was a `.plain` button, so no row reacted to a touch at all.**
The system highlight belongs to the *list row*, and a plain button opts
out of it — the player controls had the app's press language, the lists
had nothing.

- **New `RowPressableButtonStyle`** (`Theme.swift`) — the row-level
  cousin of `PressableButtonStyle`: the card dims to 72% and settles
  back with a spring (0.26 s, bounce 0.22), scaled to 0.99. Much
  softer than the glyph style on purpose — that one shrinks a 44 pt
  control by 8%, which is right for a transport button and wrong for a
  380 pt row.
- **Applied to every full-width row**: the Home station rows, the
  browse row, the Radio station rows (list, search results, favorites,
  recents), the Radio discover rows (Popular / Countries / Tags) and the
  country/tag catalog rows, the browse sheet's category rows, the
  add-station search results, and the mini player's open button.
- **Icon buttons keep the glyph style**: the Login button, the accent
  swatches, the bookmark delete and the error-banner dismiss.
- **A haptic on the Home station rows** — tapping a station starts
  playback, and it now says so (the hero and the Radio rows already
  did).

Local verification: the nine touched app files are parse-clean
(`swiftc -parse -swift-version 6`); PandoraCore untouched (315/315
stands). The app target compiles on CI only.

**Device expectation**: tap a station row on Home, a station row in
Radio, or a browse row — the card dips and springs back instead of
feeling dead; the Sign In button and the accent swatches dip like the
transport buttons already do.

**(previous push — the explicit-content badge, at the only level the
protocol supports):** AGENTS.md asks for an "explicit-content badge" on
the station list. The legacy API has **no per-track explicit flag** —
the filter is an account-level switch — so a per-station badge would
be invented data. This unit ships the honest version: one account-level
badge.

- **The protocol, verified against pithos** —
  `Pandora.explicit_content_filter_state` calls `user.getSettings` and
  reads `isExplicitContentFilterEnabled` and
  `isExplicitContentFilterPINProtected`. pithos' `https=True` only
  switches the transport to TLS — the body is still Blowfish-encrypted,
  exactly like every other authenticated call, so Amphora's
  `authenticatedRequest` fits as-is.
- **Core (`UserSettings.swift`, new)** — the reply as a value type. A
  missing key means "off", matching pithos' `.get(..., False)`
  default — an older server that does not send the field must not read
  as "the filter is on".
- **Core (`SessionManager.getUserSettings()`)** — `user.getSettings`
  with no parameters of its own (the session token rides in the query
  and the encrypted body, like every other call).
- **App (`AppStore`)** — `isExplicitContentFilterEnabled`, read once
  after sign-in / session restore. Best-effort: a failure only leaves
  the badge off, it never blocks anything.
- **UI** — Home carries one caption row under the browse row ("Explicit
  content is filtered for this account." with the `e.square.fill`
  glyph); Settings → Account shows "Explicit Content: Filtered /
  Allowed" with a pointer to pandora.com, where the setting actually
  lives. Changing it from the app is out of scope: the account's PIN
  protection would have to be handled, and the API only takes effect
  with the next playlist (pithos).

Local verification: **PandoraCore 314/314 green in Docker** (307 + 7
new tests — decoding, the missing-key default, the wrong-type case,
the call's method/token on the wire, and the 1001 re-auth contract);
the three touched app files are parse-clean. The app target compiles
on CI only.

**Device expectation**: sign in with an account that has the explicit
filter on → Home shows the "Explicit content is filtered" caption under
the browse row, and Settings → Account reads "Explicit Content:
Filtered"; with the filter off, neither appears.

**Repair (this push, on top of the skip-limit push):** the skip-limit
push's iOS Build was red on one line —
`value of type 'PlaylistError' has no member 'playlistEnded'`: an enum
with an associated value has no such member, the value has to be
unwrapped. `PlaylistError.playlistEnded` is now a computed property
(`switch self { case .skipLimitReached(let ended): … }`) with a test
for it — **315/315 green** locally after the repair.

**(previous push — skip-limit awareness, the last unimplemented AGENTS.md
requirement):** "Respect skip limits and rate limits. Never hammer the
API" + "skip-limit awareness shown in UI" — the feature set asked for
it, the code never had it.

- **The protocol, derived and verified** — Pandora signals the limit by
  **fault message**, not by a numeric code: the legacy error-code table
  has no entry for it. The reference is Elpis
  (`Libs/PandoraSharp/Station.cs:232`), which compares the exception
  message against `"PLAYLIST_END"` and `"DAILY_SKIP_LIMIT_REACHED"` and
  treats the first as "skip limit reached"; pithos has no special case
  at all (its `json_call` raises `ApiError` with the server's message),
  and pianobar's changelog knows the same token.
- **Core (`PandoraAPIError`)** — `isSkipLimitReached` /
  `isPlaylistEnd` match the server's message (case-insensitive,
  whitespace-tolerant, and tolerant of a message that carries the token
  plus a sentence). The messages themselves are named constants
  (`playlistEndMessage`, `dailySkipLimitMessage`).
- **Core (`PlaylistError`)** — a new typed error:
  `.skipLimitReached(playlistEnded:)`. `SessionManager.getPlaylist`
  maps the fault to it, so the app can tell "the server refuses more
  tracks" apart from "the network is down" — the two need opposite
  reactions (stop asking vs. retry later).
- **App (`AppStore`)** — `skipLimitStationId` remembers which station
  hit the limit; `handleSkipLimit` reports it and **cancels the prefetch
  retry**: no prefetch, no retry, no hammering (the three playlist
  paths — first play, prefetch, restart-after-tuning — all route
  through it). A successful play of the same station clears the flag.
- **UI** — the full player shows a yellow **SKIP LIMIT** capsule with
  the explanation under it; the station row on Home reads "Skip limit
  reached" (and VoiceOver says "Pandora's daily skip limit reached").

Local verification: **PandoraCore 307/307 green in Docker** (298 + 9
new tests — the message detection, the typed mapping of both server
signals, that other faults stay `PandoraAPIError`, and that the request
is made exactly once); the four touched app files are parse-clean.
The app target compiles on CI only.

**Device expectation**: play a station until Pandora's daily skip limit
is reached (the queue dries up) → the player shows the SKIP LIMIT badge
and the row on Home is marked; the Diagnostics log shows "skip limit
reached for … — not requesting more tracks"; no further playlist
requests are made for that station (the log line appears once, not on a
retry loop).

**(previous push — Unit 4 slice 2: Settings manage the data they own):**
the user's "add and make the settings work and useful". Unit 1 already
added the live Last.fm status line; this slice adds the **Library**
section — the two kinds of data the app keeps on the device, and a way
to wipe each one.

- **`ArtworkCache.clear()` + `diskUsage()`** (app target) — empties both
  tiers (decoded images in memory, bytes on disk) and cancels in-flight
  downloads; `diskUsage()` reports what the disk tier occupies. The
  cache is a pure accelerator, so clearing it is safe: artwork is
  downloaded again the next time a screen shows it.
- **`AppStore`** — two intents: `.clearHistory` (wipes the local play
  history — Pandora's own listening data and the account are untouched)
  and `.clearArtworkCache` (clears the cache, then refreshes the size).
  `refreshArtworkCacheSize()` is called when Settings appears, so the
  row shows the real number rather than a guess.
- **`SettingsView`** — a new **Library** section: "Clear Play History"
  (with the play count, disabled when the history is empty, behind a
  confirmation alert) and "Clear Artwork Cache" (with the cache size on
  disk, disabled when it is empty). Both rows say what is local-only in
  the section footer.

Local verification: the **host has no Swift toolchain, but the
`swift:6.0` Docker image is present**, so `PandoraCore` runs locally
again (**298/298 green**, 3.4 s) and the three touched app files are
parse-clean (`swiftc -parse -swift-version 6`). The app target itself
still compiles on CI only (fire-and-continue).

**Device expectation**: Settings → Library → "Clear Play History" shows
the number of plays and asks to confirm; the Recents sheet is empty
afterwards. "Clear Artwork Cache" shows the cache size and empties it;
station and song artwork still shows (it is downloaded again).

**(previous push — Unit 4 slice: the playback volume survives a relaunch):**
the volume slider Unit 3 added forgot its level on the next launch.

- **`Preferences.playbackVolume`** — an **optional** `Float?` on
  purpose: a preferences file written before this key existed must
  still decode (a missing key is an error for a synthesized
  `Decodable`, and that error would silently reset every other
  preference). `nil` means full volume.
- **`AppStore`** — the stored level is applied to the player at launch
  (`player.setVolume(preferences.playbackVolume ?? 1)`), and the new
  intent `.setPlaybackVolume(_:)` applies it live and writes it to
  disk.
- **The slider writes once per gesture, not per frame** — the view
  keeps the dragged value in `@State` (`draftVolume`) and applies it
  live to the player; the intent (and the disk write) fires from the
  slider's `onEditingChanged` when the drag ends.

Local verification: **not run this session** — the host has no Swift
toolchain and the Docker test run was declined by the user. Core Tests
and the iOS Build ride CI on this push (fire-and-continue).

**CI state at the end of the session:** Unit 2 (`d83c98d`) ✅ Core
Tests 42484879520 + iOS Build 42484879521 · Unit 3 (`dc0ace3`) ✅ Core
Tests 42519050000 + iOS Build 42519049995 · this push (`be12caa`) ✅
Core Tests 42521649254, iOS Build 42521649244 **in flight** (not
waited on — check it next session).

**Device expectation**: full player → drag the volume slider → the
music's level follows live → close the app, reopen it → the slider is
still where it was left.

**(previous push — Unit 3 of the GUI round: the sophisticated player):** the
user's "the playback controls and player dont look sophisticated".

- **The transport was rebuilt** (`NowPlayingView.transport(for:)`): the
  play/pause glyph grew to 58 pt (a 92×76 hit area), the side buttons
  are matched 56 pt glyphs in a 56×56 area, and the spacing opened to
  52 — the Apple-Music proportions the rest of the player already
  follows (matte shades, plain glyphs, no liquid glass). The press
  response (`PressableButtonStyle`: scale 0.92 + 0.6 opacity on a
  spring) and the haptics are unchanged, and the symbol still swaps
  with `.symbolEffect(.replace)`.
- **A volume slider** under the transport: a speaker glyph, a native
  `Slider` tinted with the artwork accent, a second speaker glyph.
  `PlayerService` gained `volume` (0...1) and `setVolume(_:)`, applied
  to `AVPlayer.volume` — the **app's** output level, not the phone's
  system volume, so the slider never fights the hardware buttons. The
  level survives a media-services reset (the rebuilt player restores
  it). **Not persisted across launches yet** — a follow-up, because
  `Preferences` is Codable and a missing key would need the optional
  treatment the other newer fields use.
- **Radio streams get their own controls** — the old player showed a
  radio track as if it were a song, which was wrong in five places:
  - a **LIVE badge** (a pulsing red dot in the same capsule language
    as the ADVERTISEMENT badge) replaces the scrubber: a live stream
    has no length, so a progress bar over nothing read as a broken
    control;
  - the **thumbs are gone** — a radio track has no song to rate, and
    the intent would have fired at a synthetic `radio.<uuid>` token
    (`AppStore` already refused it, so the button did nothing);
  - **back-15 is gone** — there is no timeline to go back in;
  - the trailing button **stops the stream** instead of skipping it
    (both in the full player and in the mini player), because "next"
    on a live stream was quietly a stop;
  - the **lyrics button and the song-level actions** (Tune Station…,
    Bookmark Song, Bookmark Artist, Hide This Song) are not offered —
    all of them are no-ops on a stream.

Local verification: **not run this session** — the host has no Swift
toolchain and the Docker test run was declined by the user. Core Tests
and the iOS Build ride CI on this push (fire-and-continue). The CI
state of the Unit 2 push was not checked (the check was declined) —
check both workflows before the next unit.

**Device expectation**: full player → the transport reads as one
cluster, the volume slider sits under it and changes the music's level
without touching the phone's system volume; play a Pandora station →
the scrubber and the thumbs are there as before; play a radio station
→ a LIVE badge above the transport, no scrubber, no thumbs, no
back-15, and the trailing button stops the stream (the mini player
does the same).

**(previous push — Unit 2 of the GUI round: radio station artwork):** the
user's "no artwork for radiostations?" — three causes, three fixes.

- **The raw HTTP URL was never tried** (`ArtworkCache.candidateURLs`
  force-upgraded every candidate to HTTPS, so the "raw URL as-is"
  fallback its own comment promised was a no-op).
  `PandoraCore/Sources/PandoraCore/ArtworkURL.swift` now owns the
  candidate list: the HTTPS-preferred, percent-encoded form first and
  the URL **exactly as given** second (`http://` stays `http://`) — the
  last-resort candidate for favicons on hosts that serve nothing but
  cleartext. `ArtworkCache.candidateURLs` delegates to it; the
  duplicated `normalizedURL` / `upgradedToHTTPS` helpers are gone and
  the file's header comment no longer lies. The percent sign is now
  allowed in the encoding path, so an already-escaped signed CDN URL
  (`%2F`, `%20`) is not encoded twice.
  **17 new tests** (`ArtworkURLTests`): HTTP raw → two candidates
  (https first, http second), HTTPS raw → one, scheme-less → one,
  spaces percent-encoded, empty/whitespace → none, case/whitespace
  normalization, and the two halves on their own.
- **ATS blocked the cleartext loads.** The target now ships an explicit
  `Amphora/Info.plist` (`project.yml`: `INFOPLIST_FILE` +
  `GENERATE_INFOPLIST_FILE: NO`, the plist excluded from the sources)
  because `INFOPLIST_KEY_*` build settings cannot express a nested
  dictionary — they would have written the key as a flat string and the
  exception would silently do nothing. The plist carries
  `NSAppTransportSecurity → NSAllowsArbitraryLoads = true` **alone**:
  on iOS 10+ that key is ignored when
  `NSAllowsArbitraryLoadsForMedia` / `…InWebContent` /
  `…LocalNetworking` is also present, and `NSAllowsArbitraryLoadsInMedia`
  on its own covers AVFoundation media but **not** the URLSession image
  loads the favicons need. One key, both paths unblocked (the shape was
  verified by parsing the plist, not by eye). The generated plist's
  other keys (display name, version, launch screen, orientations,
  background audio mode, local-network usage string, scene manifest)
  were carried over by hand.
- **Stations without artwork get a generated tile.**
  `PandoraCore/Rources/PandoraCore/RadioStationIdentity.swift` (new,
  pure logic, 8 tests) derives the monogram and a **deterministic**
  hue from the station name — FNV-1a over the UTF-8 bytes, because
  Swift's `hashValue` is seeded per process and would recolor every
  station on every launch. `Amphora/UI/RadioStationArtwork.swift` (new)
  draws the gradient tile and shows the real favicon only when it is
  big enough for the slot: 64 px for the 44 pt radio row and the mini
  player, 200 px for the full player's cover, 120 px on the lock screen.
  Wired into `RadioStationRow`, `MiniPlayer`, `NowPlayingView.artwork`
  and `NowPlayingService.loadArtwork` (which now falls back to the
  drawn tile). A 16×16 favicon blown up to cover size is gone — the
  station's initials are shown instead.
  The antenna glyph is no longer the station's "artwork".

Local verification: **not run this session** — the host has no Swift
toolchain and the Docker test run was declined by the user. Core Tests
and the iOS Build ride CI on this push (fire-and-continue).

**Device expectation**: Radio tab → any station row shows a gradient
tile with the station's initials (or its real logo when it has a big
one); tap it → the mini player and the full player show the same tile
at full size; the lock screen shows the tile as the cover; a station
whose favicon is plain HTTP now loads its logo instead of the tile.

**(previous push — Unit 1 of the GUI round: Last.fm actually works +
useful Settings status):** the user's "last fm doesnt work", root-caused
and fixed, with the fix verified against the live Last.fm endpoint.

- **Core (`LastFmClient.post`)** — every request now sends
  `format=json`. This is *the* bug behind "last fm doesnt work":
  without it Last.fm replies in XML, and the JSON-only decode made
  every call fail as `.malformed`. The parameter is added after signing
  and is excluded from `api_sig` (authspec), so signatures stay valid.
  Two regression tests (`testEveryRequestAsksForJSON`,
  `testFormatParameterIsExcludedFromSignature`) assert the parameter is
  on the wire for all three methods and excluded from the signature —
  these fail without the fix.
- **`Scrobbler`** — new `lastActivity` / `lastActivityIsError` for a
  Settings status line: "Now playing on Last.fm: <track>" at track
  start, "Scrobbled: <track>" on a successful scrobble, and the typed
  error on failure (scrobble failures still never interrupt playback;
  they now *show* instead of only logging). Sign-in sets a "Signed in.
  Play a track to scrobble." hint; sign-out clears the status.
- **Enable-persistence bug fixed** — new `Scrobbler.onEnabledChanged`
  callback, fired on sign-in (enables), sign-out and session-expiry
  (disable). `AppStore` persists `preferences.scrobblingEnabled` from
  it. Previously a fresh sign-in enabled scrobbling only in memory and
  the stored preference read back as `false` on the next launch.
- **Settings** — signed-in Last.fm section now shows the live status
  line (last scrobble / now-playing / error, icon tinted to match) and
  an "Open Last.fm Profile" link (safely unwrapped URL — no force
  unwrap). Sign-out path simplified to rely on the callback.

Local verification: **not run this session** — the host has no Swift
toolchain and the Docker test run was declined by the user. Core Tests
and the iOS Build ride CI on this push (fire-and-continue). The
protocol fix itself is verified by the live probe above; the two new
tests (`testEveryRequestAsksForJSON`,
`testFormatParameterIsExcludedFromSignature`) would have caught the
original bug and run on CI.

**Repair push (`b02b803`):** the first push's Core Tests run was red on
a test-file edit slip — the new test block replaced the `// MARK:
Error mapping` header *including* the `func
testErrorCodesMapToTypedErrors() async {` declaration line, leaving
its body orphaned (CI: "extraneous '}' at top level",
"expected 'func' keyword"). The declaration is restored; iOS Build was
already green on the Last.fm commit (`7cf6503`, run 42417743667).

**Device expectation**: Settings → Last.fm → enter real credentials →
Connect now succeeds (previously always failed with "Last.fm sent an
unexpected response"); "Signed in as <name>" + status line + profile
link appear; play a track past halfway → the status line shows
"Scrobbled: <title>" and the track appears on the Last.fm profile;
toggle persists across relaunch. If it still fails, the status line
and Diagnostics log now show the exact Last.fm error.

**(previous push — app unit R5: custom stations by URL):** the radio
milestone's last unit — the user can add any direct stream URL as a
station (Shortwave's "add by URL").

- **Form sheet** — `Amphora/UI/RadioStationFormSheet.swift` (new):
  name + stream-URL fields, Save disabled until valid (non-empty name;
  URL parses with an http/https scheme — what AVPlayer streams), the
  same add/edit form (a nil `existing` = add). Opened from the Radio
  tab's toolbar **+** (add) or a custom row's Edit context menu.
  Validation is local; saving is synchronous — no network — so the
  sheet dismisses on Save. No .m3u/.pls URL-following (out of scope;
  the footer tells the user to copy the inner link).
- **Persistence** — `Preferences.radioCustomStations` (device-local,
  survives sign-out like favorites/recents). Custom entries reuse
  `RadioStation` with a generated UUID — playable through the R3
  path with zero core changes.
- **`AppStore`** — `radioCustomStations` + `isRadioCustom(_:)`, intents
  `.addRadioCustomStation` / `.updateRadioCustomStation` /
  `.deleteRadioCustomStation`. An edit carries the new identity into
  favorites/recents and the playing snapshot (the stream keeps playing
  until restarted; a restart picks the new URL). A delete removes it
  everywhere and stops playback if it was playing. Custom stations
  skip the directory click ping (they aren't in the directory).
- **Radio tab root** — a "My Stations" section above "Recently
  Played"; rows play/toggle/star exactly like directory rows, with
  Edit/Delete on the context menu.

Local checks: all four touched files parse-clean in Docker;
`RadioController.swift` type-checked clean last push (unchanged).
PandoraCore untouched (272/272 stands). App target compiles on CI
only — verify both workflows on the next `gh run list`.

**Radio milestone complete pending the device test.** Test list:
Radio tab → recents/favorites/discover → Popular rows → tap = music
within ~2s → star persists across relaunch → search finds stations →
+ adds a custom URL station (play, edit, delete) → starting a Pandora
station stops radio and vice versa → skip button stops the stream →
sleep timer pauses radio.

**(previous push — app unit R4: the Radio tab):** the Shortwave port's UI.
`Amphora/UI/RadioView.swift` (new) is the second tab
(`antenna.radiowaves.left.and.right`, between Home and Settings in
`MainTabView`); `Amphora/Store/RadioController.swift` (new) owns every
directory fetch — no networking in SwiftUI views (AGENTS.md) — and is
composed by `AppStore` as `store.radio` (state survives tab switches;
it shares the store's `RadioBrowserClient`, so mirror rotation and the
click ping see the same servers).

- **Root ("Radio")**: "Recently Played" section (swipe-remove per row,
  header "Clear" button), "Favorites" section (A–Z, as the store
  orders it), and a "Discover" section — Popular / Countries / Tags as
  accent-tiled `NavigationLink` rows (the browse-sheet language).
  Tapping a station row plays it via `.playRadioStation` (tapping the
  playing station toggles — store behavior from R3); the playing
  station's card washes in the accent and shows the speaker glyph.
- **Star toggle** on every station row (nested button, own tap and own
  VoiceOver element — the row uses `.contain`, not `.combine`) →
  `.toggleRadioFavorite` with haptics.
- **Search**: the tab root is `.searchable`; non-empty text debounces
  400 ms in the controller (never hammer the directory) then swaps the
  root for results; clearing returns to the home. Results use the same
  rows and the same accent-tint playing state.
- **Discovery lists**: Popular / one country / one tag push a shared
  `RadioResultsView` (loading / error + Retry / empty / card rows);
  Countries and Tags push catalog lists (name + station count), each
  fetched once per session (same caching as the genre browse sheet)
  with typed error copy from the R2 client.
- R5 (custom stations by URL, add/edit/delete) is the radio milestone's
  remaining unit.

Local checks: `RadioController.swift` **type-checks** clean in Docker
(`swiftc -swift-version 6` against the built PandoraCore module + an
`AppLog` stub — the strong local check from the CrashReporter rounds);
all four touched files parse-clean. PandoraCore untouched this push
(R2's 272/272 and its green CI runs stand). **CI confirmed green on
this push** (Core Tests ✅ + iOS Build ✅, runs 42390856873/42390856833).

**Device expectation**: Radio tab with recents/favorites/discover →
tap Popular → rows → tap a station → music within ~2s, star persists
across relaunch, search finds stations live, starting a Pandora
station stops radio and vice versa.

**(previous push — app unit R3: radio plays through the existing player):**
the glue between the R2 directory client and playback. Nothing new in
the UI yet (that is R4) — but radio is playable end-to-end from state:

- **`Track.radioTrack(for:)`** (PandoraCore bridge): a directory
  station becomes a synthetic live track — `trackToken =
  "radio.<uuid>"`, title = station name, artist = caption, artwork =
  favicon, **duration = 0**, and the stream URL riding as the single
  (highQuality) variant — the player reads `streamURL` from the
  variants, so without it the item would refuse to build (caught by
  the new test). `Track.isRadio` marks synthetic tracks by prefix.
- **`PlayerService.playLiveStream(track:)`**: one slot, no prefetch
  (there is no "next"), duration 0 — the scrubber reads it as live
  and disables itself. Audio session, AirPlay, interruption handling
  all inherited unchanged.
- **`NowPlayingService`**: live tracks get
  `MPNowPlayingInfoPropertyIsLiveStream` instead of a zero duration.
- **`AppStore`**: `currentRadioStation` (mutually exclusive with
  `currentStation` — starting one stops the other) plus intents
  `.playRadioStation` / `.stopRadio` / `.toggleRadioFavorite` /
  `.removeRadioRecent` / `.clearRadioRecents`. Favorites (A–Z,
  Shortwave-style) and recents (newest first, capped at 20) persist
  in `Preferences`. The directory click ping fires best-effort on
  play. `skipToNext` **stops** radio (no next track) and the
  remote-command path is covered by the queue-empty branch in
  `onTrackChanged`. Radio tracks are excluded from: history,
  lyrics, scrobbling (now-playing + scrobble), rating, sleep-song,
  bookmarks. Note: favorites/recents live in `AppStore`, not a
  separate `RadioController` — the intent pattern already had the
  persistence and playback wiring; splitting it would have meant two
  sources of truth.
- Device-local radio data survives sign-out (same rule as history).

Local checks: PandoraCore **272/272** in Docker; the four touched app
files parse-clean (`swiftc -parse`). App target compiles on CI only.
**CI note**: R2 runs for `8ccff94` were in flight when R3 was pushed —
check both on the next `gh run list`.

**Device expectation (after R4's tab exists)**: tap a station → audio
within ~2s, lock screen shows the station name + live indicator, skip
button stops the stream, star persists across relaunch, starting a
Pandora station stops radio and vice versa, sleep timer pauses radio.

**(previous push — core unit R2: the radio-browser directory client):**
PandoraCore gained `RadioBrowser.swift` — the community directory
behind GNOME Shortwave (radio-browser.info: free, keyless, GET-only
JSON, mirrored across independent servers). Contents:

- **Models**: `RadioStation` (uuid, name, resolved stream URL,
  favicon, tags, country/code, language, codec, bitrate, votes,
  clicks, plus a `caption` helper for list rows), `RadioCountry`,
  `RadioTag`. Malformed directory entries are skipped, never fatal;
  an empty `url_resolved` falls back to the submitted `url`.
- **`RadioBrowserClient`** (actor): search by name, top-voted, by
  country code, by tag, countries/tags lists (largest first), and the
  click-counter ping Shortwave also sends on play (`registerClick`,
  best-effort). An injected `RadioBrowserTransport` keeps tests
  network-free; `RadioURLSessionTransport` sends the User-Agent the
  API asks clients to identify themselves with.
- **Mirror rotation**: on a mirror's failure the call immediately
  tries the next one, and the rotation remembers only *failures* —
  a mirror that answered stays first until it stops answering. All
  mirrors failing surfaces the last typed error
  (`RadioBrowserError.httpStatus/networkFailure/badResponse`).

11 new tests (fixtures mirror the real wire shapes): decode + skip,
garbage body, caption, countries/tags decode, query assembly
(`order=votes`, `hidebroken`, percent-encoded paths), empty-query
skips the network, dead-mirror rotation, dead mirror not retried
first, all-down typed error, click ping. Local: **270/270** in Docker.

**(previous push — app unit R1: Recents loses its tab, Home gains the
toolbar button):** the user's 2026-11-07 restructure. `MainTabView` is
now Home | Settings (the Radio tab lands in R4). `StationsView`'s
toolbar gains a **clock button** (Recents + bookmarks) beside the
existing **+** (add station) and **reorder** buttons — exactly the
three the user named. The old `RecentsView` (history + bookmarks
behind the segmented pill) is unchanged and now opens as a full sheet
with a Done button. No PandoraCore changes.

Local checks: PandoraCore 259/259 in Docker (the host toolchain is
gone from PATH — core tests run via `docker run -u 1000:1000 -v
…/PandoraCore:/pkg -w /pkg swift:6.0 swift test`; the stale root-owned
`.build` was reset once via a root container to fix a build-tool
crash). App target compiles on CI only.

**Device expectation**: two tabs (Home, Settings); the clock button on
Home opens Recents + bookmarks; history rating and bookmarks still
work inside the sheet.

**(previous push — app unit: the AirPlay handover gets out of the system's
way and resumes its pause):** the user's device report on the
audio-only path: "selecting the tv to be the audio output for just the
music … its pausing the playback instead". Both previous approaches are
replaced — each was wrong in a complementary way:

1. **The item rebuild is gone** (`handOverToCurrentRoute` removed).
   Its premise was wrong: a player item is *not* bound to the renderer
   it was created for. AVPlayer follows the output route on its own —
   external playback carries AirPlay, the session's audio graph
   carries everything else. What `replaceCurrentItem` actually did was
   kill the external-playback connection the system was in the middle
   of establishing to the TV, then force a fresh item to re-buffer
   from scratch under `automaticallyWaitsToMinimizeStalling` — the
   user sees that as playback pausing. `handleRouteChange` is now two
   lines of real work: publish the new route for the UI, and re-apply
   the sharing policy on `.categoryChange` (as before). Every route
   reason takes the same path; `.oldDeviceUnavailable` (receiver went
   away) needs no rebuild either — the system falls back to the phone
   on its own.
2. **The system's pause during the switch is now recovered.** Picking
   an audio-only receiver parks the player (`timeControlStatus →
   .paused`) for a moment and the system does not always resume it —
   the pause the user reported, present even in the earlier build that
   never touched the item. The timeControlStatus observer now treats a
   paused player as a question: if the app still wants audio
   (`wantsToPlay` — cleared only by `pause()`/`stop()`, so a
   deliberate pause is never overridden), no interruption is active
   and no failure is being shown, it resumes (`play()`, state →
   `.buffering` until the player reports for itself). `play()` on a
   dead item does not change the status, so the rule cannot loop — and
   the resume works even if the system parks the player without a
   route notification at all.
3. **The route log carries the missing diagnostic** — `external
   playback active/off` (`player.isExternalPlaybackActive`) between
   the route name and the port list. On the audio-only path that flag
   says whether AVPlayer actually engaged the receiver; the next
   Diagnostics report from a failing handover says which side dropped
   it (route moved but external playback off → the player never
   engaged).

Local checks: `PlayerService.swift` parse-clean in Docker
(`swiftc -parse`); PandoraCore untouched (259/259 stands).
**Device expectation**: music playing on the phone → pick the TV from
the route picker (mini player or full player) → the music moves to the
TV within a couple of seconds, never pausing; the "Playing on …"
caption follows; picking the phone back (or the TV going away) moves
the music back the same way. If it still fails: Settings →
Diagnostics → Copy — the `output route:` line now shows whether
external playback engaged.

**(previous push — app unit: rebuild the player item on an AirPlay
handover):** the user reported that **screen mirroring** to a Samsung TV
works (and carries Amphora's audio), but picking the TV as the
**audio-only** output does not. That is the app's own path, and it was
wrong: a player item keeps its connection to the renderer it was
created for — the phone's own output. When the route changes to a
receiver, the item is not attached to the new renderer, so it keeps
playing (or stalls) on the device no matter what the session says.

- **`PlayerService.handOverToCurrentRoute()`** (new) — on a route
  change the current item is rebuilt for the new route
  (`player.replaceCurrentItem(with:)`), the position is restored with a
  seek, and playback resumes. This is what actually moves the sound to
  the receiver. The track does not change, so the now-playing and
  scrobbling hooks are deliberately not fired.
- **Only a real handover rebuilds the item** — the route is read
  *before* the switch and compared with the previous one. A receiver
  that merely woke up nearby also posts `.newDeviceAvailable`; that
  must not cause a needless re-buffer on the phone.
- **The handover is logged in detail** — `handover: item
  readyToPlay/failed/unknown, timeControl …, rate …` plus the item's
  error, so the Diagnostics report says whether the stream made it to
  the new route or stalled on the way.

Together with the previous push (session configured at launch, session
activated only when music is playing), the audio-only path now differs
from the mirroring path in the right way: the mirroring path carries
the phone's system audio over the AirPlay connection, while the
audio-only path hands a *rebuilt* player item to the receiver.

**(previous push — app unit: harden the AirPlay handover):** the user
reported that a **Samsung TV** (which does support AirPlay 2) would not
play Amphora's audio. Two real bugs in the handover, both of which
produce exactly that symptom — the receiver is picked, but the sound
stays on the phone:

1. **The session category was configured at playback time, not at
   launch.** `configureAudioSession()` only ran from
   `activateAudioSession()`, i.e. on the first press of play. Setting
   the category re-evaluates the available routes, so a category change
   made *after* the user chose a receiver can drop that choice and fall
   back to the built-in speaker — which is what happens when the user
   picks the TV in the route picker and then presses play. The session
   is now configured **once in `init()`**, so the category is already
   `.playback / .default / .longFormAudio` before the route picker is
   ever used and no category change can undo a route selection.
2. **A route appearing activated the audio session even with nothing
   playing.** The `.newDeviceAvailable` branch called
   `activateAudioSession()` unconditionally, so merely browsing the
   route list (or a receiver waking up nearby) started the audio stack
   — and the category change that came with it could drop the
   selection the user had just made. The session is now activated on a
   route change **only when music is actually playing**
   (`wantsToPlay && !slots.isEmpty && !isInterrupted`).

The route log is also richer now: `output route: <name> [airplay] —
ports: <name> [type] …`, so the Diagnostics report says whether the
system really moved the output (and to which port types) instead of
leaving it to guesswork.

**(previous push — app unit: the mini player's route caption respects the
light themes):** the mini player sits on the app floor, which can be
Daylight or Paper — and the bright accent fill loses contrast against
a white floor. The route caption, its glyph and the route picker's
active tint now use `Theme.accentText` (the accent's darker sibling
that stays legible on a light floor), the same rule the rest of the
app follows. The full player is unaffected: its backdrop comes from
the artwork and is always dark.

**(previous push — app unit: the route caption follows the lyrics mode):**
the "Playing on …" capsule in the full player only existed in the
artwork layout — opening the lyrics panel made it disappear. It is now
shown in both layouts, so the user always knows where the sound is
going.

**(previous push — app unit: AirPlay in Diagnostics):** the Diagnostics
report (Settings → Diagnostics & Logs, then Copy/Share) now carries a
`route:` line — the live output route, e.g. `Living Room (airplay)` or
`device speaker`. AirPlay problems are reported from the phone, so the
report has to say where the audio was going when the problem happened.
The line is read live (not snapshotted), so it is current at the moment
the user copies the report.

**(previous push — repair of the mini-player AirPlay unit):** the unit-2
push was red on the iOS Build with one error:
`AVPlayerItem` has no member `allowsExternalPlayback` — that property
lives on **`AVPlayer`**, not on the item. The explicit opt-in is now
set on the player (and on the replacement player built after a media
services reset). Everything else in the unit compiled.

**(previous push — app unit: AirPlay in the mini player; the iOS Build
was red on it, see the repair above):** the follow-up
to the AirPlay unit below (same request). The route picker now lives in
the **mini player** as well, so the output can be switched from any
screen without opening the full player; the mini player's second line
shows the name of the device the music is playing on (the artist when
the audio is on the phone), with the route glyph beside it. The idle
picker is tinted with the secondary label colour and turns accent when
a route is active — the same state the system's own control shows.
`AVPlayer.allowsExternalPlayback` is now set explicitly (the default,
stated so the intent survives a future change). The AirPlay symbol name
lives in one place (`RouteSymbol`) shared by the full player and the
mini player.

**(previous push — app unit: AirPlay support):** the user's explicit
request ("add support for airplay to the app"). AGENTS.md lists "AirPlay
refinements" as a stretch item, but the user asked for it directly, so
it is in scope; the app target only — `PandoraCore` is untouched (259/259
still green). CI on that push: **Core Tests ✅ / iOS Build ✅**
(41410940609 / 41410940614).

- **The audio session now allows the route to be shared**
  (`PlayerService.configureAudioSession`): `setCategory(.playback,
  mode: .default, policy: .longFormAudio)` — the `.longFormAudio`
  route-sharing policy is what lets an AirPlay receiver take the audio.
  The category is only set when it differs from the session's current
  one, because `setCategory` posts a `.categoryChange` route
  notification: the old code answered that notification by calling
  `setCategory` again, which risks a feedback loop (and the same
  `setCategory` + `setActive` pair ran on every single activation).
  Category and activation are now separate steps, and a failed
  activation while audio is already playing no longer overwrites the
  track's error message.
- **Live route state** — `PlayerService` publishes `outputRouteName`
  ("Living Room", "AirPods") and `isAirPlayActive`, read from the
  session's current route. Anything that is not the phone's own speaker
  counts as an external route; the AirPlay flag is called out
  separately. A new `onRouteChanged` callback fires when the route
  changes.
- **Route handovers keep the music going** — `.newDeviceAvailable` and
  `.routeConfigurationChange` (the user picked a route) take the new
  route and re-issue the play; `.oldDeviceUnavailable` (the receiver
  went away) re-issues it too, so the fallback to the phone's speaker
  does not leave the queue parked. The play *intent* is tracked
  separately (`wantsToPlay`) because the player's own state can dip to
  `.paused` for a moment during a handover, and it is not acted on
  during an interruption (`isInterrupted`).
- **Lock screen follows the route** — `NowPlayingService` re-publishes
  the now-playing info when the route changes, so a receiver that just
  joined shows the current title and artwork. The artwork already on the
  lock screen is carried over when the track has not changed, so
  re-publishing never blanks the cover for a moment.
- **The picker** — `Amphora/UI/AirPlayRoutePicker.swift` (new): the
  system `AVRoutePickerView` wrapped for SwiftUI (SwiftUI has no
  equivalent; this is the one UIKit control the player borrows).
  `prioritizesVideoDevices = false` — Amphora is an audio app — and it
  is tinted with the artwork accent so it sits in the player's toolbar.
  The full player shows it in the toolbar and a "Playing on …" capsule
  under the track header whenever the output is not the phone's own
  speaker.
- **Info.plist** — `NSLocalNetworkUsageDescription` added to
  `project.yml`: AirPlay receivers are found over the local network
  (Bonjour), and iOS 14+ hides the devices from the route picker
  without this string.
- Local checks: 4 touched app files parse-clean in Docker
  (`swiftc -parse`); `PandoraCore` 259/259 green in Docker (`swift:6.0`).
- **Device expectation**: open the full player → the AirPlay button in
  the toolbar opens the system route list → pick a receiver → the music
  moves to it and the player shows "Playing on <device>"; pull the
  receiver away → the music comes back to the phone and the caption
  disappears. The lock screen / the receiver's own screen show the
  current track and artwork.

**(previous push — core + app unit D: romanization for non-Latin-script
lyrics):** feedback item 4 of the 2026-10-26 round ("how are you
handling lyrics for languages with symbols like korean or japanese…
id like to sound the correct way with the words basically use
alphabet"). All protocol research was verified live in the prior
session; this unit is the implementation.

- **Core (`LyricsProvider.swift`)** — `GoogleTranslateClient` now also
  conforms to the new `LyricsRomanizing` protocol
  (`romanization(of lines: [String]) async -> [String]?`). It calls
  the same `translate_a/single` endpoint with `dt=rm` (instead of
  `dt=t`) and decodes the `rm` reply
  (`[[[null,null,null,"romanized"],…],null,"ko",…]`) — a different
  segment shape from the translation reply (text at index 3), so it
  has its own `RomanizationResponse` decoder; a segment with fewer
  elements decodes as no-romanization and is dropped. The reply
  preserves line breaks, so the joined segment texts must split back
  into exactly the input line count (or the segments line up one per
  line) — a mismatched count returns nil and nothing is shown, never a
  shifted alignment.
- **The rate-limit gate** — `GoogleTranslateClient.
  containsNonLatinScript(_:)` (public, tested) skips the request
  entirely for Latin-script text (Hangul syllables + jamo, kana, CJK
  ideographs + extension A, Thai, Cyrillic ranges). English/French/
  Portuguese lyrics cost exactly one Google request as today; the
  endpoint 302s probing IPs to its "unusual traffic" page. The
  no-segments reply (`[null,null,"en",…]`) is the second net for
  Latin input that slips through.
- **Core (`Lyrics.swift`)** — `LyricLine` gains
  `romanization: String?` (optional; lines without the key still
  decode — regression-tested).
- **App (`AppStore`)** — a new injected `lyricsRomanizer` (default
  `GoogleTranslateClient()`), its own cancellable `romanizationTask`,
  and `applyRomanization` mirroring `applyTranslation` (line-count
  guard; rebuilds from the current cache entry so whichever of
  translation/romanization lands second keeps the first one's field).
  `translateIfNeeded` now fires both tasks independently — a failed
  romanization never suppresses the translation.
- **App (`LyricsPanel`)** — a line with a romanization renders three
  rows: the original script (demoted to a secondary reference line),
  the romanization as the **primary reading line** (title3, semibold
  when active, tinted with the artwork accent), and the English
  translation beneath. Lines without one render exactly as before.
- 16 new tests — **259/259 green in Docker** (`swift:6.0`; was 245).
- **Device expectation**: Korean/Japanese/Chinese/Thai/Cyrillic
  lyrics now show the alphabet spelling under each line, sing-along
  style; English and other Latin-script lyrics are unchanged and cost
  no extra request.

**(previous push — core unit C: lyrics source fallbacks):** feedback item 3 of
the 2026-10-26 round ("add some fallbacks incase the first source doesnt
have lyrics"). App target untouched except the provider injection.

- **The gap** — lrclib's exact-match `/api/get` 404s whenever album or
  duration differ from what Pandora sends (verified live this session:
  "Creep" with a wrong album → 404; with just track+artist → 200). One
  miss and the user saw "No lyrics".
- **New `LyricsFallbacks.swift` (PandoraCore)** — three pieces:
  1. **`LRCLibSearchClient`** — lrclib's own fuzzy endpoint
     (`/api/search?track_name=&artist_name=`, the same database). The
     candidates are scored against the track by `LyricsMatchScorer`
     (artist first — a different artist is disqualifying on its own,
     caught by the `testSameTitleDifferentArtistIsRejected` test; then
     title, then duration as tie-breaker, minimum score 30) and the
     best one wins. Handles 503-retry like the exact-match client.
  2. **`LyricsOvhClient`** — lyrics.ovh, a genuinely different database
     (plain lyrics only, verified live). Path components are
     percent-encoded by hand — "AC/DC" must become `AC%2FDC`, and
     `appendingPathComponent` would treat the slash as a separator
     (regression-tested).
  3. **`LyricsProviderChain`** — tries providers in order
     (exact match → fuzzy search → lyrics.ovh), skips a provider that
     returns empty/instrumental-only content, and reports
     `notFound` only when *every* source has nothing.
- **App wiring** — `AppStore`'s injected provider defaults to
  `LyricsProviderChain.defaultChain()`. The lyrics cache, translation
  and UI are unchanged: the chain is invisible to them.
- **19 new tests — 245/245 green in Docker** (`swift:6.0`; was 226).
  The test suite shares `StubGETTransport` with the provider tests
  (now internal rather than file-private).
- **Device expectation**: lyrics that used to say "Couldn't find lyrics
  for this track" (wrong-album or non-lrclib songs) now show words.
  Synced lyrics are unaffected — they still come from the exact match
  first.

**(this push — core + app unit B: rate a song that has already played):**
feedback item 2 of the 2026-10-26 round ("pithos am able to like a
song even after it has already played").

- **Why Amphora could not do it before** — two protocol gaps, both
  confirmed against pithos and pydora this session:
  1. **Pithos transforms a shared station before rating**
     (`Song.rate` → `self.station.transformIfShared()` →
     `station.transformSharedStation`). Pandora rejects feedback on a
     station the user has not personalised. Amphora's `addFeedback`
     never did this.
  2. **Removing a rating needs a `feedbackId`**, and the id is unknown
     for a song rated before this device saw it. Pithos' trick:
     re-rate with the *opposite* rating to obtain an id, then delete
     that feedback.
- **Core (`SessionManager.rateTrack`)** — Pithos's `Song.rate` verbatim:
  transform a shared station (once per station token — pithos's
  `isCreator` flag, mirrored as a token set), replace an existing
  rating by its id, and obtain an id by re-rating when removing one
  whose id is unknown. Returns `TrackRatingResult` (new type: the
  rating afterwards + the new feedback id). 7 new tests.
- **Core (`PlayHistory.Entry`)** — now carries the `stationToken` the
  track was played from (the rating belongs to that station) and its
  rating. The station token and rating are optional, so a history file
  written by an older build still decodes. A re-listen keeps the
  rating the user already gave — the rating belongs to the song, not
  to the play. 6 new tests.
- **App** — the Recents list rows now carry thumbs-up / thumbs-down
  glyphs (the same language as the player's FeedbackBar: the active
  rating fills, tapping it again removes the rating). The rows are
  disabled when the station the track was played from is no longer in
  the user's list. New intents `rateHistoryTrack` /
  `removeHistoryTrackRating`.
- Local checks: 226/226 green in Docker (`swift:6.0`; was 214);
  both touched app files parse-clean.

**(this push — UI unit A: light mode):** feedback item 1 of the
2026-10-26 round ("why is there no light mode").

- **New appearances** — `ThemeAppearance` gains `.daylight` (cool
  neutral: #EDF0F4 floor / white cards), `.paper` (warm cream:
  #F4EFE6 floor / ivory cards) and `.system` (follows the device).
  The three dark families are untouched.
- **`ThemeController` resolves `.system`** — `resolvedAppearance` maps
  it to `.daylight` when the device is light, `.dark` when it is dark;
  `resolvedSelection` is what the tokens read. The device's scheme
  arrives from `RootView` via SwiftUI's `colorScheme` environment
  value (`setSystemColorScheme`), updated in `.onChange` so a
  mid-session flip re-themes instantly.
- **Scheme-aware tokens** — `Theme.stroke` and the new
  `Theme.progressTrack` invert to soft black on a light floor (a
  white hairline on white is invisible); `Theme.accentText` is a new
  darker sibling of each accent, used wherever the accent is *text*
  (station name, QuickMix glyph, segmented-pill label, browse icons,
  the Last.fm checkmark) — the bright accent fills lose contrast
  against white.
- **Player stays dark** — the full player's backdrop is derived from
  the artwork, so it keeps `.preferredColorScheme(.dark)`; its chips
  and toasts use the new `Theme.playerSurface` instead of the app
  surface, which would have been near-white on a light floor.
- Sheets (sleep timer, tune station, browse) now follow the theme
  instead of forcing dark. The app-level `.preferredColorScheme(.dark)`
  in `RootView` is gone.
- Local checks: all 12 touched app files parse-clean in Docker
  (`swiftc -parse`); PandoraCore untouched (214/214 stands).

**(this push — public release v0.1.0):** user directed: repo goes public,
prerelease `v0.1.0` is cut, all authorship moves to thesagezm, and
anything that could identify the machine is removed. Done:

- **History rewritten** — every commit's author/committer is now
  `thesagezm <192189590+thesagezm@users.noreply.github.com>` (was
  `ZCode <zcode@localhost>`); `main` force-pushed. Repo-local git
  identity switched to thesagezm for all future commits. **User
  explicitly authorized the v0.1.0 prerelease** — the one-time
  exception to the no-version-bump rule.
- `CFBundleShortVersionString` 0.0.1 → **0.1.0** (`CFBundleVersion`
  stays 1).
- Identity scrub: `.gitignore` comment no longer names the agent tool.
  Full-tree and full-history scans found nothing else machine-
  identifying (no local paths, no IPs; test fixtures use
  `me@example.com`; the `LyricsProvider` user-agent naming
  `thesagezm/amphora-ios` is intended public attribution and stays).
- Pre-rewrite workflow runs — their pages displayed the old ZCode
  authorship — were deleted after the release was cut.
- **The repo is PUBLIC now: nothing machine-identifying may ever be
  committed, and no credentials/tokens anywhere (files, logs, QUEUE).**
- **Post-release incident (2026-10-25):** GitHub's web view broke minutes
  after the release — repo home, tree views, and blob views 500
  ("Something went wrong") for everyone, while commits/commit-diff/raw/
  API pages all serve fine; the release page's tag list also errored.
  Diagnosis: the web refs index wedged after force-push + tag +
  visibility flip + 156 run deletions inside ~2 minutes. This commit is
  a deliberate ref-reindex nudge (new HEAD on main). If the web view is
  still 500 after this push, next step is a GitHub support ticket;
  cloning, `git fetch`, the API, releases, and CI are unaffected.
  **Outcome: fixed —** the web view (home/tree/blob) came back within a
  minute of this push; the release asset widget serves
  `Amphora-v0.1.0-unsigned.ipa` from `/releases/expanded_assets/v0.1.0`
  and the direct download link returns 200. Lesson: after a mass
  history rewrite + visibility flip, pace the follow-up operations; if
  web views 500 while the API serves, a fresh commit re-seeds the refs
  index.

**(this push — UI unit 4: browse sheet joins the card language):**
the one surface the card pass missed. `BrowseStationsSheet`: theme
floor behind both levels, category rows + station rows as matte
`amphoraCardRow` cards, the category glyph becomes the accent-tinted
rounded tile (matching Home's browse row), create buttons press with
`PressableButtonStyle`. Parse-clean in Docker; PandoraCore untouched.

**(repair push — `d5a6830`; the earlier `fc3139a` run is covered by
it):** `Theme.selection` helper needed `@MainActor` too — its body
references the controller, and the downstream `@MainActor` statics
didn't propagate isolation through it. iOS Build green on `d5a6830`
(units 1–3 all compile for iOS).

**(repair push — `60f28e9`, unit-2 iOS Build was red):** one error in
unit 1's AboutView — `.title2.weight(.bold).width(.rounded)`: rounded
is a font **design**, not a `Font.Width`. Now `Font.system(.title2,
design: .rounded).weight(.bold)` (the shape NowPlayingView already
uses). Trap class: SwiftUI type errors are CI-only — `-parse` can't
see them.

**(this push — UI unit 3, `a871b76`: Apple-Music-style player):**
feedback
item 4 + the follow-up ("make the player look Apple Music-like — matte
black/grey shades, not liquid glass — even put the music quality").

- **One sleep control** — the FeedbackBar's third button (hide-song)
  wore the same `moon.zzz` glyph as the sleep timer: that was the
  "two sleep timers". Secondary actions now live in one
  Apple-Music-style toolbar ellipsis menu: Sleep Timer…, Tune
  Station…, Bookmark Song, Bookmark Artist, Hide This Song
  (`ear.slash`). FeedbackBar is thumbs up/down only, as plain glyphs.
- **Transport** — plain bold glyphs (back-15 / 52 pt play-pause /
  next), no filled circles; `PressableButtonStyle` (new, Theme.swift:
  scale 0.92 + 0.6 opacity, spring) on every control so nothing feels
  static while artwork/progress move; play-pause glyph swaps via
  `.contentTransition(.symbolEffect(.replace))` (mini player + hero
  play button too).
- **Matte, borderless** — artwork lost its hairline stroke (shadows
  carry the depth), confirmation toast + ad badge are matte capsules,
  scrubber bar is a hair thicker at white 14%.
- **Quality chip** — left-aligned AM-style title block (title, artist
  in artwork accent, album) with a matte capsule chip on the trailing
  edge from `Track.preferredVariant`: "128 kbps · MP3" /
  "64 kbps · AAC+" (the stream actually playing; hidden for ads).
- Local checks: 6 touched files parse-clean in Docker; PandoraCore
  untouched (214/214 stands).

**(previous push — UI unit 2, `641f93e`: Home hero + gentle cards):**
feedback items 2 + 6.

- **`StationsView` hero** — the last-played (or playing) station as
  the landing centerpiece: large centered artwork (max 240 pt, radius
  L, black depth + accent glow shadows), name + "Now playing"/"Last
  played" caption, and a big accent play/pause circle (`Theme.
  accentGlyph` icon). Tap plays/toggles the station. Hidden before
  the first-ever play (browse row leads until then). New AppStore
  accessor `featuredStation` (current station, else
  `preferences.lastStationId`, nil before first play).
- **Gentle station cards** — `amphoraCardRow(tinted:)`: the playing
  station's card washes in a matte accent tint (accent at 14% over the
  floor — a shade, not a border) and its name renders in the accent;
  every other card stays a plain matte surface. Browse row got an
  accent-tinted rounded icon tile instead of a bare glyph; the error
  banner lost its stroke.
- Local checks: all three touched files parse-clean in Docker;
  PandoraCore untouched (214/214 stands).
- Next: Unit 3 — the Apple-Music-style player (see feedback item 4).

**(previous push — UI unit 1, `259491f`: theme system + tabs + full
Settings):** the Settings/appearance foundation of the 2026-10-24
beautify round.

- **`Theme.swift` rewritten around user-selectable palettes.**
  `ThemeAppearance` (`.dark` = current violet cast, `.pandora` = brand
  navy #224099/#00A0EE cast, `.trueBlack` = OLED black + neutral
  surfaces) × `ThemeAccent` (gold / Pandora blue / violet / aqua /
  rose, each with primary + gradient partner + a legible glyph color).
  The static tokens (`Theme.background`, `Theme.accent`,
  `brandGradient`, …) became **@MainActor computed vars reading
  `ThemeController.shared`** — observation tracking works through the
  indirection, so a theme change in Settings re-renders every view
  that touches a token (verified pattern: access-time tracking).
  `amphoraCardRow` dropped its hairline stroke — matte surface fill
  only (feedback item 6).
- **`ThemeController` (new, Store)** — @Observable singleton owning
  `ThemeSelection {appearance, accent}`, persisted to its own
  `theme.json` — deliberately NOT in `Preferences`, because AppStore
  round-trips the whole Preferences struct on every save and a second
  writer there would clobber whichever saved last.
- **Tab restructure (`MainTabView`)** — Home (`music.note.house`) /
  Recents / Settings; `.tint(Theme.accent)`. **`RecentsView` (new)**
  absorbs History + Bookmarks behind a themed segmented pill
  (feedback items 5+7). BookmarksView/HistoryView deleted.
- **`SettingsView` (new tab)** — Appearance (menu picker + gradient
  accent swatches), Last.fm (moved verbatim from SettingsSheet, which
  is deleted), Diagnostics & Logs (NavigationLink — DiagnosticsView
  lost its inner NavigationStack/Done for push), About → **`AboutView`
  (new)**: unofficial-client notice + acknowledgements (Pithos, pydora/
  libpiano/pianobar, CryptoSwift, Last.fm, LRCLIB, Google Translate) +
  version row. **Sign Out** with confirmation → new intent
  `.signOutPandora`: `player.stop()`, session-scoped state cleared,
  back to LoginView (local history survives).
- **Core:** `SessionManager.signOut()` — drops credentials/tokens +
  clears the stored record, offline + idempotent. 1 new test —
  **214/214 green in Docker** (213 prior + signOut).
- Local checks: 11 touched/new app files parse-clean in Docker;
  PandoraCore 214/214. ThemeController typechecks standalone (its
  ThemeAppearance types live in Theme.swift, UI-module-only concern).
- Known follow-ups queued: Unit 2 (home hero + station-row states),
  Unit 3 (Apple-Music-style player, one sleep control, matte shades,
  quality chip).

**(previous push — Last.fm app integration, the unit that made it real):**

- **`Amphora/Player/Scrobbler.swift` (new)** — @Observable @MainActor
  engine owned by `AppStore`. Holds the session state
  (`.signedOut` / `.signedIn(name)` / `.needsAuth` — the Last.fm-9
  dead-key state), the Keychain-backed session (`LastFmSession` JSON,
  account `lastfm.session`; the password is never stored), the enable
  flag (persisted via `Preferences.scrobblingEnabled`), and the pithos
  hooks: `nowPlaying(track)` at track start, `scrobbleIfEarned(track:
  reachedPosition: startedAt:)` at track stop. All Last.fm failures
  only log — scrobbling never disturbs playback (Priority 1); error 9
  additionally disables and asks for re-auth from Settings.
- **`PlayerService.onTrackFinished` (new)** — fires at the four points
  where a track stops being current (natural end, skip, station
  switch, stop) with the reached position, *before* the replacement
  track's `onTrackChanged`, so `trackStartedAt` stays the outgoing
  track's start (Last.fm wants the start timestamp).
- **`AppStore`** — owns the scrobbler, sets `trackStartedAt` in
  `onTrackChanged`, routes `onTrackFinished` → `scrobbleIfEarned`;
  intents `authenticateLastFm` / `signOutLastFm` /
  `setScrobblingEnabled` (the last two persist the preference).
- **`SettingsSheet` (new, Stations toolbar gear)** — theme-styled
  (card rows, dark floor): connect form (username + SecureField
  password, spinner, typed error copy), "Scrobble to Last.fm" toggle,
  "Signed in as X" row, Sign Out; needsAuth shows the re-auth prompt.
  Footer explains the scrobble rule in user terms.
- Local checks: `Scrobbler.swift` **-typecheck**s clean under
  `swift -swift-version 6` on Linux (against the built PandoraCore
  module, with KeychainStore/AppLog stubs); all six touched app files
  parse-clean. PandoraCore untouched in this push.

**(repair push — `12b682b`, iOS Build was red on the integration push):**
`AppStore.swift:157` — `private var trackStartedAt = Date()` with no
`import Foundation`. On Linux, PandoraCore's built module re-exports
Foundation, so both the Docker typecheck and `swift test` passed; the
macOS CI toolchain does not re-export it. AppStore now imports
Foundation explicitly (every other touched file already did).
**Trap for the memory:** app-target files that gain direct Foundation
symbol uses need their own `import Foundation` even though local
Linux checks pass — the core package's re-export hides it.

**(previous push — Last.fm core, PandoraCore):** scrobbling protocol for
user request 2026-10-24 item 3. New `LastFm.swift`:
`LastFmSigning.signature` (params sorted by name, `<name><value>`
concatenated, secret appended, MD5 lowercase hex; `format`/`callback`
excluded — verified against the API spec's own worked example),
`LastFmClient.authenticate` (`auth.getMobileSession`, username +
plain-text password per the current docs — the `authToken` md5 variant
is the deprecated one; web-auth needs a URL-scheme callback a
LiveContainer app cannot register, hence the documented mobile flow),
`updateNowPlaying` and `scrobble` (single, un-indexed params; timestamp
= UNIX seconds when the track *started*), typed `LastFmError` map
(4/9/10/13/29 + rejected/http/malformed/transport), strict
percent-encoded form bodies, and `ScrobblePolicy` — pithos's exact rule
(`plugins/lastfm.py`: `!isAd && duration > 30 && (position > 240 ||
position > duration/2)`). API key/secret pair is Pithos's public pair
(`plugins/lastfm.py:25`). **28 new tests — 213/213 green in Docker**
(`swift:6.0`), including the spec's signature example and both
scrobble-rule boundaries. App wiring (settings, Keychain session key,
track-lifecycle triggers) is the next unit.

**(previous push — card-list + brand pass, the beautify pass unit 3 of 3):**
every remaining surface now speaks the theme's language. CI confirmed
units 1–2 fully green (iOS Build ✅ + Core Tests ✅ on both pushes,
incl. the risky SwiftUI surfaces) before this one went out.

- **`Theme.amphoraCardRow()` / `amphoraListBackground()`** (new shared
  helpers): one List row = rounded surface card (radius 16) with an 8%
  white hairline, inset 16 pt, separators hidden, scroll background
  cleared — the list language for every screen, replacing
  `Color.primaryBackground.opacity(0.4)` rows.
- `StationsView`: card rows (browse row + stations, all logic and the
  parallel session's `browseRow` untouched); error banner de-materials
  to a surface card. Playing indicator picks up the global gold accent.
- `HistoryView` / `BookmarksView` / `AddStationView` results: same card
  rows; AddStation's banner de-materials too.
- `LoginView` rebuilt: `Theme.backgroundGradient` floor, gradient-filled
  waveform mark, heavy rounded wordmark, one surface card per field
  (hairline strokes), solid-gold Sign In button (black glyph, accent
  shadow) — matches the player's accent button language.
- Sheets tinted: SleepTimer / TuneStation get `Theme.background` +
  cleared list background; Diagnostics background token swapped;
  last `.thinMaterial` and `Color.primaryBackground` usages are gone —
  the extension was deleted from `RootView` (the app now has exactly one
  color source: `Theme` + the artwork palette).
- Local checks: all 10 touched app files `swiftc -parse` clean in
  Docker. PandoraCore untouched (197/197 run stands; the +1 luminance
  test from unit 2 rides CI — the parallel session's uncommitted
  `LastFm.swift` still blocks a local full-suite run).
- Beautify pass complete pending the user's device test. The look:
  flat dark violet-tinted surfaces, continuous rounded corners
  (10/16/20/24/28), violet→gold brand gradient, gold global accent, and
  the full player bathed in the current artwork's palette (accent, glow,
  gradient stops) — no liquid glass, no system materials anywhere, every
  token in `Theme.swift` for the Android port to mirror.

**(previous push — player restyle, the beautify pass unit 2 of 3):** the full
player and mini player now wear the theme, driven by the artwork palette.
Still no liquid glass — flat fills, continuous corners, one gradient.

- `NowPlayingView` rebuilt: ambient background =
  `Theme.playerBackground(artworkColors)` + a static blurred accent
  ellipse behind the artwork ("light in the room"; no per-tick state, so
  the blur renders once); nav bar background hidden so the gradient
  shows; artwork at radius 28 with a white hairline + black depth shadow
  + accent ambient shadow; artist line tinted with the artwork accent;
  title in rounded bold. Artwork mode scrolls (`.scrollBounceBehavior(
  .basedOnSize)`) with the transport pinned via `safeAreaInset`; lyrics
  mode keeps the panel self-scrolling with fixed controls below (no
  nested scroll views).
- **Custom scrubber** (`PlayerScrubber`, new): capsule track + accent
  fill + white drag knob (visible while dragging), `DragGesture(
  minimumDistance: 0)` with `@GestureState` preview and seek-on-end,
  disabled (35% opacity, no hit-testing) while duration is 0 (ads),
  VoiceOver-adjustable (±10 s). Chosen over `Slider` so the Android port
  can mirror the exact shape.
- Play button: 74 pt circle filled with the **artwork accent**; glyph
  contrast from the new `PaletteColor.relativeLuminance`/`isLight`
  (Rec. 709, +2 tests — dark glyph on light accents like gold, white on
  dark ones). Back-15 is a surface circle; skip-forward is a surface
  circle with the accent glyph.
- `FeedbackBar`: three 52 pt surface circles (up/down/sleep); the active
  rating fills with the artwork accent, icon contrast via `isLight`;
  takes a `PaletteColor` now (only call site updated).
- Bookmarks: surface capsules with hairline strokes instead of
  `.bordered`. ADVERTISEMENT badge: capsule on 14% yellow. Confirmation
  toast: surfaceHighlight capsule (was `.thinMaterial` — materials are
  not portable). Up Next header label tinted accent.
- `MiniPlayer` rebuilt: floating card (radius 20, surface fill, 8% white
  hairline, shadow) with **progress hairline along its top edge** in the
  accent→violet brand gradient; the hairline is its own view so the
  per-tick `elapsed` read re-renders only that 2.5 pt strip, never the
  card (per-property `@Observable` tracking). Gold 34 pt play circle,
  haptics on play/skip, artwork radius 12, card horizontal margin 12.
- `Haptics` (new, Support): light/medium impact feedback on
  play/pause, skip, back-15, ratings, bookmarks — the design spec's
  "haptics on rating/skip", previously absent.
- `AmphoraTimeFormat` (new, Support): the `m:ss` / `h:mm:ss` helper
  extracted from NowPlayingView (scrubber labels + time rows share it).
- `Theme.radiusCard = 20` added.
- Local checks: all 7 touched app files `swiftc -parse` clean in Docker;
  `ArtworkColors.swift` type-checks standalone (its new computed props).
  **The full `swift test` run is temporarily blocked by the parallel
  session's in-flight `LastFm.swift` (uncommitted, missing `return`) —
  CI builds only committed files, so this push is unaffected; the delta
  since the 197/197 run is 8 lines of pure computed properties + 1
  test.**
- Unit 3 (next): station list / login / history / bookmarks card
  treatment + sheet tints. StationsView is the parallel session's hot
  file — recheck `git status` first.

**(previous push — theming foundation, the beautify pass unit 1 of 3):**
Amphora now has a design system and artwork-driven color. The look is
deliberately self-contained (flat dark surfaces, generous continuous
corner radii, one violet→gold brand gradient, **no liquid glass / no
system materials as the look**) so the Android port can reproduce every
value one-for-one.

- `PandoraCore/ArtworkColors.swift` (new, pure logic): dominant-color
  extraction from RGBA8 pixels — HSV conversion, 12 hue buckets,
  weight `s·(0.2+0.8v)` (saturation-led; a first version with
  `s·(1−|2v−1|)` wrongly gave pure #FF0000 zero weight), near-black/gray
  gated, chromatic threshold 8 (~2% of a 32×32 sample) so a tiny colored
  logo can't theme the player; grayscale covers return nil (caller keeps
  the previous/brand palette). Derives `accent` (fixed clamps: s ≥ 0.45,
  v in 0.55...0.80) and two deep gradient stops from the winner.
  **Platform-free by design — the Android port feeds Bitmap bytes into
  the identical algorithm, so both apps theme identically.** 12 tests;
  **197/197 green** in Docker (was 185).
- `Amphora/UI/Theme.swift` (new): tokens — background `#0C0A14`,
  surface `#1B1828`, surfaceHighlight `#28243A`, accent gold `#F2B233`,
  violet `#6C4AB6`, stroke white 8%; radii 10/16/24/28 (continuous);
  `brandGradient`, `backgroundGradient`, `playerBackground(artworkColors)`.
- `Amphora/UI/ArtworkPaletteService.swift` (new): the one UIKit-touching
  step — draws a cached artwork into a 32×32 RGBA8 buffer (CGContext,
  ~1 ms) and runs the shared extractor. Loads through `ArtworkCache`
  (no second download).
- `Amphora/Store/ArtworkThemeController.swift` (new): `@Observable`
  singleton owning `colors: ArtworkColors`; attaches to
  `player.onTrackChanged` (idempotent, from `RootView.task`) — kept out
  of `AppStore` on purpose so the theming layer is additive and the
  parallel session's AppStore/StationsView work never collides.
  Memoized per artwork URL (cap 24), request counter drops out-of-order
  completions.
- Global accent: `AccentColor.colorset` (gold) +
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` in `project.yml` —
  system controls (sliders, alerts, menus, tab tint) now pick up brand
  gold everywhere without per-view tints.
- `RootView`: floor color → `Theme.background`; attaches the theme
  controller. Next units (mine): 2) full player + mini player restyle on
  the artwork palette (ambient gradient, custom scrubber, haptics), 3)
  station list / login / history / bookmarks card treatment.
- Local checks: all four new/edited app files `swiftc -parse` clean in
  Docker; PandoraCore 197/197.

**(previous push — genre stations UI, the landing-page ask):** "Browse
Pandora Stations" is now the first row of the Stations list (radio
glyph, "Popular stations made by Pandora" caption, 44 pt+ target) —
opening a new `BrowseStationsSheet`: NavigationStack with the category
list (`genreCategories`, cached per session — reloads only on relaunch;
error + Retry and empty states included) pushing to a category's
station rows (art via `CachedArtwork` when the wire sent artUrl, radio
glyph otherwise); tapping a row creates a personal station via the
shared create path. `AppStore`: `genreCategories`/`isLoadingGenres` +
intents `loadGenreStations` (fetch-once guard) and
`createGenreStation`; `createStation(from:)` refactored onto a shared
`createStation(musicToken:)` (identical append-if-new + tick-bump
behavior — search-create and genre-create now share it, and the sheet
dismisses on the same `stationCreatedTick` signal as AddStationView).
PandoraCore untouched. All three app files parse-clean in Docker.

**(previous push — genre stations core, PandoraCore):** the protocol behind
"popular Pandora stations" (user request 2026-10-24 item 2). New
`GenreStations.swift`: `GenreStation` (token/stationId/name/
categoryName/artUrl?, Identifiable by token) + `GenreCategory` +
`GenreStations` decode of `station.getGenreStations`'s `categories[]` —
tolerant (unusable entries dropped, duplicate tokens keep first, empty
categories dropped, station `categoryName` inherits the category's,
`stationId` number-or-string) with a malformed-error only when
`categories` is missing/not an array; missing `artUrl` decodes nil (UI
falls back to a glyph). `PandoraAPI.Method.getGenreStations` +
`SessionManager.getGenreStations()` (bare request — no parameters, per
all four references). **6 new tests — 185/185 green in Docker
(`swift:6.0`)**. UI unit is next: Browse section on the Stations
landing → create via the existing `createStation(musicToken:)` with the
genre station's token.

**(previous push — Up Next queue display):** Pithos-parity "Up Next" in the
full player. `PlayerService.upcomingTracks` exposes the tracks queued
behind the current one (`slots.dropFirst()`, most immediate first —
this is what will actually play, ads included and badged "AD");
`@Observable` instruments the private `slots` storage, so the view
invalidates on every queue change (skip, natural advance, enqueue,
prefetch). `NowPlayingView.upNext`: a DisclosureGroup below the
feedback controls, collapsed by default to one line ("Up Next" +
immediate next title), expanding to the next 4 with 38 pt artwork rows;
hidden when the queue is empty. Local checks: both files parse-clean
in Docker. PandoraCore untouched.

**(previous push — session-expiry surfacing + prefetch retry):**

- `AppStore.record(_:)` — every surfaced error now flows through one
  helper (18 call sites). When the error means the session is
  unrecoverable — 1001 after `SessionManager`'s transparent re-login
  retry (a freshly-issued token was already rejected),
  `StationModesError.unauthorized` after its own re-login, or
  `notAuthenticated` — the app returns to the sign-in screen
  (`authPhase = .signedOut`) with "Your Pandora session ended. Sign in
  again." (LoginView displays `lastErrorMessage`). Previously the
  modes error even *said* "Sign in again" with no way to get there.
  Note the self-heal contract is unchanged: a normal expiry re-logins
  transparently inside `authenticatedRequest` and the user never sees
  anything; only genuinely dead credentials surface. Audio keeps
  playing through the transition (the player owns its queue).
- Prefetch dead-end fix: a failed `fetchMoreTracks` (network blip near
  the queue's end) now schedules one backed-off retry (5 s / 15 s / 30 s,
  then stop — never hammer the API). Retry state resets on prefetch
  success and on station change / mode-change restart.
- Local checks: `AppStore.swift` parse-clean in Docker. PandoraCore
  untouched (179/179 from the ad-core run stands).

**(previous push — ad app wiring):** the player now behaves correctly
when an advertisement plays (free accounts hit them in every playlist):

**(this push — ad core, PandoraCore):** free-account ads now decode
instead of being silently dropped. Protocol derived from pydora this
session (pithos has NO ad handling — grep of `pandora.py` via blob API
returned nothing; the old silent drop came from pithos' `songName`
filter): playlist ad entries are stubs (`adToken` + `title`/
`companyName`, usually no audio — pydora `AudioField`: "No audio url
available (e.g. ad tokens)"); resolve with `ad.getAdMetadata`
(`returnAdTrackingTokens=true`, `supportAudioAds=true`); register the
impression with `ad.registerAd` (`stationId` + the reply's
`adTrackingTokens` array) — pydora `AdItem.prepare_playback`.

- `Track`: ad entries kept + flagged (`songName`→`title`,
  `artistName`→`companyName` fallbacks; synthetic id `ad.<adToken>`
  when the entry has no `trackToken`; new `adToken: String?` field;
  bare `audioUrl` still yields a 64-aacplus variant via the existing
  fallback).
- `Advertisement` (new): metadata struct (tolerant decode) +
  `asTrack(stationId:)` player-slot builder.
- `JSONValue`: new `.array([JSONValue])` case — `adTrackingTokens` is
  the first array parameter the API surface needs (sorted-key encoding
  unchanged; exact-byte tests still green).
- `SessionManager`: `getAdMetadata(adToken:)` /
  `registerAd(stationId:trackingTokens:)` (refuses empty token lists
  before any network — pydora `ParameterMissing`) / `prepareAd(_:)` —
  metadata required, registration best-effort (documented deviation:
  pydora propagates register errors; Amphora must never block playback
  on a failed impression registration).
- Tests: 18 new (decode 8, JSONValue 2, facade 8) — **179/179 green**
  in Docker (`swift:6.0`).

**(follow-up push — ad app wiring):** the player now behaves correctly
when an advertisement plays (free accounts hit them in every playlist):

- `AppStore.onTrackChanged`: ads are excluded from the local play
  history, and `prepareAdIfNeeded` fires `SessionManager.prepareAd`
  (resolve + best-effort impression registration, pydora
  `AdItem.prepare_playback`); failures only log — the ad keeps playing.
- Skip is refused during an ad (pydora's player: "Cannot skip
  advertisements") with a user-visible message; rating, sleep-timer and
  both bookmarks are no-ops for ads (their trackToken is synthetic).
  Lyrics already guarded (`loadLyrics` returns nil for ads).
- `NowPlayingView`: yellow ADVERTISEMENT badge above the transport;
  FeedbackBar + bookmark buttons hidden during ads. Scrubber was
  already safe (duration 0 → disabled slider).
- Local checks: both touched app files parse-clean in Docker;
  PandoraCore untouched in this push.
- App-target crash repairs from the 2026-10-24 device report (below)
  are the parallel session's work and are NOT part of this commit.

**(parallel push — crash repair from the 2026-10-24 device report):**

- `NowPlayingService`: artwork handler now built in `nonisolated static
  lockScreenArtwork(for:)` with a `@Sendable` closure (scales to the
  requested size via `UIGraphicsImageRenderer`) — no MainActor
  isolation attached, so MediaPlayer calling it on its own queue no
  longer trips Swift 6's dynamic isolation check. **This was the
  deterministic "crashes seconds into playback" bug.**
- `CachedArtwork` + `AddStationView`: all `.task(id:)` removed
  (`.onAppear`/`.onChange` + owned `@State` task, identical restart +
  cancel-on-disappear semantics) — the app now contains no
  `_TaskValueModifier`, the modifier that trapped in SwiftUI metadata
  instantiation at launch on iOS 27.0.
- All three changed files parse-clean in Docker (`swiftc -parse`);
  PandoraCore **untouched** by this commit — the in-flight ad work
  (see Pending Queue item 3) stays uncommitted in the working tree.

**(previous push — app icon):** Amphora now has an app icon. Generated, not
hand-drawn: `Tools/gen_appicon.py` (pure Pillow, committed for
regeneration) draws at 4096² and downsamples to the required 1024²
opaque RGB PNG at
`Amphora/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Design (user
direction: "add something musical… polish/shine it a bit more…
curved/rounded look nice"): dark violet→near-black diagonal background,
soft amber glow, gold amphora (Catmull-Rom lathe profile +
stamped-spline handles) **with a beamed eighth-note pair + single
eighth note floating out of the mouth, sound-ripple arcs, sparkles**;
polish = specular spot, lip rim-light, warm ground bounce, corner
vignette, final Sharpness/Contrast/Color pass. Every element is
round-capped (no sharp corners); PNG stays full-bleed square because
iOS applies its own rounded-squircle mask. `project.yml`:
`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (was `""`); Contents.json
uses the Xcode 14+ single-size (universal/1024) format — fine on the
Xcode 16.4 CI. Traps fixed during render: never build gradients with
`rotate()`/`paste()` of gradient tiles (border seams); notes need fat
stems/beams (r≈0.034 local units) to survive downscale. PandoraCore
untouched.

**(previous push — repair of the list-tuning push):** iOS Build on `3f8389b`
was red with one error — `TuneStationSheet.swift:80` still sent the old
`.setStationMode(mode)` shape after the intent grew the `for:` station
parameter (the row button's call site was missed; the retry/task sites
were updated). Now `.setStationMode(mode, for: station)`. Grep-audited
every `.setStationMode(` / `.loadStationModes(` call site.

**(previous push — Tune Station from the station list):** the intents now
carry the station (`loadStationModes(Station?)` /
`setStationMode(_:for:)`, nil = the playing one), so the sheet also
opens from a **"Tune Station…" context-menu row on the station list**
(hidden for QuickMix — an aggregator has no modes). Tuning a
non-playing station updates Pandora's per-station mode for its next
play and does **not** touch the current playlist; the
`previousModeId` is only sent when the cached modes describe the same
station (`modesStationId`). The prior push (`55ad967`) went fully
green — **Core Tests ✅ / iOS Build ✅ (40057734767 / 40057734776)** —
after the units-B/C repair; a fresh IPA is uploaded. Files touched:
`AppStore`, `TuneStationSheet` (`station:` param), `NowPlayingView`,
`StationsView`; parse-clean in Docker.

**(previous push — station-tuning UI, app target):**

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

## Session handover (2026-10-25, public release session)

**State:** release cut at the user's direction — repo public, prerelease
`v0.1.0` tagged with an unsigned-IPA release asset, authorship under
thesagezm, identity scrub done (details in In Flight / Last Push).

**FIRST ACTION next session:** `gh run list --limit 5`. The release push
must be green on the rewritten HEAD (Core Tests + iOS Build). Then:

- **Release asset check:** if the attached IPA is not from the 0.1.0
  build (check the release page / run numbers), download the green
  run's `amphora-ipa-<run_number>` artifact and
  `gh release upload v0.1.0 <dir>/Amphora-unsigned.ipa#Amphora-v0.1.0-unsigned.ipa --clobber`.
- The M6 device-test checklist in the 2026-10-24 handover below is
  still the gating item; user feedback still jumps the queue.
- Public-repo hygiene is now permanent (see In Flight entry).

## Session handover (2026-10-24, beautify round session)

**State:** the full 2026-10-24 UI feedback round is landed in three
units + one repair — `259491f` (theme system, Home/Recents/Settings
tabs, full Settings with About/Acknowledgements/Sign Out),
`641f93e` (Home hero + matte station cards), `a871b76`
(Apple-Music-style player), `60f28e9` (AboutView font repair; the
unit-2 build caught it). Core Tests green through unit 2; unit 3 +
repair builds were queued at handover — **check `gh run list` first**.

**Device-test checklist for this round (on top of the accumulated one
below):**

- **Tabs**: Home / Recents / Settings. Bookmarks live behind Recents'
  segmented pill; gear + stethoscope are gone from the Home toolbar
  (they're Settings rows now).
- **Appearance**: Settings → Appearance → Background (Amphora Dark /
  Pandora Night / True Black) and Accent (Gold / Pandora Blue /
  Violet / Aqua / Rose) — every screen should re-theme instantly; the
  choice survives a relaunch.
- **Home hero**: after playing any station, Home leads with its large
  centered artwork + play circle ("Last played"/"Now playing"); the
  playing station's row card is accent-tinted.
- **Player**: ONE moon icon total (ellipsis menu → Sleep Timer);
  menu also holds Tune Station, both bookmarks, Hide This Song.
  Transport = plain glyphs that dip on touch; play/pause glyph
  animates its swap; quality chip ("128 kbps · MP3" or similar) by
  the title. No hard borders on artwork/toast.
- **Sign Out**: Settings → Sign Out of Pandora (confirm) → back at
  login; sign in again works.
- **Bookmarks on device (user said not working)**: bookmark from the
  player's ellipsis menu, then Recents → Bookmarks. The protocol is
  verified against pydora; if it fails, Diagnostics → Copy → paste.

## Session handover (2026-10-24, feature-requests session)

**State:** all three user-requested features landed and pushed, one
unit per commit — `fabcb7d` (Up Next display), `1ed0e59` (genre
stations core, 213/213 Docker), `096e4ca` (browse stations UI),
`129cc01` (Last.fm core, 213/213 Docker), `76b5076` (Last.fm app
integration). The beautify agent finished in parallel (`7b59c17` +
earlier theming commits, all green) and is **done** — theme helpers
live in `Amphora/UI/Theme.swift` (card rows, gradients, gold accent);
new UI should use them. CI: everything through the Last.fm core push
green; the integration push (`76b5076`) was in flight at handover —
**check `gh run list` first next session**; its IPA is the one to test.

**Device-test checklist additions (on top of the existing one below):**
- **Up Next**: play a station >60 s, open the full player → "Up Next"
  row under the feedback controls shows the immediate next title;
  expand → up to 4 rows with artwork; skip → the list advances.
- **Browse stations**: Stations tab → "Browse Pandora Stations" first
  row → categories → tap a station → sheet closes and the new station
  appears in the list (then plays like any station).
- **Last.fm**: Settings (gear, Stations toolbar) → enter Last.fm
  username/password → Connect → "Signed in as …" + toggle on; play a
  track past half → check it scrobbles on last.fm; "now playing"
  appears on the Last.fm profile while a track plays; Sign Out works.
  (Last.fm auth uses the documented mobile flow — password is sent
  once over HTTPS, only the session key is stored in the Keychain.)

**Protocol notes added this session:** genre stations
(`station.getGenreStations`, create with the token as `musicToken`)
and Last.fm (signing spec example, `auth.getMobileSession` current
form, pithos scrobble rule) — both under Protocol Notes below.

## Session handover (2026-10-24, icon+ads session)

**State:** everything pushed and green — `a613a07` (app icon), `d362f29`
(ad core, 179/179 Docker), `690ce9a` (ad app wiring), `ef94166`
(session-expiry surfacing + prefetch retry). iOS Build ✅ on every push;
Core Tests ✅ (or in-progress-on-green-path at handover). Working tree
clean at handover.

**ASSIGNED ELSEWHERE: the beautify pass (theme/typography/gradients) is
another agent's unit — do NOT start it here.** Survey finding that may
help that agent: theming is nearly nonexistent by design so far — one
`Color.primaryBackground` in `RootView.swift:39-41`, everything else is
semantic system styles (`.secondary`/`.tertiary`, materials); a
`Theme.swift` consolidation + violet→gold accent echoing the app icon is
the obvious first slice.

**Pending Queue at handover:**
1. Device test of the latest IPA (the gating item; list below).
2. Beautify pass — OTHER AGENT owns it.
3. Ad handling follow-ups (only if the device test shows ads behaving
   oddly): audio ad length is unknown to the UI (duration 0 → disabled
   scrubber by design); `Advertisement.clickThroughURL` is decoded but
   unused (no external-open in a LiveContainer app anyway).

**Device-test checklist (accumulated):** play >30 s (lock-screen
artwork SIGTRAP + `.task(id:)` launch traps were fixed in `0c7bd99`),
song artwork everywhere, tab switching, lyrics panel, Tune Station
(player + station list), new app icon on the home screen, ads: expect
a yellow ADVERTISEMENT badge, no skip, no feedback controls, history
excludes ads. If anything breaks: Diagnostics (stethoscope, Stations
toolbar) → Copy → paste.

**Traps learned this session (still apply):**
- Docker `swift test`: if `.build` was written by a container at a
  different mount path, PCH errors (`/src` vs `/pkg`) — wipe via a
  container (`docker run … rm -rf .build`), the dir is root-owned so
  host `rm` fails.
- Same-scope shadowing (`let x = try XCTUnwrap(x)`) is a redeclaration
  error in tests — write it correctly the first time.
- Icon generator (`Tools/gen_appicon.py`): never build gradients via
  `rotate()`/`paste()` of gradient tiles (border seams); analytic
  per-pixel maps at 512² upscaled are seamless.
- `JSONValue` now has `.array([JSONValue])` — first array param was
  `ad.registerAd`'s `adTrackingTokens`; exact-byte encoder tests must
  stay green.
- A parallel session may be active in this repo: check `git status`
  before every commit and commit only your own files (this session
  found the crash-fix trio mid-tree and left it alone).
- pydora ad protocol (source-verified this session): playlist ad
  entries are stubs; `ad.getAdMetadata`
  (`returnAdTrackingTokens=true`, `supportAudioAds=true`) → register
  via `ad.registerAd` with the reply's tracking tokens; pithos has no
  ad handling at all.

## Pending Queue

0. **GUI round (user request 2026-11-07 — this session's driver):**
   Unit 1 Last.fm fix ✅ → Unit 2 radio artwork ✅ → Unit 3
   sophisticated player ✅ → **Unit 4 Settings/GUI polish ✅**
   (volume persistence, Settings data management, the list press
   feedback, the station name in the Now Playing header). Unit details
   and root causes are in User Feedback Pending at the top.
1. **User device test of the next IPA** — the player first (transport,
   volume slider, LIVE badge, radio controls), then radio artwork
   (every station row shows a monogram tile or its real logo; the full
   player and the lock screen show the same), then Last.fm (Settings →
   Last.fm → Connect with real credentials; it must now succeed and
   show the live scrobble status line), then the radio flow (R1–R5,
   test list in In Flight / Last Push) and the older pending round
   (light mode, history ratings, lyrics fallbacks, romanization,
   AirPlay).
2. **Bookmarks on device** — user reports they don't work; protocol
   verified against pydora. If the device test still fails, the
   Diagnostics log decides the next step.
3. **Persist the playback volume** — ✅ landed (the slider's level now
   survives a relaunch).
4. **Skip-limit awareness** — ✅ landed (typed core error, a SKIP LIMIT
   badge in the player, the station row marked, and no prefetch
   hammering while the limit is reached).
5. **Explicit-content indicator** — ✅ landed at the only level the
   protocol supports (an account-level badge, since the legacy API has
   no per-track explicit flag).
6. Anything red on the next `gh run list` — repair first.

**FIRST ACTION next session:** `gh run list --limit 5` — confirm the
GUI-polish and Now-Playing pushes are green, then **install the IPA on
the phone** and run the device-test checklist below.

**CI state at the end of this session:** Unit A (`8f066a6`) ✅ Core
Tests 42527855898 + iOS Build 42527855907 · the skip-limit push was
red on the iOS Build (`4e1aa1f`, one type error) and the explicit-
content push inherited it (`8cc40ed`) — **both are covered by the
repair push (`4dd965d`), which is ✅ green** (Core Tests 42531317700 +
iOS Build 42531317702) · the GUI-polish push (`473bc78`) and the
Now-Playing push (`399a7f4`) were in flight at handover.

**Local verification is available again**: the `swift:6.0` Docker image
is on this host, so `cd PandoraCore && docker run --rm -u 1000:1000 -v
"$PWD:/pkg" -w /pkg swift:6.0 swift test` runs the core suite in
seconds (**315/315 green** at the end of this session — 298 before it,
+9 skip-limit, +7 user-settings, +1 repair test). App-target files can
be parse-checked with `swiftc -parse -swift-version 6`; type errors
still only surface on CI.

**Device-test checklist for this session's units:**

- **Settings → Library**: "Clear Play History" shows the number of
  plays and asks to confirm; the Recents sheet is empty afterwards.
  "Clear Artwork Cache" shows the cache size on disk; station and song
  artwork still appears (it is downloaded again).
- **Skip limit**: hard to reproduce on demand — it needs the account's
  daily skips to run out. If the Diagnostics log shows "skip limit
  reached for … — not requesting more tracks", the SKIP LIMIT badge
  must be in the player and the row on Home must read "Skip limit
  reached", and the log line must appear **once** (no retry loop).
- **Explicit content**: sign in with an account that has the filter on
  → Home shows "Explicit content is filtered for this account." under
  the browse row, and Settings → Account reads "Explicit Content:
  Filtered".
- **GUI polish**: tap a station row on Home, a radio row, a browse row
  → the card dips and springs back. The Sign In button and the accent
  swatches dip like the transport buttons.
- **Now Playing**: the station name sits under the album in the header.

## Session handover (2026-11-08, GUI round — Unit 3 landed)

**State:** Units 2 (radio artwork) and 3 (sophisticated player) are
complete and pushed, plus the volume-persistence slice; the working
tree is clean. Local verification was **not** run — the host has no
Swift toolchain and the Docker test run was declined by the user — so
Core Tests + iOS Build ride CI. **CI: Unit 2 ✅, Unit 3 ✅, the
volume push ✅ Core Tests / iOS Build in flight at the end of the
session** — check that one first next session.

**What Unit 3 changed (do not re-derive):**

- `Amphora/Player/PlayerService.swift` — `volume` (0...1) + 
  `setVolume(_:)`, applied to `AVPlayer.volume`; the level is restored
  after a media-services reset. It is **not persisted** (follow-up in
  Pending Queue item 3).
- `Amphora/UI/NowPlayingView.swift` — the transport was rebuilt
  (`transport(for:)`: 58 pt play/pause, matched 56 pt side buttons,
  spacing 52); a **volume slider** sits under the transport; a **LIVE
  badge** replaces the scrubber for radio; the thumbs, the back-15
  button, the lyrics button and the song-level menu actions are hidden
  for radio; the trailing transport button stops a stream instead of
  skipping it.
- `Amphora/UI/MiniPlayer.swift` — the trailing button stops a radio
  stream (glyph and VoiceOver label follow).
- `LiveBadge` (private, in `NowPlayingView.swift`) — the pulsing red
  dot + "LIVE" capsule.

**Unit 4 is next — Settings usefulness + general GUI polish** (the
user's fourth ask: "add and make the settings work and useful"). Unit
1 already added the live Last.fm status line and the profile link, so
what is left is scope-dependent: the user has not named the settings
they want. Sensible candidates, in order of value:

1. ~~**Persisting the playback volume**~~ — ✅ landed (the push above).
2. **History management** — clear the play history (the app has
   history but no way to wipe it from the UI).
3. **Audio quality** — Pandora already serves the best variant the
   account offers (`Track.preferredVariant`); a user-facing preference
   would need a protocol change, so it is out of scope unless the user
   asks for it.
4. General GUI polish, reviewed surface by surface.

**Keep the unit small**: pick one thing, ship it, push, continue. If
the user names a specific setting, that wins over this list.

**Constraints to carry over:** no subagents (project working style);
never wait on a build — push and continue; `PandoraCore` stays UI-free;
`project.yml` and app sources are ours, but `.github/workflows/*` need
user approval; no version bumps; no credentials or tokens in the repo
(it is public).

## Session handover (2026-11-08, GUI round — Unit 2 started, interrupted)

> **Superseded** by the newer 2026-11-08 handover above: Unit 2 was
> finished and pushed. Kept for the record (the findings below are the
> ones the unit was built on).

**State:** the session was cut short by a context handover mid-unit.
Working tree has **one new uncommitted file** and nothing else changed:

- `PandoraCore/Sources/PandoraCore/ArtworkURL.swift` (new, untracked)
  — `ArtworkURLCandidates.candidates(for:)`: the HTTPS-preferred URL
  first, then **the raw URL with its scheme preserved** (`http://` stays
  `http://`) as the last-resort candidate. Pure Foundation, no UI, so it
  belongs in the core package (and the Android port surface).
  `httpsPreferredURL(from:)` and `rawURL(from:)` are the two halves.

**Verified this session (do not re-derive):**

1. **The raw-HTTP bug is real.** `ArtworkCache.candidateURLs` calls
   `normalizedURL` (which force-sets `components.scheme = "https"`) and
   then `upgradedToHTTPS(direct)` — so every candidate is HTTPS and the
   raw HTTP URL is *never* tried, exactly as the handover said. The
   file's own comment ("the raw URL is tried as-is") is false.
2. **ATS key precedence (Apple's docs, fetched):** `NSAllowsArbitraryLoads`
   is **ignored on iOS 10+** if the plist also contains
   `NSAllowsArbitraryLoadsForMedia`, `NSAllowsArbitraryLoadsInWebContent`
   or `NSAllowsLocalNetworking`. So the correct shape is:
   `NSAllowsArbitraryLoads = true` **alone** (it covers every domain,
   including the media and URLSession loads), and **do not** also set
   `NSAllowsArbitraryLoadsInMedia` — adding it would silently disable
   the general exception. `NSAllowsArbitraryLoadsInMedia` alone covers
   AVFoundation media loads only, **not** `URLSession` image loads, so
   it would NOT unblock the favicons.
3. **Live radio-browser data** (`de1.api.radio-browser.info`,
   `/json/stations/topclick/8`): favicons are a mix — `https://` for most
   (armisa.it, francetvinfo.fr, duckduckgo.com, mangoradio.de,
   icecast.anon.fm), one **`http://`** (cdn-profiles.tunein.com), and
   one station with **no favicon at all**. So both the HTTP fallback and
   the generated tile are needed, not just one.
4. **No Swift toolchain on this host** (`swift` not found). Docker is
   installed but the user declined the Docker test run last session —
   treat local `PandoraCore` tests as unavailable unless the user says
   otherwise; Core Tests ride CI.

**Still to do (Unit 2):**

1. **Tests for `ArtworkURLCandidates`** — new
   `PandoraCore/Tests/PandoraCoreTests/ArtworkURLTests.swift`: HTTP raw
   URL yields two candidates (`https://` first, `http://` second);
   HTTPS raw URL yields one; scheme-less yields one (`https://`);
   spaces are percent-encoded; empty string yields none. These are
   pure-function tests — they belong in the core package and run in CI.
2. **Wire it into `ArtworkCache`** — replace the body of
   `ArtworkCache.candidateURLs(for:)` with
   `ArtworkURLCandidates.candidates(for:)`; keep the disk/memory cache
   keyed on the first candidate as today. Delete the now-duplicated
   `normalizedURL`/`upgradedToHTTPS` helpers and fix the file's header
   comment (it currently claims the raw URL is tried as-is).
   **Note:** the ATS exception in `project.yml` must land *before or
   with* this, otherwise the HTTP candidate is blocked by ATS anyway.
3. **ATS exception in `project.yml`** — the target currently uses
   `GENERATE_INFOPLIST_FILE: YES` with `INFOPLIST_KEY_*` settings, and
   `INFOPLIST_KEY_` build settings cannot express a nested dictionary
   (`NSAppTransportSecurity` is a dict). Options: switch the target to
   an explicit `info:` block / `Info.plist` file via XcodeGen's `info:`
   property (XcodeGen writes it and sets `INFOPLIST_FILE`), or keep the
   generated plist and inject the dict another way. **Verify the chosen
   route actually produces the nested dictionary** — a flat
   `INFOPLIST_KEY_` string will not work. The value must end up as:
   `NSAppTransportSecurity → NSAllowsArbitraryLoads = true` and nothing
   else (see precedence point 2).
4. **Generated monogram/gradient tile** — for stations with no favicon
   (and for favicons that are 16×16 blown up to full-player size).
   Suggested shape: a `RadioStationArtwork` SwiftUI view in
   `Amphora/UI/` that renders initials over a deterministic gradient
   derived from the station name (hash → hue), used by the radio row
   (`RadioStationRow`), the mini player and the full player when the
   favicon is missing or too small. `Track.radioTrack(for:)` already
   carries the station name as the track title and the favicon as the
   artwork URL, so the player paths can key off `track.isRadio`.
   The full player should prefer the tile over a tiny favicon; the row
   can show the favicon when it exists and fall back to the tile.
5. **Lock screen** (`NowPlayingService.loadArtwork`) loads via
   `ArtworkCache.image(for:)` — with the HTTP candidate + ATS in place it
   picks up HTTP favicons automatically. Consider whether the lock
   screen should also fall back to a generated tile (probably yes, for
   stations with no favicon).
6. Update `QUEUE.md` (this section + User Feedback Pending item 2 +
   Pending Queue) in the same commit, push, and **continue to Unit 3**
   (sophisticated player) without waiting on CI.

**Constraints to carry over:** no subagents (project working style);
never wait on a build — push and continue; `PandoraCore` stays UI-free;
`project.yml` and app sources are ours, but `.github/workflows/*` need
user approval; no version bumps; no credentials or tokens in the repo
(it is public).

## Session handover (2026-11-07, GUI round — Last.fm unit)

**State:** Unit 1 (Last.fm fix + Settings status) pushed; working tree
clean after push. Local verification NOT run (no host toolchain;
Docker declined) — Core Tests + iOS Build ride CI. The Last.fm fix is
verified by a live protocol probe, not by a device test.

**Handover for the next session — three units remain in the GUI round:**

- **Unit 2 (radio artwork) is next.** Root causes already diagnosed
  (User Feedback Pending item 2): `ArtworkCache.candidateURLs` only
  ever emits HTTPS candidates (the comment claims the raw URL is tried
  as-is, but `upgradedToHTTPS` is applied to it too), so HTTP-only
  radio favicons never load; ATS blocks cleartext anyway. Fix:
  `INFOPLIST_KEY_NSAppTransportSecurity` exception for internet-radio
  media loads (`NSAllowsArbitraryLoadsInMedia`, scoped to media) plus
  a raw-HTTP last-resort candidate in `candidateURLs`, and a generated
  monogram/gradient tile view for stations with no favicon (rows, mini
  player, full player). Watch the 16×16-favicon-blown-up problem: at
  full-player size prefer the monogram tile over a tiny favicon.
- **Unit 3 (player sophistication)**: refine the transport (previous/
  back-15, larger play, next), add a volume slider, and give live radio
  its own controls (LIVE badge instead of a dead scrubber, hide thumbs
  and back-15 on live streams — `FeedbackBar` currently renders for
  radio tracks, which would fire rating intents at a synthetic token).
- **Unit 4 (Settings usefulness + general GUI polish)** — Unit 1
  already added the Last.fm status line + profile link; more useful
  settings (audio-quality preference, history management) only if the
  user asks; keep scope tight.
- **Verification constraint this session:** no host Swift toolchain;
  the user declined the Docker test run. Tests ride CI. If Docker is
  acceptable next session, the loop is
  `docker run --rm -u 1000:1000 -v "$PWD/PandoraCore:/pkg" -w /pkg swift:6.0 swift test`.

## Session handover (2026-10-25, public release session)

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

- **Genre stations (Pandora's featured/popular stations)** — legacy v5,
  verified 2026-10-24 from four sources: `station.getGenreStations`
  (**no parameters** — pydora `pandora/client.py:254`, pancake
  `client.py:193`, python-pandora `connection.py:65`, Sonos Indigo
  `connection.py:126`). Reply: `{"categories": [{"categoryName": …,
  "stations": [{"stationId": …, "stationToken": …, "stationName": …,
  "categoryName": …}]}], "checksum": …}` (pydora `models/station.py`
  `GenreStation`; pancake `GenreStations.__dict_key__="categoryName"`,
  `__list_key__="stations"`). **Create a real station with
  `station.createStation {"musicToken": <the genre station's
  stationToken>}`** — xivpiano `PandoraClient.cs:261` ("making one uses
  its token as the music token"), pydra `GenreStation.get_playlist`
  ("Create a real station using the token"); pithos's search-genre
  results use the same `musicToken` create shape
  (`add_station_by_music_id`). Genre stations themselves have no
  playlist — you create a personal station from them and play that.
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
