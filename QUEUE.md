# QUEUE.md

Working memory for the Amphora build pipeline. Owned by the agent.
Updated in the same commit as the work it describes.

## Current Milestone

**M6** — performance & robustness. (M0–M5 code complete; M2 confirmed on
device 2026-10-23 "everything so far works". M3–M5 device check pending —
superseded by the crash report below.)

## User Feedback Pending

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

1. **Release follow-up** — v0.1.0 runs green on the rewritten HEAD;
   release asset is the 0.1.0 build (swap command in the 2026-10-25
   handover if not).
2. **User device test of this round's IPA** — the gating item; the
   checklist is in the 2026-10-24 handover section above (tabs,
   appearance themes, hero, player menu/quality chip, sign out,
   bookmarks-on-device investigation).
3. **Bookmarks on device** — user reports they don't work; protocol
   verified against pydora this session (endpoints/params/decode all
   match). If the device test still fails, the Diagnostics log decides
   the next step.
4. Anything red on the next `gh run list` — repair first.

**FIRST ACTION next session:** `gh run list --limit 5`. If red, read
the failure summary annotation and repair before any new unit.

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
