# OmaTimeAtBandcamp — v3 UI Spec

For: OpenCode working in the existing OmaTimeAtBandcamp repo on branch `v2`.
Owner: David Sewall. Date: 2026-10-24.

## Context

v2 is complete (see `docs/omatimeatbandcamp-v2-spec.md` phase results and
`V2-NOTES.md`). This spec records the v3 UI phase only. The Radio feature is
**not** in scope; it is a separate spike later.

Baseline before any v3 change: 86 unit tests pass (5 skipped), 5 live fixture
tests pass, 281 QML checks pass.

## Scope

THE V3 CHANGE LIST (owner-decided):
   a. Header: replace the ⋯ button with a gear (settings) icon
      button, same BcButton style. Its menu contains: "Refresh
      library", "Hide pre-orders" (checkable, keeps its persisted
      state), and "Log out / Clear Bandcamp session" (existing
      confirmation flow). Remove Refresh and Hide pre-orders from
      the toolbar.
   b. Search row: add a magnifying-glass icon to the left of the
      search field; shorten the field. DELETE the Bandcamp,
      Discover, Editorials, Radio, and Feed buttons entirely.
      Keep only Collection (renamed from "Your Collection"),
      inline in the search row to the right of the field, keeping
      its current behaviour (URL built from library-cache username,
      disabled until known). The links row disappears.
   c. Toolbar: DELETE the "Shuffle: On/Off" toolbar button.
      Albums (N) / Playlists (N) and Sort stay as they are.
   d. Footer: add a Shuffle icon button to the transport group,
      same BcButton style as Prev/Play/Next, highlighted/tinted
      when On, toggling the CURRENT CONTEXT's shuffle state (the
      per-context state model from v2 is unchanged — only the
      control moves). RIGHT-JUSTIFY the whole transport group
      (Shuffle + Prev + Play/Pause + Next) in the footer.
      Now-playing text stays left.
   e. Detail pane: REMOVE the Play/"Play available" button from
      the pane header. Playback starts from a double-click, Enter,
      or the footer. ("Play available" text for pre-orders moves
      into the header's availability line if it isn't already
      conveyed there — do not lose the information.)
   f. Track clicks: single-click SELECTS only (never starts
      audio); DOUBLE-click a track starts playback with the queue
      starting at that track (existing queue/shuffle rules apply).
      Unreleased pre-order tracks stay non-playable by any gesture.
   g. Borders/colour: use ONE shared border colour for the album
      list pane, the detail pane, and the footer (today the detail
      pane has a light-blue border and the others differ). Take the
      colour from the theme/detail pane so everything matches.
   h. Bar (Quickshell): REMOVE the bar-art widget entirely (the
      sibling …omatimeatbandcamp-art plugin: remove its shell.json
      entry and the plugin symlink; back up shell.json first, as
      before) and REMOVE the play/pause suffix — the bar shows
      plain "BC" at all times. Keep the bar click behaviours
      (left = toggle window, right = play/pause, middle = next).
      Backend cover art stays (MPRIS still uses the local file).
   i. RTL fix: artist/title/track names containing right-to-left
      script (e.g. Arabic) currently render pushed right in album
      rows and centre the footer's "Artist · Album" line. Force
      left alignment and disable layout mirroring on all
      title/artist/track text items so mixed-direction names align
      like everything else.
   j. Compact pass: modestly reduce vertical padding in list rows
      and section spacing, keeping two-line wrapping and the
      660 px popup cap. If a reduction hurts readability or breaks
      a measured-wrap check, stop at the last good value and say so.

## Hard rules

- Never open, cat, or read `~/.config/omatimeatbandcamp/credentials.toml`
  or `cookies.txt`. `ls -l` only — path and mode, never contents.
- Never print, log, or commit a stream URL, cover-art URL, or any credential
  value. The `mpv --load-scripts=no` spawn flag and the MPRIS whitelist fence
  stay exactly as they are.
- `shell.json` lives outside the repo: back it up before editing and report
  those changes separately from repo commits.
- Some v2 harness checks pin behaviour this list deliberately removes. Update
  those checks to v3 and enumerate every such change with its reason. Never
  weaken a check to make failing code pass.
- Report test results as raw counts from the actual run.

## Acceptance

The v2 acceptance checklist continues to hold except where v3 supersedes it:
no Play control in the detail header; single-click selects and double-click
plays tracks; one Collection link; gear menu owns Refresh / Hide pre-orders /
Log out; footer owns the per-context Shuffle control; plain `BC` in every
playback state; matching pane/footer border colour; left-aligned, non-mirrored
title/artist/track text.

## Implementation result (2026-10-24)

All ten changes a–j are implemented. Notes:

- **Border colour**: one `paneBorderSpec` (`Border.flat(Util.alpha(Color.accent,
  0.75), Style.normalBorderWidth)`) is used by `leftPane`, `detailPane` and
  `footer`.
- **Availability line**: a partially released pre-order now reads
  `N of M tracks available · Play available`; a fully unreleased one keeps
  `0 of M tracks available`. Information from the removed header button is not
  lost.
- **RTL**: every title/artist/track text item is explicitly `Text.AlignLeft`
  with `LayoutMirroring.enabled: false`. (Qt's `Text` has no `layoutDirection`
  property; `LayoutMirroring` is the supported switch.)
- **Compact pass**: content spacing `md` → `sm`; album-row padding 14 → 10;
  track-row minimum/padding 34/14 → 30/10. The 660 px popup cap and the
  measured two-/three-line wrapping checks are unchanged.
- **Bar art**: `bar-art/` was deleted, the sibling plugin symlink and the
  `shell.json` entry were removed (shell.json is outside this repo and was backed
  up first). Backend cover caching is kept for MPRIS, but the `RTMIN+8` Waybar
  signal is gone.

Raw results after the change:

- Unit tests: `Ran 86 tests ... OK (skipped=5)`
- Live fixture tests: `Ran 5 tests ... OK`
- QML harness: **294 checks** passed — phase 1 265, phase 2 7, real-data 16,
  and 6 script-side checks. Baseline was 281.
- `omarchy plugin validate .`: OK; `qmllint` reports import/unqualified-access
  warnings only, no errors.

## v3.1 polish pass (owner-decided, 2026-10-24)

Scope: one control height, a title-only header with the gear moved into the
search row, the magnifier moved inside the field, a tighter footer, and a
shuffle dot. Menus, Collection behaviour, RTL alignment, borders, keyboard
handling, playback, the `mpv --load-scripts=no` spawn flag and the MPRIS
whitelist are unchanged.

### What changed

- **One control height.** `Panel.controlHeight` is the shared token and equals
  BcButton's existing height (`Style.spacing.controlHeight`, 28 px in this
  theme). The search field, gear, Collection, Albums (N), Playlists (N), Sort
  and the four footer transport buttons all bind to it. The search field keeps
  the stock 30 px look by reducing its vertical padding to 4 px; the harness
  asserts its implicit text still fits at 28 px.
- **Header.** The title row now contains only `OmaTimeAtBandcamp`; the title is
  `Style.font.subtitle + 2` (15 px, +2 over the v3 13 px). The gear moved to
  the search row and keeps the same `settingsButton` object, menu items,
  placement code and confirmation flow.
- **Search row.** Left to right: flexible search field, Collection, gear. The
  field never drops below half the row and shares the control height. Its left
  edge is flush with the album list and toolbar below (no indent).
- **Magnifier.** The separate left-hand glyph is gone. A dimmed magnifier
  (Nerd Font glyph, 16 px, the footer transport icon size) is a child `Text`
  anchored inside the field's right end; `enabled: false`, no input handlers,
  and extra right padding so typed text never runs under it. The harness clicks
  it and types to prove it blocks neither focus nor text entry.
- **Footer.** The blank band between the now-playing text and the progress bar
  is halved. The footer height is driven by the text height so both states fit:
  81 px for the two-line harness state (gap 6 -> 3 px) and 74 px for a one-line
  title (gap 21 -> 10.5 px). The popup is correspondingly shorter (612 -> 609
  px in the long-title harness state, about 602 px with one line), still under
  the 660 px cap, with title, artist and progress bar all inside the footer.
- **Shuffle dot.** A 4 px accent dot inside the shuffle button's bottom padding,
  centred on the glyph, visible only while `root.shuffleOn` is true for the
  current context. The existing `selected` tint is unchanged and the button
  height stays 28 px.

### Tests (raw counts)

Baseline on the v3 build (commit `68b90f8`), before any v3.1 change:

- Unit: `Ran 86 tests ... OK (skipped=5)`
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK`
- QML (`tests/qml/run.sh`): **294** checks = phase 1 265 + relaunch 7 +
  real-data 16 + 6 script-side.

After v3.1:

- Unit: `Ran 86 tests ... OK (skipped=5)` (unchanged; QML-only change)
- Live fixtures: `Ran 5 tests ... OK` (unchanged)
- QML: **317** checks, all pass = phase 1 288 + relaunch 7 + real-data 16 +
  6 script-side. That is +23 QML checks.
- `omarchy plugin validate .`: exit 0. `qmllint` (Qt 6 binary): no errors,
  only the pre-existing import/unqualified-access warnings.
- Credential files were not opened; only their paths/modes are reportable.
  No stream URL, cover-art URL or credential value was printed or committed.

### Harness checks updated (and why)

1. `header has a gear (settings) button, not the old ⋯ overflow` ->
   `header row contains ONLY the title (the gear is no longer in it)` plus
   `gear (settings) button still exists, with its menu, and now lives in the
   search row`. Reason: change b moves the gear out of the title row.
2. `search row has a magnifying-glass icon` -> `the old left-hand search icon
   is gone` plus the new inside-the-field checks. Reason: change d removes the
   external glyph.
3. `the magnifier sits to the left of the search field` -> `magnifier sits
   inside the field's right end, not to its left`. Reason: change d.
4. `gear menu opens` -> `gear menu opens from its search-row position` (same
   open/menu-kind assertion, now also asserts the button's new parent).
   Reason: changes b/c.
5. No height, spacing or position check was weakened. The existing "all buttons
   share ONE height" check is unchanged and still passes at 28 px; the new
   check extends that measurement to the search field and every named control.
   A new constant `v3PopupHeight = 612` is the measured v3 baseline for the
   "popup is shorter" assertion.

### New harness coverage

- Header has exactly one child (the title); title text and +2 pt size.
- Search row order field -> Collection -> gear; field >= half the row; field
  left edge == album list == toolbar; text fits the shared height.
- Magnifier inside the field's right end, footer-glyph size, dimmed, disabled,
  no input handlers; clicking it focuses the field and typing reaches search.
- All ten named controls measure exactly one height, equal to the shared token.
- Gear menu opens from the search row and its existing entries still work.
- Shuffle dot: 3-4 px, centred, inside the button, height unchanged; visible
  for an On album, hidden for an Off playlist while the album is On, visible
  for the On playlist, remembered back on the album, hidden again when that
  album is turned Off.
- Footer: two-line gap 6 -> 3 px, footer 84 -> 81 px, popup 612 -> 609 px,
  under the 660 px cap, title/artist/progress all inside the footer without
  overlap. The one-line formula is the same halving (74 px footer).

### Deviations / owner-visible decisions

- **Search field width.** It is exactly half the row (444 of 888 px in the
  harness), flexible with the window and never below half, as requested.
  Collection and the gear follow it immediately, so the area to the right of
  the gear is empty; the list did not ask for the group to be right-justified
  (unlike the v3 footer transport), so it was left in the stated order.
- **Footer height is content-driven**, not a fixed 84 px, so the gap is halved
  for both one-line and two-line titles without clipping. The popup therefore
  becomes slightly shorter or taller by one text line when the now-playing
  title changes; it remains under the 660 px cap.
- **Title size is `subtitle + 2` (15 px)** rather than the next named token:
  `title` is only +1 and `heading` is +3, while the request was about +2 pt.
- The search field's vertical padding is 4 px (stock 7) to reach the shared
  28 px; the harness asserts the text still fits.

### Owner live check

1. `omarchy restart shell`, then open the panel from `BC`.
2. Header: only the title, slightly larger. Gear is in the search row, after
   Collection; open it and confirm Refresh library / Hide pre-orders / Log out
   still work and the menu drops from the new position.
3. Search: the magnifier is dimmed inside the field's right end; click it and
   type (focus and text must work); the field's left edge lines up with the
   album list and toolbar.
4. Measure by eye: search field, gear, Collection, Albums, Playlists, Sort and
   the four footer buttons are all one height.
5. Footer: the gap above the progress bar is visibly tighter and the popup is
   shorter; play a long-titled track and confirm nothing overlaps or clips.
6. Shuffle: with an album selected, turn Shuffle On (dot appears under the
   glyph and the tint stays); select a different album/playlist (no dot); come
   back (dot returns); turn it Off (dot disappears).
7. Spot-check that menus, Collection, RTL album text, borders, keyboard
   navigation and playback behave exactly as before.

## v3.2 shrink pass (owner-decided, 2026-10-25)

Scope: a narrower popup, a content-driven list/detail row height, a flexible
search field, and an idle footer that collapses its progress row. Control
heights, the gear menu, Collection, the shuffle dot, RTL alignment, borders,
keyboard handling and playback behaviour are unchanged.

**Process note.** This section was appended by the completion run after the
original v3.2 session was cut off by a usage limit. The code and harness changes
were already in the working tree; the section is reconstructed from that diff
and from a fresh full-suite run on 2026-10-25. The v3.2 baseline (317 QML
checks) is the v3.1 figure recorded above and was **not re-run** in this
completion session because the changes were already present. Every final figure
below was reproduced in this run.

### What changed

- **Narrower popup.** `contentWidth` is
  `fittedContentWidth(Style.space(835))` (was 920). Landed on **835 px**
  (accepted range 820–840; not exactly 830). In the harness the search row is
  803 px: field 673.125, Collection 93.875, gear 28, row spacing 4.
- **List/detail proportions.** The left pane is 42.2% of the row (was 38%);
  the detail pane takes the rest. This keeps the narrower list wide enough that
  no real-library title that fitted at the v3.1 width starts truncating. (The
  harness asserts equal heights, not the width ratio.)
- **Content-driven row height.** New `detailCapHeight = Style.space(396)`,
  `detailMinTrackRows = 6`, `detailBaseTrackRowHeight = Style.space(30)`,
  `detailRowContentHeight = detailHeader.height + Style.spacing.sm +
  trackList.contentHeight`, and `libraryRowHeight = detailContextActive ?
  max(180, min(396, detailRowContentHeight)) : 396`. `detailContextActive` is a
  non-empty query, a selected playlist or a selected album. Both panes bind to
  `libraryRow.height`.
- **Search field flexes.** `width = max(0, searchRow.width -
  collectionButton.width - menuButton.width - 2 * searchRow.spacing)`; the
  v3.1 half-row rule is gone.
- **Idle footer collapses.** `footer.showProgress = root.playing ||
  root.paused`; the progress row is visible only then. Footer height is
  `5 + max(nowPlaying.implicitHeight, transportRow.height) +
  (showProgress ? footerGap + progressRow.height : 0) + 5`. The error notice
  lives in `nowPlaying`, so an idle error still renders with the bar hidden.
- **Harness helper.** `showRow()` now scrolls with `ListView.Contain` instead
  of `ListView.Visible`, so a row whose edge is barely on screen is fully
  brought into view before the harness clicks its centre. Reason: v3.2's
  content-driven heights changed scroll offsets. This changes no assertion.

### Height measurements (QML harness, 2026-10-25)

| State | Row height | Popup content height | Notes |
|---|---:|---:|---|
| Nothing selected (library browsing) | 396 | 570 | cap row; idle footer |
| 4-track album | 180 | 354 | floor (6 × 30); track list content 120, viewport 136, no scroll |
| 120-track album | 396 | 570 | cap; track list content 3600, viewport 352, scrolls |
| 4-track playlist | 180 | 354 | floor |
| Search, 4 results | 180 | — | floor |
| Search, 120 results | 396 | — | cap; content 3600, viewport 352, scrolls |
| Playing footer (two-line long title) | — | 609 | footer 81 px |
| Idle footer (same title) | — | — | footer 58 px |
| Idle footer with stream error | — | — | footer 58 px; error visible, progress hidden |

Both panes measured exactly the row height in every tested state (nothing
selected, small album, large album, playlist, 4 and 120 search results) and
their bottom edges coincided. The v3.1 playing-state popup is 609 px (footer
81); the nothing-selected v3.2 state is 570 px because the footer is
idle/collapsed. The 4-track state is 354 px.

### Tests (raw counts)

- Unit: `Ran 86 tests ... OK (skipped=5)`
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK`
- QML (`tests/qml/run.sh`): **344** checks = phase 1 315 + relaunch 7 +
  real-data 16 + 6 script-side. All `FAILS=0`. Baseline 317 (recorded in the
  v3.1 section) -> +27 QML checks, all in phase 1.
- Real library: `[real] truncated row titles (0):` and `[real] truncated detail
  titles (0):`; the existing single-line row assertion passed. The two
  truncation logs are diagnostics, not assertions (see deviations).
- `omarchy plugin validate .`: exit 0.
- `/usr/lib/qt6/bin/qmllint Panel.qml Service.qml BcButton.qml`: exit 0, no
  errors; warnings only (the pre-existing import/unqualified-access warnings
  plus the existing Service.qml `QVariantMap`/`QVariantHash` warning).
- Credential files were not opened; no stream URL, cover-art URL or credential
  value was printed or committed.

### Harness checks updated (and why)

1. `v3.1: the search field is flexible and at least half the row` ->
   `v3.2: search field takes all row width left after Collection, gear and the
   two gaps` (exact width equation, plus still > half in the fixture). Reason:
   requirement c removes the half-row rule.
2. Footer measurement step: the v3.1 footer checks used to run before
   `isPlaying` was set; v3.2 sets playing before the measurement, records
   `playingFooterHeight`, and adds `v3.2: playing keeps the progress row
   visible`. Reason: with idle collapse, measuring before the state change would
   measure the collapsed footer and the v3.1 gap/height checks would be
   meaningless. No threshold was loosened.
3. `showRow()` helper changed from `ListView.Visible` to `ListView.Contain`
   (helper, not an assertion). Reason: content-driven heights changed scroll
   offsets; a row could be only partly visible when the harness clicked its
   centre.
4. Real-data: added diagnostic logs for all truncated row titles and for
   truncated detail titles; the existing `across all albums no row is truncated
   on a single line` assertion is unchanged. Reason: verify the narrower window
   did not introduce truncation.

### New harness coverage

- Popup content width is 835 px (820–840 accepted).
- Search field width equals row − Collection − gear − 2 × spacing.
- Row height: cap for nothing selected; floor 180 and below cap for 4-track
  album/playlist/4 search results; cap 396 for 120-track album/120 search
  results; large lists scroll.
- Both panes exactly equal the row height and share a bottom line in every
  tested state.
- Playing keeps the progress row and full footer height; idle hides it and
  shrinks the footer; paused keeps it; idle error still renders inside the
  footer and does not force the bar back.
- Real library: logs 0 truncated row titles and 0 truncated detail titles; no
  HTML entities.

### Deviations / owner-visible decisions

- **Width is 835 px**, not 830: inside the accepted 820–840 range.
- **List pane is 42.2%**, not the old 38%, to protect titles at the narrower
  width. The detail pane is correspondingly 57.8%. This is a deliberate change
  from "roughly 38/62".
- **The 4-track floor is 180 px**, so a 4-track album does not shrink all the
  way to its content (detail header + 4 × 30 rows is below the six-row
  minimum). This is the specified minimum, not a bug.
- **Idle footer is 58 px** for the harness's two-line title, versus 81 px
  playing; the collapsed state hides the whole progress row (bar and both time
  labels), not just the bar.
- **The v3.2 spec section was missing when this completion run started.** The
  earlier session had left the code and harness changes uncommitted but had not
  appended the section. This section is reconstructed from the diff and the
  fresh run; the 317 baseline was not re-run here (marked unverified in this
  run), while the 344 final count, 86/5 unit, 5 live, 0 truncation logs,
  validate and qmllint results were reproduced.
- **Truncation strength.** The harness asserts no row is truncated on a single
  line; the 0-truncation logs for all row titles and all detail titles are
  observations, not separate assertions. So "nothing truncates at all" is
  verified by the log for this library snapshot, not by a dedicated check.
- The v3.2 run did not change the `mpv --load-scripts=no` flag or the MPRIS
  whitelist.

### Owner live check

1. `omarchy restart shell`, then open the panel from `BC`.
2. Confirm the popup is narrower and the list/detail split still looks
   balanced; scroll the album list and check long titles still wrap to two
   lines without ellipsis.
3. Select a short album/playlist: the popup should shrink to the six-row
   floor; select a long album: it should stop at the old height and scroll.
4. Search with a few results and with many; the row should size by result count
   and cap at the old height.
5. Stop playback: the progress bar and times disappear and the footer gets
   shorter; play/pause: they return. Force a stream error while idle: the error
   must remain visible.
6. Spot-check the gear menu, Collection, shuffle dot, RTL text, borders,
   keyboard navigation and playback are unchanged.

## Post-v3.2 fix (2026-10-25): first-track footer freeze

Owner report: on the first track of a session the footer elapsed time and
progress stayed at 0:00 indefinitely while audio played normally; only an
interaction (track change, buttons) revived it; pause/play reached mpv and the
button state flipped correctly.

### Root cause

mpv keeps its `pause` property across `loadfile`. The owner's player had been
left paused (verified live: `paused=true`, a track loaded), so the first track
of the next session loaded paused. `Service.playCurrent()` assumed a new load
starts playing (`isPlaying=true`, `isPaused=false`), and `applyPlaybackStatus()`
ignored mpv's `paused` value. The first click on the footer button therefore
unpaused mpv (audio started) while flipping the service's `isPaused` the other
way; the 1 s position timer was gated on `isPlaying && !isPaused`, so it stopped
polling exactly while mpv was playing. The position could then only change when
something re-armed the poll (a track change calls `playCurrent()` and clears
`isPaused`). Pause/play kept toggling both sides, so the icon looked correct.

### Reproduction (harness-isolated mpv, own socket, `--ao=null`)

Fresh Service, an isolated mpv left paused, one local track, no track change:

```
t=1..3  svc.position=0  isPlaying=true  isPaused=false   mpv: paused=true,  time-pos=0
        (owner clicks the footer Play/Pause button)
t=4..11 svc.position=0  isPlaying=true  isPaused=true    mpv: paused=false, time-pos 0.99 -> 7.99
```

Service position stayed 0 while mpv's `time-pos` advanced; after the fix the
same probe reports `svc.position=0.74` at t=1 with `mpv paused=false`, no click.

### Fix

- `mpvctl.do_load()` sends `set pause no` after a successful `loadfile` (every
  load from the plugin is meant to play; a rejected load never touches pause).
- `applyPlaybackStatus()` adopts mpv's `paused` value (skipped while a control
  or load command is in flight, and while mpv is idle where `pause` is
  meaningless), so the two flags cannot stay inverted.
- The position timer runs while `isPlaying` (including paused) and polls at
  250 ms until the first second is on the clock, then 1 s.
- `playbackStartedAt` is refreshed whenever `isPlaying` becomes true, so the
  Phase 5 2.5 s load grace and 8 s dead-stream rule always run from the real
  start (the existing Phase 5 tests still set it to 0 explicitly and pass).

Phase 5 failure handling is unchanged: same 2.5 s grace, same 8 s rule, same
`fatal`/stream taxonomy, same 3-skip cap. `--load-scripts=no` is untouched.

### Startup-latency rider (measured before changing)

Cold start per fixture tone, fresh Service + fresh isolated mpv, play command to
first position advance (`mpv` = first `time-pos > 0`, `svc` = first service
position > 0):

| Track | mpv before | svc before | svc after |
|---|---:|---:|---:|
| 0 (8 kHz, 8 s) | 353 ms | 1063 ms | 346 ms |
| 1 (11 kHz, 12 s) | 343 ms | 1041 ms | 341 ms |
| 2 (16 kHz, 20 s) | 240 ms | 1041 ms | 343 ms |
| 3 (22 kHz, 30 s) | 247 ms | 1144 ms | 341 ms |
| 4 (44 kHz, 15 s) | 247 ms | 1044 ms | 340 ms |

Audio start is mpv-bound (~240-350 ms, local files; real Subsonic streams are
server-bound at ~1-2 s to first `time-pos`). The rest of the old delay was the
1 s poll phase, not the server. The 250 ms fast-start poll removes ~0.7 s from
the first position advance and ~0.7 s from the first visible `0:01`. No mpv
cache/prefetch change was needed; none was made.

### Tests (raw counts)

- Unit: `Ran 88 tests ... OK (skipped=5)` (baseline 86; +2 `do_load` pause tests).
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK`.
- QML (`tests/qml/run.sh`): **355** checks = phase 1 326 + relaunch 7 +
  real-data 16 + 6 script-side. All `FAILS=0`. Baseline 344 -> +11.
- New QML checks: paused mpv flips the service to paused and the footer to
  Play; unpausing flips it back and advances the position; a transient poll
  failure keeps the last position and the next good poll advances; the
  first-track regression checks (tone fixture present, isolated mpv paused
  beforehand, the first track plays, its position advances with no track change,
  and the elapsed label leaves 0:00). The real-mpv step uses the harness's own
  socket and `--ao=null`; it never touches the owner's player.
- Harness support (no assertion changed): `run.sh` generates a 10 s tone with
  the stdlib and exports `HARNESS_TONE`; the runner gained a `pauseUntil` wait
  because `TestCase.wait()` from the runner aborts the QML engine (reproduced
  and removed).
- No existing check was changed or loosened.

### Owner live check

1. Leave a track paused, restart the shell, play any track: audio should start
   without a second click and the footer should move within about a second.
2. Pause and resume: the footer time should hold while paused and continue from
   the same place; the icon should match the audio.
3. Track changes, seek, end-of-track advance and the error notice are unchanged.

## v3.3 grouped search results (owner-decided, 2026-10-26)

Scope: search finds NAMES as well as tracks. A non-empty query now renders
grouped results — Albums, then Playlists, then Tracks, each under a small header
with its count, and only when that section has matches. Empty-query behaviour,
track matching, playback, per-context shuffle, the v3.2 height model and every
other view are unchanged.

### Baseline (fresh session, before editing)

- Unit: `Ran 88 tests ... OK (skipped=5)`
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK`
- QML (`tests/qml/run.sh`): **363** checks = phase 1 334 + relaunch 7 +
  real-data 16 + 6 script-side. All `FAILS=0`.

The baseline matched the expected 88/5 unit, 5 live and 363 QML figures, so
editing proceeded.

### What changed

- **`Model.searchIndex`** now also returns matching playlists (name, case-
  insensitive substring). Its album and track matching loops are otherwise
  unchanged: tracks still match title/artist/album and playlist name exactly as
  before, so what a track match *is* did not change.
- **`Service.search`** keeps the existing track results and orders the Albums
  group with the current Albums sort (`sortMode`). Search remains global, so
  Hide pre-orders does not remove album names from it. Playlists stay in normal
  playlist order; Tracks stay in today's order.
- **`Panel.qml`** builds a flattened `searchRows` model for a non-empty query:
  an `Albums (N)` header + album rows, then `Playlists (N)` + playlist rows,
  then `Tracks (N)` + track rows. Header rows are non-interactive and skipped
  by Up/Down. Empty query still uses the normal Albums/Playlists list, with no
  headers.
- **Interaction.** Single-click selects (cursor) without starting audio or
  navigating. Double-click / Enter on an album row clears search, switches to
  the Albums tab, selects that album and shows its tracks; a playlist row does
  the same on the Playlists tab. Neither starts playback. A track row plays
  exactly as before, with the search TRACK results as the playback context for
  Next/Previous. Group headers are never part of the playable queue.
- **Height.** Search-context height now uses the taller of the right-hand track
  content and the left grouped list (headers + items), under the existing
  6 × 30 px floor and 396 px cap. The left pane's 2 px inner margin is included
  so the last grouped row is fully visible. Both panes still bind to the one
  row height and keep coincident bottom edges.
- **Empty states.** A query matching nothing anywhere shows `No results` in
  both panes. A query that finds an album/playlist but no tracks shows
  `No matching tracks` on the right while the named result stays in the left
  list.

### Tests (raw counts)

- Unit: `Ran 88 tests ... OK (skipped=5)` (unchanged; the change is JS/QML).
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK` (unchanged).
- QML (`tests/qml/run.sh`): **388** checks = phase 1 358 + relaunch 7 +
  real-data 17 + 6 script-side. All `FAILS=0`. Baseline 363 -> +25 checks
  (24 phase 1, 1 real-data).
- `omarchy plugin validate .`: exit 0.
- `/usr/lib/qt6/bin/qmllint Panel.qml Service.qml BcButton.qml`: exit 0, no
  errors; only the pre-existing import/unqualified-access warnings and the
  existing `Service.qml` `QVariantMap`/`QVariantHash` warning.
- Credential files were not opened (paths/modes only). No stream URL, cover-art
  URL or credential value was printed or committed. `--load-scripts=no` is
  untouched.

### Harness checks updated (and why)

No existing check was changed, loosened or removed. All existing v3/v3.1/v3.2
checks still pass unchanged. One real-data assertion was **added** on top of the
existing diagnostic: the log's 0 truncated row titles is now also asserted.

### New harness coverage

- An album-name query returns the album in `Albums (1)` and places it above
  `Tracks (4)` (header -> album -> tracks header -> tracks); no empty
  Playlists section.
- A playlist-name query returns the playlist in `Playlists (1)` above
  `Tracks (4)`.
- A track-only query renders only `Tracks (4)` — no empty album/playlist
  headers.
- Activating an album row leaves search, lands on the Albums tab with that
  album selected and its 4 tracks shown, and does not start playback.
- Activating a playlist row does the same on the Playlists tab.
- Down from search skips the section header and lands on the first track;
  further Down never lands on a header; Enter activates the selected track.
- Track activation uses exactly the search TRACK results as queue/context
  (4 tracks, clicked track index, `search` context); Next stays in those
  results and no header becomes playable.
- A no-match query shows the `No results` state in both panes.
- With groups shown, the row height fits the full left content (headers +
  items), stays below the cap and above the floor, and both panes remain
  exactly equal with the same bottom line.
- Real-data smoke still reports `[real] truncated row titles (0)` and now
  asserts 0 truncated row titles as well.

### Deviations / owner-visible decisions

- **Album group order** follows the current Sort choice (the Albums list's
  normal order) but ignores Hide pre-orders, because search is global: a hidden
  pre-order name can still be found. Tracks keep today's exact matching and
  order.
- **Section labels** are `Albums (N)`, `Playlists (N)`, `Tracks (N)` — the same
  count style as the toolbar. Headers are caption-sized, bold and dimmed.
- **Name activation is navigation, not playback.** An album/playlist row shows
  its tracks; it does not start audio. Only a track row starts playback.
- **Right pane remains the track-results pane.** A name-only match leaves it
  empty with `No matching tracks`; it is not replaced by an album/playlist
  detail pane. This keeps the existing search playback context and track list
  intact.
- **Height includes the grouped left list.** For the tested album query the row
  is 247 px (left content 245 + 2 px inner margin), with the right track list
  fitting inside it; both panes are 247 px and end on the same line.
- No changes to shuffle/per-context state, track matching, playback, the
  `--load-scripts=no` spawn flag, the MPRIS whitelist or any other view.

### Owner live check

1. `omarchy restart shell`, open the panel, and type an album name (try
   `Crocbrain`, `La Dee La La` or `First Impressions`): the album appears under
   `Albums (N)` above the matching tracks.
2. Type a playlist name (try `Postpunky?` or `Rock & Roll Faves`): it appears
   under `Playlists (N)` above the tracks.
3. Type a track-only phrase (try `The White Lady`): only `Tracks (N)` appears,
   with no empty album/playlist headers.
4. Double-click (or select and press Enter on) an album row: search clears, the
   Albums tab opens with that album selected and its tracks shown; do the same
   for a playlist row on the Playlists tab. Neither should start audio.
5. Double-click / Enter a track row: it plays as before; Next/Previous should
   stay inside the search track results, and Shuffle should still be the search
   context's own state.
6. With groups on screen, check the popup height fits all rows and the two
   panes end on the same line; long grouped lists should cap and scroll.
7. Type nonsense (`zzzz`): both panes should say `No results`. Esc clears the
   query and restores the normal list.

## v3.4 session-only user queue (owner-decided, 2026-10-26)

Scope: a Spotify-style "Up Next" queue that sits on top of whatever context is
playing. It starts empty on every shell launch, holds tracks in the order the
user added them, and disappears with the session. Playback order, the existing
per-context shuffle, the v3.2 content-driven height and every other view keep
working as before.

### Baseline (fresh session, before editing)

- Unit: `Ran 88 tests ... OK (skipped=5)`
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK`
- QML (`tests/qml/run.sh`): **388** checks = phase 1 358 + relaunch 7 +
  real-data 17 + 6 script-side. All `FAILS=0`.

The baseline matched the expected 88/5 unit, 5 live and 388 QML figures, so
editing proceeded.

### What changed

- **`UserQueue.js`** is a new, mutable-free ES5 model with no Qt imports:
  `{ pending, current, resumeIndex, history }`. The same file is imported by
  `Service.qml` and run under Node by the unit tests. Every operation returns a
  new state so QML bindings stay reactive.
- **The user queue is separate from the context queue.** `Service.qml` keeps its
  existing `queue` / `queueIndex` untouched underneath any queued track, so the
  context's own order (including shuffle) is preserved for when the queue
  drains. `userQueueState` drives the new `userQueue`, `currentUserTrack`,
  `userResumeIndex` and `userQueueActive` properties.
- **Adding.** Play Next inserts at the FRONT, Add to Queue appends at the END;
  duplicates are allowed. Only streamable tracks can enter the queue: the UI
  disables both actions on an unstreamable row and the service refuses the
  track too. Album/playlist adds append their streamable tracks in album order,
  skip unstreamable ones, and report `Added N tracks to queue` plus
  `· M skipped (not streamable)` when anything was skipped.
- **One advance path.** Footer Next, MPRIS Next, the media key and the
  end-of-track handler all go through the same `advanceUserQueueIfNeeded()`
  branch: a non-empty user queue always plays its head and removes it; otherwise
  the context advances exactly as before. A failed stream uses the same rule
  (`advanceUserQueueAfterFailure`) and does not pretend the failed track played.
- **Order is added order.** Queued tracks play in the order they were added even
  when the underlying context is shuffled. Shuffle continues to reorder only the
  context, including while a queued track is playing.
- **Drain.** The state remembers the context position after the track that was
  playing when the queue took over. When the last queued track ends (or Next
  goes past it), the context resumes at that position. The interrupted track is
  never replayed. If it was the last track in the context, playback stops.
- **Previous.** While a queued track plays, Previous steps through actual
  history: the previous queued item, then the interrupted context track (which
  becomes current again and the two queued items go back to the front of
  pending, in order). Outside a queue takeover, Previous is byte-for-byte the
  old context behaviour.
- **Starting something new.** Starting playback in a different context (another
  album, playlist, search result set, or a single track) clears the queue.
  Selecting another track in the same context keeps the pending queue but
  releases the queued `current`, so the context track is what plays.
- **UI.** Track rows have a right-click menu with Play Next / Add to Queue (both
  visibly disabled on unstreamable rows). Album and playlist rows have
  Add to Queue. A non-empty queue shows `Up Next (n)` ABOVE the context's own
  header and tracks: ordered rows with title and `artist · album`, a Clear
  button, double-click to play a row immediately (dropping it and everything
  ahead of it), and right-click → Remove from queue. The menu is a separate
  overlay from the gear/Sort menu; Esc closes only the menu.
- **Height (v3.2 model).** The Up Next section (header/Clear control row,
  2 px gap, visible queue rows) counts as detail content. Up to six rows are
  visible at the same 30 px unit as the six-row floor; longer queues scroll.
  The existing floor (6 × 30 px) and 396 px cap still apply, and both panes
  keep the one shared height with coincident bottom edges.
- **MPRIS.** `canNext` / `canPrevious` now also consider the pending user queue.
  The published key whitelist is unchanged.

### Tests (raw counts)

- Unit: `Ran 97 tests ... OK (skipped=5)` (88 existing + 9 new
  `UserQueue` model cases). The model tests run the exact source under Node.
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK` (unchanged).
- QML (`tests/qml/run.sh`): **426** checks = phase 1 395 + relaunch 8 +
  real-data 17 + 6 script-side. All `FAILS=0`. Baseline 388 -> +38 checks
  (37 phase 1, 1 relaunch).
- `omarchy plugin validate .`: exit 0.
- `/usr/lib/qt6/bin/qmllint Service.qml Panel.qml BcButton.qml`: exit 0, no
  errors; only the pre-existing import/unqualified-access warnings and the
  existing `Service.qml` `QVariantMap`/`QVariantHash` warning.
- Credential files were not opened (paths/modes only). No stream URL, cover-art
  URL or credential value was printed or committed. `--load-scripts=no` is
  untouched and the MPRIS whitelist is untouched.

### Harness checks updated (and why)

No existing check was changed, loosened or removed. Every v3/v3.1/v3.2/v3.3
check still runs with its old assertion.

The new v3.4 steps start by calling `svc.loadLibrary()` and by clearing the
selected album before `pickAlbum()`. That is test setup, not a product
assertion: the preceding v3.2/v3.3 blocks deliberately replace
`svc.collection` with two synthetic albums and leave the fixture album
selected, so v3.4 has to put the fixture library and selection back to exercise
real album and track rows.

The Up Next height check measures its no-queue baseline in its own step, one
tick after selecting the album, and asserts that baseline is itself a normal
content-driven height (floor..cap) before comparing. The first draft measured
in the selection tick and could read 0 while the detail pane was still being
built, which would make the growth comparison meaningless; this is a new check
added to keep the height assertion honest, not a weakened existing one.

### New harness coverage

- Right-clicking an album row opens exactly `Add to Queue` (enabled); adding a
  four-track album queues its tracks in album order and reports
  `Added 4 tracks to queue`.
- Up Next becomes visible with `Up Next (4)`, four ordered rows carrying
  title + `artist · album`, sits entirely above the context header, and has a
  Clear button.
- Clear empties the queue, hides Up Next and leaves playback untouched.
- A streamable track row offers `Play Next | Add to Queue`; Add to Queue appends
  it; Play Next on another row inserts at the front with a duplicate allowed;
  Up Next follows the new order.
- An unstreamable track row still opens its menu with both actions disabled,
  and Esc closes it without queueing anything.
- Adding an album with one streamable and two unreleased tracks queues only
  `Released Single` and reports
  `Added 1 track to queue · 2 skipped (not streamable)`.
- From a context track, Next plays the queue head while the context
  queue/index stay underneath; with context shuffle On, queued tracks still
  play in added order; when the queue drains, the context resumes at the track
  AFTER the interrupted one and does not replay it.
- With two queued tracks played, Previous returns to the previous queued track,
  then to the interrupted context track, with both queued tracks pending again.
- Double-clicking a queue row plays it immediately and drops it and everything
  ahead; right-click → Remove from queue drops only that row and keeps playback.
- Up Next rows count in the content-driven height (baseline inside the normal
  floor..cap, growth > 50 px, result under the cap), both panes stay equal, and
  the detail content still fits.
- Playing another track in the SAME context keeps the queue; playing a track in
  a NEW context clears it.
- Relaunch phase: the queue is empty again after a shell restart (session-only,
  nothing persisted).

### Deviations / owner-visible decisions

- **Up Next shows six rows at once**, the same six-row unit as the height
  floor, then scrolls. This keeps the context's own list visible below it.
- **Clear drops pending rows only.** A queued track that is already playing
  keeps playing; Clear never stops audio.
- **Playing a queue row is a takeover**, so that row and every row ahead of it
  are discarded permanently, matching the spec's "play immediately" wording.
- **End of context stops.** If the interrupted context track was the last one,
  draining the queue leaves the last queued track in the footer but stops
  playback rather than replaying anything.
- **History is scoped to the takeover.** As soon as the context resumes,
  Previous is the old context Previous again; the queued items are gone.
- **Single-track playback is a new context**, so it clears the queue even
  though the track may come from the album that is on screen.
- **Notice wording** is `Added N track(s) to queue`, with
  `· M skipped (not streamable)` appended only when something was skipped.
- **MPRIS** treats a pending queue as "can go next/previous"; the whitelisted
  key set and status values are unchanged.

### Owner live check

1. `omarchy restart shell`, open the panel and start an album. Right-click a
   track row → Play Next: it becomes the first `Up Next (1)` row above the
   album's tracks. Right-click another → Add to Queue: it lands at the end.
2. Add the same track twice: both rows stay (duplicates are allowed).
3. Right-click an unreleased/greyed track: the menu still opens but both
   Play Next and Add to Queue are disabled.
4. Right-click an album in the left list → Add to Queue: its streamable tracks
   are appended in order; a partially released album reports both the added
   and skipped counts in the notice.
5. Press Next from a normal context track: the queue head plays, the context
   list underneath does not change, and when the queue runs out the album
   continues with the track AFTER the one that was playing (not a replay).
6. With Shuffle On for the album, queue two tracks: they still play in the
   order you added them.
7. Play two queued tracks, then press Previous twice: you should step back to
   the first queued track, then to the album track that was interrupted, with
   the queued tracks shown again in Up Next.
8. Double-click the second queued row: it plays at once and the rows above it
   disappear. Right-click a remaining queue row → Remove from queue: only that
   row goes; playback continues.
9. Start another album (or a single track from elsewhere): the queue empties.
   `omarchy restart shell` also starts you with no queue (session-only).
10. Check the popup height with Up Next full: it grows by the queue rows, stops
    at the cap and scrolls, and both panes still end on the same line.

## v3.3.1 Tab fix + search clear / focus chain / gear icon (owner-reported, 2026-10-26)

Scope: fix the owner-reported invisible-character bug (open the panel, press
Tab, Down, Tab: both panes blank to "No results" until Backspace), then three
polish items — a click-to-clear × in the search field, the header Tab order,
and the gear menu's Refresh glyph. Search matching, grouped results, playback,
queue, height model, MPRIS whitelist and every other view are unchanged.

### Baseline (fresh session, before editing)

- Unit: `Ran 97 tests ... OK (skipped=5)`
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK`
- QML (`tests/qml/run.sh`): **426** checks = phase 1 395 + relaunch 8 +
  real-data 17 + 6 script-side. All `FAILS=0`.

The baseline matched the expected 97/5 unit, 5 live and 426 QML figures, so
editing proceeded.

### Part A root cause (confirmed by probe, not inferred)

The Phase 8 type-to-search branch in `listKeyCatcher` accepted any `event.text`
of length 1. Qt reports Tab as a single-character `event.text` of `"\t"`
(U+0009), and the search field's own Tab was not consumed as a focus move, so
the sequence was:

1. Tab with search focused: no explicit traversal ran; the field kept focus.
2. Down: Phase 8 moved focus to the left list (`listKeyCatcher`).
3. Tab with the list focused: no Tab branch existed, so the type-to-search
   branch appended `event.text` (`"\t"`), then returned focus to the field.

Raw harness dump **before** the fix (temporary probe, removed afterwards):

```
after Tab1: field=true  catcher=false pane=""
after Down: field=false catcher=true  pane=list
after Tab2: field=true  catcher=false pane=""
repro text len=1 cps=[U+9] queryLen=1 rows=0
```

The query therefore contained exactly one U+0009 code point, which matched
nothing — the owner's "No results / 0 tracks" state. Backspace removed it and
restored the lists. Switching Albums/Playlists could not cure it because the
query was still non-empty.

Fix at two layers:

- `Panel.handleTabKey(event)` now runs first on the search field, the clear
  control, every header button and `listKeyCatcher`: `Tab`, `Shift+Tab` and
  `Key_Backtab` always move focus through the chain and are accepted, so the
  key can never reach text entry or type-to-search.
- `Panel.isPrintableText(text)` gates type-to-search (and the Slash shortcut is
  unchanged): exactly one code point, `>= 0x20`, excluding DEL and the C1 range,
  with Ctrl/Alt/Meta excluded. Navigation/control keys carry empty or control
  `event.text` and are never appended.

Phase 8 behaviour is preserved: a genuine printable character typed while a
list is focused still returns to search with the character, `/` still jumps to
search, and Space with a list focused still toggles play/pause without entering
the query. Both were re-asserted (see below).

### What changed

- **Part A** — `Panel.qml`: `handleTabKey`, `moveFocus`, `focusChainItems`,
  `focusControlName`, `isPrintableText`; Tab handling at the top of
  `searchField`'s and `listKeyCatcher`'s `Keys.onPressed`; printable-only
  type-to-search.
- **Part B1 click-to-clear** — the right-end glyph is now a borderless
  `BcButton` (`searchAction`) inside the field: magnifier (`\uf002`) when empty,
  × (`\uf00d`) with tooltip `Clear search` when text is present. Clicking with
  text clears the query and returns focus to the field; clicking when empty
  focuses the field. `rightPadding` reserves the control's box.
- **Part B2 Tab order** — `focusChain` is search field → clear/magnifier →
  Collection → gear → Albums → Playlists → Sort, wrapping both ways. Hidden
  controls (Sort on Playlists) are skipped. Every member is a real focus target
  (`focusable: true` on the `BcButton`s), so it paints the shell's existing
  focus fill/border; no new visual language. Enter/Space on the focused clear
  button clears and refocuses the field (normal `Button` activation).
  `focusSearch()` is called when a gear/sort menu opens so the menu's existing
  Up/Down/Enter handling on the field keeps working even though the gear is now
  a Tab stop.
- **Part B3 gear icon** — Refresh changes from the thin text arrow `\u21BB` to
  the icon font's sync glyph `\uf021`, matching the Log out glyph's family,
  pixel size, weight, button height and glyph box/baseline. Hide pre-orders is
  still a plain checkable item (`\uf00c` on, em-space off).

### Tests (raw counts)

- Unit: `Ran 97 tests ... OK (skipped=5)` (unchanged).
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK` (unchanged).
- QML (`tests/qml/run.sh`): **446** checks = phase 1 415 + relaunch 8 +
  real-data 17 + 6 script-side. All `FAILS=0`. Baseline 426 -> +20 checks
  (21 new, one existing magnifier check replaced; three existing check
  descriptions/assertions adjusted as listed below).
- `/usr/lib/qt6/bin/qmllint Panel.qml BcButton.qml tests/qml/shell.qml`: exit 0,
  no errors.
- Credential files were not opened (paths/modes only). No stream URL, cover-art
  URL or credential value was printed or committed. `--load-scripts=no` is
  untouched.
- Acceptance screenshot: `/tmp/omatime-v331-gear-menu.png` (300×106, saved and
  reloaded by the harness; Refresh sync glyph aligned with the Log out icon,
  Hide pre-orders plain).

### Harness checks updated (and why)

- `v3.1: magnifier is dimmed and non-interactive (plain disabled Text, no input
  handlers)` -> `v3.3.1: an empty field shows a focusable magnifier control (not
  a disabled glyph)`: the old check asserted the design Part B1 deliberately
  replaces. The new check asserts the same geometry/glyph/size and the new
  contract (magnifier icon, no tooltip when empty, focusable, inside the field).
- `9 buttons in the open window ...` -> `10 buttons ...`: the in-field
  clear/magnifier is a real button now; it is the tenth.
- `all buttons bordered (one border style)` -> `toolbar/footer/header buttons
  share one bordered style; the in-field clear action stays borderless by
  design`: the new control is intentionally borderless inside the text field;
  every other button must still be bordered. This is stricter than the old
  blanket check, not looser.
- `searchMagnifier()` now resolves the shell `Button`'s internal glyph `Text`
  through the new `iconGlyphOf()` helper (BcButton does not name it). The
  existing magnifier geometry/font-size checks are unchanged and still pass.
- No other existing check was loosened or removed.

### New harness coverage (21 checks)

- Part A: owner's exact Tab/Down/Tab leaves text `len=0 cps=[]`, query empty,
  both lists populated, no empty-state overlays. Raw values are logged
  (`v3.3.1 owner Tab/Down/Tab: len=0 cps=[] query=0 left=13 tracks=2`).
- Part A: Tab from a focused list moves to search without typing U+0009;
  Shift+Tab from a list goes back to Sort without typing.
- Part A: Delete/Home/End/PageUp/PageDown/arrows with a list focused never enter
  the query.
- Part A: a printable `q` with a list focused still jumps to search and is kept;
  Space with a list focused toggles playback and never enters the query.
- Part B2: Tab walks the exact chain
  `searchAction|link-collection|settingsButton|albumsButton|playlistsButton|sortButton|searchField`
  and every stop reports the shared focus ring; Shift+Tab walks it in reverse
  and wraps.
- Part B1/B2: with text the field shows ×, tooltip `Clear search`, same icon
  family/pixel size as the gear; clicking × clears, restores both lists and
  returns focus; Tab from search lands on the focused clear button; Enter and
  Space on it clear and refocus.
- Part B3: Refresh uses `\uf021`, same font family, pixel size, weight, button
  height and glyph box/baseline offset as Log out; Hide pre-orders remains a
  plain checkable item.
- Part B3 acceptance: the open gear menu is grabbed to
  `/tmp/omatime-v331-gear-menu.png`, saved successfully and reloaded as a real
  image before the check passes.
- Esc with the gear menu open still closes only the menu, not the window.

### Deviations / owner-visible decisions

- **The clear/magnifier is a borderless button inside the field.** It uses the
  shared `BcButton` focus fill/border and icon size, but intentionally keeps no
  resting border so it reads as part of the text field. It is the one
  exception to "every button is bordered".
- **Tab needs an explicit chain.** Qt's automatic traversal did not move focus
  out of the in-field composite in the offscreen harness (and the owner saw the
  same), so the chain is explicit; this also guarantees Tab can never become
  text. Tab now wraps from Sort back to search instead of leaving the panel.
- **Opening the gear/sort menu returns focus to the search field.** This keeps
  the existing menu keys (Up/Down/Enter, Esc) working exactly as in v3.4. The
  gear still shows its `active` fill while its menu is open and regains its
  focus ring on the next Tab.
- **Sort is skipped in the chain on the Playlists tab** because it is hidden
  there; Tab then goes Playlists -> search, Shift+Tab search -> Playlists.
- **No Phase 8 key conflicts.** `/`, arrows, Enter and the Esc layering behave
  as before; only Tab/Shift+Tab were previously unhandled and are now focus
  movement.

### Owner live check

1. **Re-try the original repro:** open the panel, press Tab, Down, Tab. The
   query must stay empty, both panes populated, and no Backspace should be
   needed.
2. Repeat with Shift+Tab variants (Shift+Tab from the list and from search):
   focus moves, nothing is typed, lists stay.
3. Type an album/track name into search: results appear; the right-end icon is
   ×. Click ×: query empties, focus returns to the field, both lists return.
4. Tab through the header: search field → ×/magnifier → Collection → gear →
   Albums → Playlists → Sort → back to search. Shift+Tab reverses. Every stop
   shows a visible focus highlight.
5. With text in the field, Tab to the × and press Enter, then Space: both clear
   and put the caret back in the field.
6. Open the gear menu (icon and with the mouse): Refresh shows the circular
   sync glyph, matching the Log out icon's weight/alignment; Hide pre-orders is
   a plain checkable row; Up/Down/Enter still operate the menu; Esc closes only
   the menu.
7. Type a letter with the left list focused: search opens with that letter;
   press Space with a list focused: playback toggles and no space is typed.

## Pre-release fixes (owner-requested, 2026-10-27): Sort on Playlists + Up Next frame

Scope: two owner requests before release. Sort must stay on the Playlists tab
with a reduced option set, remembered per tab; and Up Next needs its own
bordered sub-frame so it no longer runs into the selected album's header and
tracks. Search matching, playback, the queue's semantics, the v3.2 height
floor/cap, the MPRIS whitelist and every other view are unchanged.

### Baseline (fresh session, before editing)

- Unit: `Ran 97 tests ... OK (skipped=5)`
- Live fixtures (`OMATIME_LIVE=1`): `Ran 5 tests ... OK`
- QML (`tests/qml/run.sh`): **446** checks = phase 1 415 + relaunch 8 +
  real-data 17 + 6 script-side. All `FAILS=0`.

The baseline matched the expected 97/5 unit, 5 live and 446 QML figures, so
editing proceeded.

### Playlist source-order check (done before writing the sort)

The spec defines Recently Added as the library's existing source order, so the
order had to be verified first. `backend/library.py::_pull_playlists` preserves
the order Subsonic returns, and the cache keeps that list verbatim. The real
cache (`~/.cache/omatimeatbandcamp/library/library.json`, 33 playlists) starts:

```
Postpunky?, aaaaaaa, Zaké, dave’s faves., jim o, Instru, Glass Beams!,
Peppery Art, geotic!, jim & yola, ...
```

That is not alphabetical, so labelling it "Recently added" is honest: playlists
carry no purchased/release timestamp in the model or the cache, so the source
order is the only "added" ordering that exists — the same definition Albums
uses when it has no date. No relabelling or invented timestamp was needed.

The QML fixture order was swapped (`Rock & Roll Faves`, then `Postpunky?`) so
source order and Title A–Z differ and both can be asserted.

### What changed — Item 1 (Sort on Playlists)

- **`LibraryModel.js`**: new `PLAYLIST_SORT_MODES` (exactly
  `Recently added`, `Title A–Z`), `validPlaylistSort(mode)` and
  `sortPlaylists(playlists, mode)`. `added` returns a copy in source order;
  `title` sorts by name with the existing accent/case-insensitive `cmpStr`
  and the id as a stable tie-break.
- **`Service.qml`**: `playlistSortMode` (default `"added"`),
  `playlistsView` (the sorted list the UI binds to), `setPlaylistSortMode()`,
  and persistence in the existing `stateDir/ui.json` file next to `sortMode`
  and `hidePreorders`. `sortMode` remains the Albums choice; the two are
  independent. Search now reorders its Playlists group with
  `sortPlaylists(playlists, playlistSortMode)` and keeps only the matching
  rows, mirroring how Albums already follow the Albums sort.
- **`Panel.qml`**: the Sort button is always visible again and its label
  follows the active tab (`activeSortMode` / `activeSortLabel`); the sort menu
  lists `PLAYLIST_SORT_MODES` on the Playlists tab and the full
  `SORT_MODES` on Albums; the menu action dispatches to
  `setPlaylistSortMode()` or `setSortMode()` by tab. The list binds to
  `playlistRows` (the sorted view) instead of the raw `playlists`.

Albums sort options, before and after (unchanged):

| Before | After |
|---|---|
| Recently added, Artist A–Z, Title A–Z, Release date | Recently added, Artist A–Z, Title A–Z, Release date |

Playlists sort options, before and after:

| Before | After |
|---|---|
| (none — button hidden) | Recently added, Title A–Z |

### What changed — Item 2 (Up Next frame)

- Up Next is now a `BorderSurface` inside the detail pane, with the **same
  `root.paneBorderSpec`** the panes and controls use. No new colours, no new
  style tokens.
- Frame chrome is `2 * (Style.normalBorderWidth + Style.spacing.sm)`, i.e.
  10 px at the current theme (1 px border + 4 px padding per side). The
  "Up Next (n)" header and Clear stay in the frame's top row, with the queue
  list below them inside the frame's content insets.
- `upNextSectionHeight` includes that chrome, so the v3.2 content-driven
  height counts the border and padding honestly. The floor (6 × 30 px) and
  cap (396 px) are untouched; the queue list keeps its 6-row cap and scrolls
  internally, and the album/playlist track list keeps its own independent
  scroll. `objectName: "upNext"` is unchanged, so all v3.4 queue checks and
  their probes still address the same item.
- Empty queue: the section is `visible: false` with height 0, so there is no
  frame and no residual gap; the album header keeps its usual 4 px offset.

Measured frame heights: 1 queue row → **70 px** (28 header + 2 gap + 30 row +
10 chrome); 6 visible rows → **220 px** (28 + 2 + 180 + 10). The detail row's
floor/cap still governs the pane height, and both panes end on the same line
at both queue sizes.

### Tests (raw counts)

| Run | Baseline | Final |
|---|---|---|
| Unit (`python3 -m unittest discover -s tests -t .`) | `Ran 97 ... OK (skipped=5)` | `Ran 97 ... OK (skipped=5)` |
| Live (`OMATIME_LIVE=1`) | `Ran 5 ... OK` | `Ran 5 ... OK` |
| QML total | **446** | **472** |
| — phase 1 (fixture library) | 415 | 437 |
| — phase 2 (relaunch, same HOME) | 8 | 12 |
| — real-data smoke | 17 | 17 |
| — script-side (`run.sh`) | 6 | 6 |

All phases report `FAILS=0`; `tests/qml/run.sh` exits 0 and prints
`QML tests: OK`. `omarchy plugin validate .` exits 0; `qmllint` over
`Panel.qml`, `Service.qml`, `BcButton.qml`, `LibraryModel.js` and
`tests/qml/shell.qml` exits 0 with no errors.

Final − baseline = +26 = 27 new checks − 1 removed check.

### Harness checks updated (and why)

- **Removed** `Sort is only offered on the Albums list`. The requirement
  changed: Sort must be on Playlists too. Its replacement is the new
  presence + exact-two-option coverage below, so no coverage was dropped.
- **Test helper `sortButton()`** now resolves the label from the active tab's
  mode (`svc.playlistSortMode` on Playlists, `svc.sortMode` on Albums)
  instead of always `svc.sortMode`. Helper only; no check changed.
- **Fixture `tests/qml/fixtures/library.json`**: the two playlists were
  reordered to `Rock & Roll Faves`, `Postpunky?`. Data-only change needed to
  make source order differ from Title A–Z; album fixtures are untouched.
- **New frame check tolerance**: the top-row alignment check allows 1 px
  between the header text's centre and the 28 px Clear button's centre
  (glyph box is 15 px vs the button's 28 px). This is a new check authored
  with that tolerance; no existing check was loosened.
- Every existing Albums sort check is unchanged and still passes: the four
  options in order (`Recently added|Artist A–Z|Title A–Z|Release date`),
  the check mark, the order assertions, the filter combination, and the
  relaunch-restored Album choice.
- Every existing v3.4 Up Next check is unchanged and still passes (count,
  row order and labels, above-context placement, Clear, empty-state removal,
  reorder, height contribution, fits-in-pane).

New Item 1 checks (10 + 4 relaunch):

1. Sort is present on the Playlists tab with its reduced label.
2. Playlists start in the library's source order (Recently added).
3. The Playlists sort menu offers EXACTLY Recently added and Title A–Z.
4. Recently added is checked on the default Playlists sort.
5. Title A–Z reorders the playlists case-insensitively.
6. The playlist sort does not change the Albums sort.
7. Recently added restores the library source order.
8. Playlist Title A–Z is the persisted choice for relaunch.
9. The search Playlists group follows the playlist sort.
10. The Albums sort is still its own choice after changing Playlists.
11. `[relaunch]` playlist sort restored from disk (Title A–Z).
12. `[relaunch]` playlists are Title A–Z in the relaunched process.
13. `[relaunch]` playlist sort menu still has exactly two options.
14. `[relaunch]` the restored playlist choice is the checked item.

New Item 2 checks (13):

1. An empty queue shows NO Up Next frame and leaves no gap.
2. A non-empty queue shows the bordered Up Next frame.
3. The frame border is the shared pane/control border colour (equals the
   detail pane, left pane and footer borders).
4. The frame height includes its own border and padding.
5. Header and Clear sit inside the frame's top row.
6. Queued rows start below the header/Clear top row.
7. The frame adds its real height + gap above the album header.
8. A small queue keeps both panes exactly equal.
9. The queue list caps at six visible rows and scrolls internally.
10. Scrolling the queue never scrolls the album track list.
11. A large queue keeps both panes exactly equal with the frame present.
12. The frame stays inside the detail pane.
13. Clearing the queue removes the frame (no frame, no leftover gap).

### Deviations / owner-visible decisions

- **"Recently added" on Playlists is source order**, because playlists have no
  timestamp anywhere in the model or cache. Verified non-alphabetical against
  the real library before using the label, as required.
- **The two tabs persist independently**: `ui.json` now holds
  `{ sortMode, playlistSortMode, hidePreorders }` in the same file as before.
  Older files without `playlistSortMode` load as Recently added.
- **The search Playlists group is only reordered when it has more than one
  result** (with one result the order cannot be observed). Albums follow the
  same pattern.
- **Frame chrome is 10 px at the current theme** and scales with the theme's
  border width and `spacing.sm`; it is part of the measured section height,
  not an overlay, so the floor/cap and equal pane bottoms stay exact.
- **`--load-scripts=no` unchanged**; no credential or stream URL is read,
  printed or stored by this work.

### Owner live check

Item 1:

1. Open the panel, click Playlists: the Sort button is there and reads
   `Sort: Recently added` (or your last playlist choice).
2. Open Sort on Playlists: exactly two rows, Recently added and Title A–Z.
   Choose Title A–Z: the playlists reorder by name; clear the choice back to
   Recently added: they return to the library's order.
3. Switch to Albums: its Sort still offers all four options and keeps its own
   choice. Switch back to Playlists: your playlist choice is still selected.
4. Search for a letter matching more than one playlist (e.g. `o`): the
   Playlists group in the results follows the playlist sort.
5. Restart the shell: the playlist sort is still what you last chose (and
   `~/.local/state/omatimeatbandcamp/ui.json` shows `playlistSortMode`).

Item 2:

1. Start an album, right-click a track → Play Next: Up Next appears in its own
   rounded frame above the album title, same border as the panes and footer.
2. Check the header row: "Up Next (1)" and Clear sit inside the frame's top
   edge, with the queued row under them.
3. Add seven more tracks: the frame stops at six visible rows and scrolls on
   its own; scrolling it must not move the album track list.
4. Look at the bottom edges: both panes still end on exactly the same line.
5. Clear the queue: the frame disappears completely, with no leftover gap
   above the album header.

## v3.5 interaction pass (owner-decided, 2026-10-28)

Branch `v2`. Implements the complete keyboard/interaction pass: sort direction,
full Tab traversal, queue keyboard control, keyboard-accessible row menus, and
an in-body keyboard-shortcuts view.

### Baseline (fresh session, before editing)

- `python3 -m unittest discover -s tests -t .`: 97 tests OK, 5 skipped.
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: 5 tests OK.
- `tests/qml/run.sh`: 472 checks passed, `FAILS=0` in every phase.
- Values matched the expected baseline exactly, so editing proceeded.

### Part A — sort direction

- `LibraryModel` gains `validSortDirection`, `defaultSortDirection(scope, mode)`
  and `sortDirectionArrow(dir)`. Defaults are exactly the pre-v3.5 comparator
  results: Albums `added`/`release` descending, `artist`/`title` ascending;
  Playlists `added`/`title` ascending.
- Flipping is implemented by **reversing the completed default ordering**, not
  by re-sorting with an inverted comparator. A flip is therefore an exact
  reverse, ties included, and the default path is byte-for-byte the old order.
- `Service` holds `sortDirection` and `playlistSortDirection`, persists both in
  `ui.json`, and validates them on load. Choosing a new criterion resets that
  tab to the criterion's default; flipping alone keeps the criterion. Search
  re-runs through the same direction, so the Albums/Playlists result groups
  follow it.
- `Panel` adds a 28 px icon-only button immediately right of Sort, tooltip
  "Reverse sort direction", showing the current direction (`\uf062` up /
  `\uf063` down). One click flips and re-sorts. The selected Sort menu row
  carries the same arrow through `BcButton.trailingText`, which leaves every
  existing `text`/label lookup unchanged. Option sets are untouched: four
  Albums criteria, two Playlists criteria.

### Part B — complete Tab traversal

- One ordered token list drives focus:
  `searchField, searchAction, link-collection, settingsButton, albumsButton,
  playlistsButton, sortButton, sortDirectionButton, leftList, upNextList,
  upNextClear, trackList, footerShuffle, footerPrev, footerPlay, footerNext`.
- `upNextList`/`upNextClear` are skipped entirely when the queue is empty, so
  Tab goes straight from the left list to the track list. The help view removes
  the four body regions from the chain while it is open.
- Entering the left list focuses the selected/current row; entering Up Next
  focuses its current cursor; entering the track list focuses the playing row
  or row 0. Each region shows a cursor tint or focus ring. Buttons activate on
  Enter and Space. Tab/Shift+Tab never become text.
- If the queue vanishes while it owns focus (Clear, removal, or service state),
  `afterQueueCleared()` moves focus to the track list.

### Part C — queue keys and keyboard menus

- Only with a named list focused: track list `Ctrl+Enter` = Add to Queue,
  `Alt+Enter` = Play Next; left list `Ctrl+Enter` = add the whole item
  (streamable tracks only, with added/skipped counts), `Alt+Enter` = nothing;
  queue list `Delete` removes the focused row (next row, previous if last,
  track list when it empties) and `Enter` plays it now with double-click
  semantics. Adding/removing never starts or changes the playback context.
- Unstreamable rows are no-ops with the same notice as the pointer menu.
- The search field remains a normal editor: `Delete` deletes text;
  `Ctrl+Enter`/`Alt+Enter` do nothing.
- Context-menu rows carry dimmed hints via `BcButton.trailingText`
  (`Add to Queue · Ctrl+Enter`, `Play Next · Alt+Enter`, `Remove ·
  Del`). `Menu` or `Shift+F10` on a focused list row opens the identical menu;
  `↑`/`↓` navigate, `Enter` activates and closes, `Esc` closes without acting,
  and focus returns to the opening row.

### Part D — keyboard shortcuts view

- Gear order is now Refresh library / Hide pre-orders / Keyboard shortcuts /
  Log out. Selecting the new item replaces only the two-pane body slot with a
  shortcuts view; header, search, gear, toolbar and footer remain.
- Groups are Navigation, Playback, Queue, Search & menus. Rows are two-column
  (`shortcutsKey` 170 px, `shortcutsDesc` at 182 px) using the existing
  `bodySmall`/`caption` sizes and body/dimmed colours. The view respects the
  same floor/cap as the panes and scrolls internally.
- The two panes and the queue stay alive underneath, so selection, both scroll
  positions and queue contents are restored exactly on close. Opening moves
  focus into the view; `Esc` closes and returns focus to the gear; selecting
  Keyboard shortcuts again toggles it closed. The item is reachable by the
  keyboard (Tab to gear, Enter, Down ×2, Enter).

### Tests (raw counts)

After the pass:

- `python3 -m unittest discover -s tests -t .`: **97 tests OK, 5 skipped**
  (unchanged).
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: **5 tests OK**
  (unchanged).
- `tests/qml/run.sh`: **558 checks passed**. Phase 1 520, relaunch 15,
  real-data 17, shell-script 6; `FAILS=0` in every phase.
- `node --test tests/user_queue.test.js`: pass (unchanged model behaviour).
- `/usr/lib/qt6/bin/qmllint Panel.qml Service.qml BcButton.qml`: exit 0, only
  the pre-existing import/unqualified-access warnings.
- `/usr/lib/qt6/bin/qmllint tests/qml/shell.qml`: exit 0.
- `omarchy plugin validate .`: exit 0.

Baseline 472 → final 558 QML checks (+86). All Phase 8, v3.3.1, v3.4 queue
and sort assertions still run; the intentionally superseded checks are listed
below, none weakened.

### Harness checks updated (and why)

1. Window button count 10 → 11: the new direction button is a real control.
2. Gear menu exact order gains `Keyboard shortcuts`.
3. The keyboard logout test presses Down three times instead of two, because
   the help item now sits before Log out.
4. Two v3.3.1 header-chain checks now include the direction button; the header
   walk is seven stops from search to direction (and reversed from direction to
   search).
5. The v3.3.1 "Tab from a focused list returns to search" check now asserts
   the v3.5 order: the next region (track list when no queue; Up Next when a
   queue exists), still proving Tab never types U+0009.
6. The v3.3.1 "Shift+Tab from a list goes to Sort" check now targets the sort
   direction button, the actual previous stop.

No other assertion was relaxed or removed.

### New harness coverage

Part A (phase 1):

1. Direction button exists beside Sort, 28 px, button style, correct tooltip.
2. Placement and glyph show the current direction.
3. Every Albums criterion's default exactly reproduces the old comparator.
4. The Playlists default reproduces the old comparator.
5. Documented per-criterion defaults.
6. Untouched Title A–Z still ascending.
7. One click flips Title A–Z to the exact reverse (ties included).
8. Arrow updates and focus returns to search.
9. Second click restores the default.
10. Release date defaults descending.
11. Release date flip is the exact reverse.
12. Recently added defaults descending.
13. Recently added flip is the exact reverse.
14. Descending survives while the criterion is unchanged.
15. A new criterion resets to its default.
16. The Albums menu still has exactly four rows.
17. The selected row carries the same direction arrow.
18. Re-choosing the selected criterion restores its default.
19. Playlists has its own direction, up by default.
20. The Playlists menu still has exactly two rows.
21. Playlists Title flips to the exact reverse.
22. Flipping Playlists does not touch Albums.
23. Search Albums group follows direction.
24. Search Playlists group follows its tab's direction.
25–27. Relaunch: both directions restored independently and the relaunched
   Albums list is ordered by the restored direction.

Part B:

28. Full Tab chain with no queue skips the queue frame and wraps.
29. Full Tab chain with a queue includes Up Next then Clear.
30. Entering the left list focuses the selected row with a visible cursor.
31. Tab from the left list enters Up Next row 0 with a visible cursor.
32. Arrows move inside Up Next and move the visible cursor.
33. Tab leaves Up Next for Clear, with its focus ring.
34. Tab from Clear enters the track list at the current row.
35. Tab from the track list reaches the footer.
36. The chain reaches Next.
37. Enter activates a focused footer button.
38. Space activates it too.
39. Shift+Tab reverses the full chain across every boundary, queue included.
40. Queue focus is established before it vanishes.
41. A vanished queue lands focus on the track list.

Part C:

42. Track-list focus starts at row 0.
43. Ctrl+Enter adds the focused track.
44. Adding never starts/changes playback.
45. Alt+Enter inserts the focused track next.
46. Further Ctrl+Enter appends in order.
47. Ctrl+Enter on an unstreamable track is a no-op with notice.
48. Alt+Enter on it is the same no-op.
49. The whole-item row is focused in the left list.
50. Ctrl+Enter adds the whole album, streamable only, with counts.
51. Alt+Enter on an album row does nothing.
52. Queue cursor reaches the second row.
53. Delete removes that row and stays on the next.
54. Removing never changes the playback context.
55. Deleting the last row selects the previous.
56. Deleting the only row lands on the track list.
57. Enter on a queue row plays it now.
58. The underlying context/index stay untouched.
59. Ctrl/Alt+Enter in search do nothing.
60. Delete in search edits text.
61. Menu on a track row opens the same menu.
62. Menu rows carry the dimmed hints.
63. Down navigates the context menu.
64. Enter activates the highlighted item and closes.
65. Focus returns to the opening row.
66. The menu reopens on the same row.
67. Esc closes without acting and restores row focus.
68. Shift+F10 opens the queue row's menu with its Delete hint.
69. Enter removes the row and returns focus.

Part D:

70. The shortcuts view opens in the body slot.
71. Opening moves focus into the view.
72. The four groups appear in order.
73. Rows use the existing two-column sizes and colours.
74. The view stays inside the floor/cap and scrolls internally.
75. Every Part A–C/addendum shortcut is listed.
76. Esc closes, keeps the window and returns focus to the gear.
77. Selection, both scroll positions and the queue are restored exactly.
78. The item opens the view again.
79. Selecting it again closes (toggle).
80. The keyboard path reaches the gear.
81. Enter opens the gear menu from the keyboard.
82. Down ×2 + Enter opens the view from the keyboard.
83. Esc from that path returns focus to the gear.
84. The final phase-1 directions are persisted for relaunch.

### Deviations / owner-visible decisions

- **Criterion change resets direction**, flip keeps it. This makes each
  criterion's documented default observable and avoids surprising reversals
  when switching criteria. Persisted direction is per tab.
- **The direction glyph is the state, not a second menu**: Sort still owns the
  criterion. The selected Sort row repeats the arrow so the state is visible
  inside the menu.
- **`BcButton.trailingText`** was added instead of appending the hint/arrow to
  `text`, so all existing exact-label checks and lookups keep working.
- **The shortcuts view overlays only the pane body**. The panes and queue are
  not destroyed, which is what makes exact restoration of selection, scroll and
  queue possible without extra state.
- **Addendum keys use the same context menu**: no second menu implementation,
  and the pointer hints are the keyboard hints.
- **`--load-scripts=no` unchanged**. No credential or stream URL was opened,
  read, printed or stored by this work.

### Owner live check

1. Open the panel on Albums. The arrow beside Sort points up for Title A–Z.
   Click it: the list reverses exactly and the arrow points down; the arrow is
   also shown on the selected Title A–Z row in the Sort menu.
2. Switch to Playlists, change direction, switch back: each tab keeps its own
   direction. Restart the shell: both directions come back.
3. Press Tab repeatedly from search: the focus walks search → clear →
   Collection → gear → Albums → Playlists → Sort → direction → album list →
   Up Next + Clear (if queued) → track list → Shuffle → Prev → Play/Pause →
   Next → search. Shift+Tab walks it backwards. Every stop is visibly focused.
4. Add two tracks to Up Next. Tab into the queue, press `Enter` on one (it plays
   now), `Delete` on another (it disappears and focus moves to the next row).
   Delete the last row: focus lands in the track list.
5. Focus an album track, press `Ctrl+Enter` and `Alt+Enter`; focus an album row
   and press `Ctrl+Enter` (whole album, streamable only); press `Alt+Enter` on
   the row (nothing). The search field still edits normally, including Delete.
6. Focus a track or queue row and press `Menu` (or `Shift+F10`): the context
   menu opens on that row with its dimmed key hints. `↑`/`↓`, `Enter`, `Esc`
   behave as listed, and focus returns to the row.
7. Gear → Keyboard shortcuts: the two panes are replaced by the grouped list.
   Scroll it, press `Esc`: the exact panes, selection, scroll and queue return,
   with focus back on the gear. Open it again and select the item again: it
   closes.


## v3.5.1 live-look fixes (owner-requested, 2026-10-28)

Branch `v2`. A live-look pass after v3.5: Collection moves into the settings menu,
the product name is spelled `Bandcamp`, keyboard focus uses the theme accent, the
shortcuts reference fits without scrolling, and the header becomes a title band,
a field and the cat-and-flute settings mark.

### Baseline (fresh session, before editing)

- `python3 -m unittest discover -s tests -t .`: **97 tests OK, 5 skipped**.
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: **5 tests OK**.
- `tests/qml/run.sh`: **560 checks passed** (phase 1 521, relaunch 15, real-data
  17, script-side 7), `FAILS=0` in every phase.
- The expected baseline was 558. The repo was already at commit `404d330`
  (Items 1–4), whose two added guards bring the raw total to 560; the spec below
  documents that +2. No check was missing, so editing proceeded from 560.

### Item 1 — Collection moves into the gear menu

- The header search row now contains only the search field (with its in-field
  clear/magnifier control) and the gear button. The old `link-collection`
  button and its `collectionButton` object are gone.
- Gear menu order is exactly **Refresh / Hide pre-orders / Keyboard shortcuts /
  Collection / Log out**. The short owner labels replace the older "Refresh
  library" and "Log out / Clear Bandcamp session" wording.
- Collection runs the same code path as the removed header button:
  `Service.openExternal(collectionUrl)`, with the same username-derived
  `https://bandcamp.com/<user>` URL, same disabled-until-username behaviour and
  the URL as its tooltip.
- `focusTokens` loses the `link-collection` stop. The rest of the Part B chain is
  unchanged: search → clear/magnifier → gear → Albums → Playlists → Sort →
  direction → left list → Up Next + Clear (when queued) → track list → Shuffle →
  Prev → Play/Pause → Next → search. The shortcuts view's Tab row text follows.
- The gear menu itself keeps its existing Up/Down/Enter handling; menu items are
  not separate Tab tokens.
- Item 5 below replaces this temporary gear button with the cat-and-flute mark.
  The menu contents, labels, order and Collection behaviour are unchanged.

### Item 2 — Product spelling normalised to "Bandcamp"

- Every text occurrence became `Bandcamp`, including the product name
  `OmaTimeAtBandcamp`: plugin manifest name/displayName, README, both specs,
  V2 notes, UI strings, code comments, the MPRIS Identity, the Subsonic client
  name, and harness expectations.
- No file, directory, plugin id, IPC target, D-Bus name, state key or other
  lowercase functional identifier was renamed.
- The GitHub repository description was updated with `gh repo edit` to
  `OmaTimeAtBandcamp - Bandcamp collection/player plugin for Omarchy`.
- Old-spelling occurrences changed, per file (30 total):

| File | Old hits |
|---|---:|
| `manifest.json` | 2 |
| `README.md` | 6 |
| `docs/omatimeatbandcamp-v2-spec.md` | 5 |
| `docs/omatimeatbandcamp-v3-spec.md` | 3 |
| `Panel.qml` | 3 |
| `BcButton.qml` | 1 |
| `Service.qml` | 1 |
| `backend/mpris.py` | 3 |
| `backend/subsonic.py` | 1 |
| `mpvctl.py` | 1 |
| `spike/subsonic_client.py` | 1 |
| `cookies.py` | 1 |
| `tests/qml/shell.qml` | 1 |
| `tests/test_phase8_mpris.py` | 1 |

A repo-wide text grep for the old spelling now returns zero hits. The harness
builds the search string at runtime so its own source does not reintroduce it.

### Item 3 — Focus uses the theme accent

- `BcButton` gains `focusColor: Color.accent` (the same `qs.Commons.Color`
  source the panel already uses for foreground/background/pane accents) and
  paints its focused border as `Border.flat(focusColor, Style.focusBorderWidth)`.
  No hex value is introduced.
- The search field's focused border is the same full-strength accent; its
  unfocused and hover borders still come from the shell's normal token chain.
- Focused rows in the album/playlist list, Up Next queue and track list carry an
  accent ring (`border.color: Color.accent`) in addition to the existing cursor
  tint. Unfocused rows keep a zero-width transparent border, so their painting is
  byte-identical to v3.5.
- Harness checks assert the focused button/field/row colour equals the theme
  fixture's `Color.accent` and differs from the unfocused colour. Existing colour
  and pane-border checks are unchanged.

### Item 4 — Shortcuts view fits without scrolling

- The flat shortcut list is grouped on the fly and reflowed into two equal
  columns: **Navigation** then **Playback** on the left, **Queue** then
  **Search & menus** on the right.
- All 16 rows, their text and the existing `bodySmall`/`caption` font sizes are
  unchanged. Only internal spacing is tighter: key column 108 px, description at
  112 px, 2 px row padding and 6 px between groups.
- The Flickable remains as a fallback, but the harness now asserts
  `contentHeight <= height` under the harness theme. The panel's 180 px floor and
  396 px cap are unchanged.

### Item 5 — Header layout + cat-and-flute settings control

- The header is now one `headerStack` item holding the title band and the search
  row, so the settings control can overlay both without adding flow height. The
  title is vertically centred in the band from the panel's top border to the top
  of the search bar.
- The search field ends exactly where the settings zone begins: its width is
  `searchRow.width - headerCatZoneWidth`, with no extra gap. The zone starts
  where the old Collection button began, rebuilt from the old Collection text
  metrics, control padding, border widths, one row gap and the old gear width, so
  the field keeps approximately its previous length.
- The zone starts at the panel's top border and ends at the bottom of the search
  row. Its `BcButton` is therefore the one intentionally tall control; every
  other named control still shares the 28 px height. It is borderless at rest,
  gets the shell's existing hover fill, and shows the theme accent outline when
  focused. `objectName: "settingsButton"` is unchanged, so the Tab chain keeps
  the same stop and there is still no `link-collection` stop.
- The visual mark is `CatMark.qml`: a vector trace using QML `Shape`/`ShapePath`
  in the reference drawing's 508×346 coordinate space. Every stroke binds to
  `strokeColor`, which the panel sets to `Color.accent`. No bitmap is embedded;
  `docs/cat-and-flute-reference.jpg` is committed alongside it as provenance.
- The title-only header check remains true: there are no buttons inside
  `headerRow`; the cat control is a sibling overlay in `headerStack`.

### Addendum — Settings-menu leading icons

- `BcButton` gains a dedicated, fixed-width leading icon slot
  (`leadingIconText`, `leadingIconSlot`, `leadingIconSpinning`) that shifts the
  label and the existing icon/check slot. The original check slot is untouched.
- All five settings entries use the leading slot: Refresh `\uf021`, Hide
  pre-orders `\ueeb6`, Keyboard shortcuts `\uf11c`, Collection `\uf07b`, Log out
  `\uf08b`. The harness asserts all five icons occupy one aligned x/y box.
- The installed `JetBrainsMono Nerd Font` was inventoried before choosing a
  glyph. `\ueeb6` renders as the theatre masks, so the eye-slash fallback is not
  used. Hide pre-orders keeps its existing check display in the original slot
  (`\uf00c` when On, an em-space placeholder when Off), plus the mask in the new
  slot. Menu order and the checkable behaviour are unchanged.

### Tests (raw counts)

Clean run on the final tree, with no file edited while the harness was running:

- `python3 -m unittest discover -s tests -t .`: **97 tests OK, 5 skipped**.
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: **5 tests OK**.
- `tests/qml/run.sh`: **567 checks passed** (phase 1 528, relaunch 15,
  real-data 17, script-side 7), `FAILS=0` in every phase, exit 0.

The starting total was 560 (see Baseline). Item 5 and the icon addendum add 7
checks and rewrite the stale layout expectations; no existing check was removed
or weakened.

> Count note: an earlier run reported 743 because `BcButton.qml` was edited
> while Quickshell was watching the plugin, which hot-reloaded the shell and
> restarted the step list mid-phase. The clean rerun above has one
> `loaded phase=…` line per launch and no reload/step-throw lines.

### Harness checks updated (and why)

1. Product-name/title expectation is now `OmaTimeAtBandcamp`.
2. Header composition: Collection is gone, the search row holds only the field,
   the cat settings control sits beside it in `headerStack`, the field width
   formula is `row − cat zone`, and the open window has 10 buttons (was 11).
3. Settings-menu exact contents are the five owner labels in order; the new
   Collection item's URL/enabled style is checked inside the menu. The logout
   keyboard path presses Down four times (was three).
4. Phase 7 now opens Collection through the settings menu and still asserts exactly
   the same opened URL.
5. Header focus walk is six stops (was seven) and both full Part B chain
   expectations lose `link-collection` (14→13 with no queue, 16→15 with one).
6. The shortcuts-view keyboard path is Tab ×2 to the settings control (was ×3).
7. The shortcuts-view row-size check uses the reflowed 108/112 px columns, and
   the old "scrolls internally" assertion becomes a no-scroll fit assertion
   because that is the new owner requirement.
8. Added focus-accent checks for a button, the search field and list/queue rows.
9. Added a script-side repo-text check for the old product spelling, with the
   pattern assembled at runtime.
10. The settings control check now requires the cat mark in `headerCatZone`, an
    empty `iconText`, the Settings tooltip and no gear glyph, instead of the old
    gear-in-search-row expectation.
11. The search-field width and right-edge checks now measure against the cat
    zone (field ends at its left edge, cat zone ends at the row's right edge).
12. The shared-height check excludes the one intentionally tall cat control and
    asserts that its height spans both header rows. All ordinary buttons stay at
    the 28 px control height.
13. The bordered-style check keeps toolbar/footer buttons bordered and accepts
    exactly two intended borderless controls: the in-field action and the
    at-rest cat mark.
14. The menu-position check now looks for the cat control in `headerCatZone`
    rather than in `searchRow`.
15. The shared-icon-font check uses Sort's rendered glyph as the reference,
    because the old gear glyph no longer exists.
16. Refresh/Log out glyph checks now read the new leading-icon slot, and new
    checks assert one aligned leading box across all five rows, the mask icon on
    Hide pre-orders, and its unchanged check slot/state.
17. Added title-centring, cat-zone span, vector/bitmap, accent-stroke and
    real-panel-size screenshot checks.

No check was weakened or deleted.

### New harness coverage

- Collection is absent from the header and present in the gear menu with the
  exact fixture URL; opening it uses the recorded opener path.
- Focused button, field and row borders equal `Color.accent`; an unfocused field
  and an unfocused queue row differ.
- The five settings entries are exact and in order.
- The cat mark is a vector Shape with no bitmap and every stroke uses
  `Color.accent`; it spans from the panel top to the search row bottom, starts at
  the field's right edge, and does not add header flow height.
- The title centre matches the band centre, and the full popup saves a real-size
  screenshot at `/tmp/omatime-v351-header.png`.
- All five settings rows have a leading icon in one aligned box; Hide pre-orders
  uses the theatre-masks glyph and keeps its check in the original slot.
- The shortcuts groups are side by side in the requested order and the content
  fits the view height without scrolling.
- The repo text contains no old product spelling.

### Deviations / owner-visible decisions

- The settings labels are the owner's exact short wording (Refresh, Log out), not
  the older longer labels.
- Collection is a menu item, so it is intentionally not its own Tab stop; the
  settings menu keeps Up/Down/Enter navigation.
- Focus uses an added full-strength accent ring rather than changing the shell's
  shared focus-fill token, so every unfocused colour stays exactly as it was.
- The shortcuts key column is narrower to suit two columns; text and font sizes
  are unchanged.
- The header control is a traced vector drawing, not a theme icon: the cat and
  flute follow `docs/cat-and-flute-reference.jpg`, with the reference committed
  as provenance. Stroke colour is still the theme accent, not a hard-coded hex.
- The settings control is deliberately taller than the shared 28 px control
  height so it can span the title band and search row; every other control keeps
  the one-height rule.
- Menu icons moved to a new leading slot so Hide pre-orders could gain the mask
  without losing its check. The checkable display and menu order are unchanged.

### Owner live check

1. `omarchy restart shell`, open the panel. The header is the title band, the
   search field and the cat-and-flute settings mark at the right; there is no
   gear icon. Confirm the title looks centred in the band and the field ends at
   the mark rather than under it.
2. Click the cat mark: the settings menu is Refresh / Hide pre-orders /
   Keyboard shortcuts / Collection / Log out, in that order. Every row has a
   left icon; Hide pre-orders shows theatre masks and keeps its check on the
   right. Choose Collection: the same public collection page opens as before.
3. Press Tab from search through the whole chain: search → clear/magnifier →
   settings (cat) → Albums → Playlists → Sort → direction → album/playlist list
   → Up Next and Clear (only with a queue) → track list → Shuffle → Previous →
   Play/Pause → Next → search. Shift+Tab reverses it.
4. Check focus visibility against the real theme accent on the cat mark, Sort,
   direction, footer controls, search field and a focused list/queue row.
5. Open Keyboard shortcuts: the four groups are in two columns with no scrolling
   needed; Esc restores the panes, selection, scroll and queue.
6. Look at `/tmp/omatime-v351-header.png`: it is the full popup at its real
   size, saved by the harness.

## v3.5.2 cat-and-flute stencil (owner-requested, 2026-10-28)

Branch `v2`. v3.5.1 drew the header mark as a hand-traced vector. The owner
asked for the reference drawing itself instead: a soft-ramp stencil, tinted
with the live theme accent and fitted to the whole cat zone at the real header
size (108.86 × 74.00). This section records the resumed-session audit, the
finished implementation and every changed check.

### Baseline audit (resumed session, before editing)

The previous session was cut off by the provider quota. Its tree was audited,
not rebuilt:

- `git status`: modified `CatMark.qml`, `Panel.qml`, `tests/qml/run.sh`,
  `tests/qml/shell.qml`; untracked `assets/cat-flute-mask.png`,
  `tests/test_cat_mask_asset.py`, and the unrelated research note
  `docs/radio-spike-2026-10.md`.
- `git log -3`: `990ce81` v3.5.1 cat-and-flute header settings; `404d330`
  v3.5.1 Collection/spelling/focus/shortcuts; `251370d` v3.5 interaction pass.
- `assets/cat-flute-mask.png` already existed: 509 × 346, 8-bit RGBA,
  33,294 bytes, sha256
  `7aa57c2944b7e10fa400930a74c9016796f3216f2ff704600701563780314e87`.
- The QML stencil render, the centred zone-filling geometry, the asset test,
  the new harness checks and the screenshot pixel probe were already
  implemented and passing. Only this specification section and the commit
  remained.
- Suites as found: Python **99 tests OK, 5 skipped**; QML **573 checks,
  `FAILS=0`** in all three phases, stencil pixel probe passing.

For the delta, commit `990ce81` was run in a throwaway worktree: **567 checks**
(phase 1 528 + relaunch 15 + real-data 17 + script-side 7). The older v3.5.1
section's figure of 560 could not be reproduced from that commit and is stale
by 7 checks that predate this pass. Against the measured 567, v3.5.2 adds 6:
5 phase-1 checks and 1 script-side pixel probe. Python goes 97 → 99 with the
two asset tests.

### The asset — `assets/cat-flute-mask.png`

- Derived from `docs/cat-and-flute-reference.jpg` (kept as provenance), cropped
  tight to the drawing's ink box: 509 × 346, aspect 1.4711.
- White RGB with alpha only; no theme colour is baked in. The PNG has 16,865
  visible pixels, of which **16,833 (99.8%) have partial alpha** and only 32
  are fully opaque. That soft ramp preserves the JPEG's antialiased line edges
  instead of hard-thresholding them to 0/255.
- All four corners are alpha 0 and the visible ink reaches every crop edge
  (0..508, 0..345), so there is no background card, drop shadow or blank band.
- No generator script is committed: the PNG is the reviewed asset, the JPEG is
  the design provenance. Tests decode the PNG with the standard library.

### The render — `CatMark.qml`

- `CatMark` is now an `Item` named `catStencil` with implicit size 509 × 346 and
  `tintColor: Color.accent` (bound again in `Panel.qml`).
- A hidden `Image` (`catMaskImage`) loads the PNG, decoded at physical display
  size (`width × Screen.devicePixelRatio`), so Qt performs one high-quality
  downscale instead of the Canvas sampler point-sampling the thin strokes.
- A `Canvas` (`catMaskCanvas`, `renderTarget: Canvas.Image`) draws the mask with
  `source-over`, then fills the whole canvas with `tintColor` using `source-in`.
  The result is one flat theme colour whose alpha is the stencil's alpha — an
  opacity-mask tint, not a recoloured copy of the JPEG.
- Repaint triggers: image `Ready`, canvas resize, `tintColor` change, plus a
  short 20 × 50 ms startup burst that stops itself once the header settles.
- There is no vector `Shape` and no image data embedded in QML; the PNG is the
  only source.

### Geometry — `Panel.qml`

- The mark keeps `headerCatZoneWidth × headerCatZoneHeight` (the 116.86 × 75.98
  zone that spans the title band and the search row).
- Fit rule: `width = min(zoneW - 2*Style.space(1), (zoneH - 2*Style.space(1)) *
  aspect)`; height follows from the aspect. Width is the limiting axis here.
- Measured in the harness: art **108.86 × 74.00**, centre **756.56, 78.00**,
  zone centre **756.06, 78.00** (0.5 px, within 1 px on both axes),
  height ratio **0.974**. Margins are 4 px left/right and 1 px top/bottom, equal
  on the vertical axis, so the mark fills the zone instead of floating in it.
- Aspect is preserved exactly (never stretched), and the old `scale:` transform
  is gone, so the implicit size and hit target agree.

### Changed checks (enumerated)

Removed/replaced (phase 1), because the owner deliberately inverted the old
"no bitmap" invariant:

- `v3.5.1: the cat mark is a vector Shape (no bitmap) and every stroke uses the
  theme accent`.

Added (phase 1, net +5 after the replacement):

- `v3.5.2: the cat mark is the shipped stencil image, not the old vector trace`
  — asserts `catStencil`, the canvas, `cat-flute-mask.png` in `maskFile`, 509 ×
  346 implicit size, and the absence of `catMarkShape`.
- `v3.5.2: the stencil is rendered through its alpha mask in the theme accent`
  — canvas available, raster target, image `Ready`, `tintColor` and
  `renderedColor` both `Color.accent`, aspect matches 509/346.
- `v3.5.2: the stencil's bounding-box centre matches the cat-zone centre on both
  axes` (≤ 1 px).
- `v3.5.2: the stencil fills at least 90% of the cat-zone height`.
- `v3.5.2: the stencil preserves the asset aspect ratio (never stretched)`.
- `v3.5.2: the stencil sits with equal small top/bottom margins (no blank band
  under the flute)`.

Renamed only (same assertion, new screenshot):

- `v3.5.1: the header rendered at the real panel size (full popup, no scaling)`
  → `v3.5.2: …`, now saving `/tmp/omatime-v352-header.png`.

Added (script side, +1), after phase 1 saves the screenshot:

- `PASS the rendered cat stencil is the theme accent, with no baked white` —
  crops the art rect from the saved PNG (inset 3 px to exclude the zone border),
  requires ≥ 150 ink pixels, a peak within 10/255 of the QML-reported accent,
  zero pure-white pixels, and no pixel brighter than the accent.

Added (Python, +2, `tests/test_cat_mask_asset.py`):

- `test_mask_is_white_ink_on_a_transparent_background` — exact 509 × 346 RGBA,
  white RGB everywhere visible, alpha 0 at all four corners, > 1000 ink pixels.
- `test_mask_has_a_soft_ramp_and_a_tight_full_drawing_crop` — > 500 partial-alpha
  pixels (and fewer than half the image), a tight crop that reaches all four
  edges, and the 509/346 aspect.

No other check was weakened or deleted. The v3.5.1 screenshot check still
requires a full-popup grab at the panel's exact size.

### Results

- Python: **99 tests OK, 5 skipped** (`97 → 99` with the two asset tests).
- QML: **573 checks**, `FAILS=0` in all phases (phase 1 533, relaunch 15,
  real-data 17, script-side 8); `QML tests: OK`.
- Pixel probe on the saved PNG:
  `rect=705,4,104,69 accent=#cacccc inkPixels=621 peak=#c3c5c5
  pureWhitePixels=0 overAccentPixels=0` — the peak rendered pixel is 7/255
  below the harness accent (thin-line antialiasing after downscaling), and
  there is no baked white.
- Harness screenshot: `/tmp/omatime-v352-header.png`, **835 × 570**, the whole
  popup at its real size (`saved=true`, image `Ready`, dimensions equal to
  `keyboardPanel()`). The cat mark is at the top right, one tall target from the
  panel top to the search row's bottom.

### Deviations / owner-visible decisions

- The mark is a raster stencil (Canvas), not a vector Shape. This is the owner's
  request: the reference's own line work replaces the trace. The PNG is white
  with alpha, so a theme change needs no asset regeneration.
- The asset is cropped exactly to the ink box, so the ear tips are the topmost
  ink. At 108.86 × 74.00 the strokes are inherently about 1 px and the tips are
  soft; a transparent pad would not add ink. The one-pixel vertical margin keeps
  the mark inside the zone while filling 97.4% of its height.
- The Canvas is raster on purpose so `grabToImage` captures it in the harness as
  well as in the live shell.
- The Python asset test uses only the standard library, so it runs on a bare
  system without Pillow.
- `docs/radio-spike-2026-10.md` is a separate research note found untracked in
  the tree and is intentionally **not** part of this release.

### Owner live check

1. `omarchy restart shell`, open the panel. The cat-and-flute mark sits at the
   top right, spanning the title band and search row; it is tinted with the live
   theme accent, not white and not a hard-coded colour. Switch theme/accent and
   reopen: the mark follows without restarting anything else.
2. Confirm the mark is centred in its zone and fills it: no large blank band
   under the flute, no drift left or right, and the drawing is not stretched.
3. Click the mark: the settings menu still opens with Refresh / Hide pre-orders /
   Keyboard shortcuts / Collection / Log out. Tab focus still lands on the mark
   and shows the accent outline.
4. Look at `/tmp/omatime-v352-header.png` (835 × 570): the full popup at real
   size, with the stencil visible at the header's right end.
5. Expected live-look caveat: the reference is fine line art, so at header size
   the strokes are thin and the ear tips are soft. That is the raster stencil at
   1:1, not a missing crop; the full drawing (face, whiskers, flute, paws, body)
   is present.

## v3.5.3 cat final form — SVG trace, centred in every header state (2026-10-28)

### Baseline (fresh session, before editing)

- Branch/commit: `v2` @ `851428e` (the v3.5.2 raster-stencil commit).
- Python: **99 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK** (`OMATIME_LIVE=1`).
- QML: **573 checks**, `FAILS=0` in every phase (phase 1 533, relaunch 15,
  real-data 17, script-side 8); `QML tests: OK`.
- The counts matched the quoted baseline exactly before any file was changed.

### Input audit — `docs/cat-flute.svg`

- Present, 18,023 bytes, and **verified before use**: the header comment is
  `<!-- Generator: visioncortex VTracer 0.6.12 -->`, the root is
  `<svg width="508" height="346">`, and there are exactly **5 `<path>`**
  elements, each `fill="currentColor"`.
- Path inventory (exact `d` data is copied into `CatMark.qml`):

  | # | transform | `d` length | `d` sha256 (first 16) |
  |---|-----------|-----------:|-----------------------|
  | 1 | `translate(225.8125,0.5)` | 16,149 | `b9ce2a65764b9aec` |
  | 2 | `translate(178,105)` | 319 | `054b17d8280a37e9` |
  | 3 | `translate(94,106)` | 353 | `9f32a2f28a4e9811` |
  | 4 | `translate(259.12109375,181.62109375)` | 366 | `c7b7bce6172af5f9` |
  | 5 | `translate(362,182)` | 320 | `6f9a5ca5f08b32c4` |

- The shipped asset is byte-identical to the input:
  `assets/cat-flute.svg` and `docs/cat-flute.svg` both hash to
  `29f42400c1b1369d47b873f56c006e826e7ac1f6a16a207a1a73be3aba8a673b`.

### The render — `CatMark.qml`

- The PNG mask, hidden `Image`, `Canvas`, `source-in` compositing and repaint
  timers are gone. `assets/cat-flute-mask.png` was deleted.
- `CatMark` is a vector `Item` (`objectName: "catStencil"`) with implicit size
  **508 × 346**, `artAspect = 508 / 346`, and `pathCount = 5`.
- Each SVG `<path>` is a `Shape`/`ShapePath` with a `PathSvg` whose `path` is the
  **exact `d` string from the file**. The file's `translate(...)` is applied as a
  `Translate` on the corresponding Shape. A `Scale` on the inner 508 × 346 layer
  maps the SVG coordinate space into the fitted item; it is visual only, so the
  item's width/height remain the fit box the geometry checks measure.
- Fill binding: `ShapePath.fillColor: root.tintColor`; `CatMark.tintColor` is
  `Color.accent`, and `Panel.qml` binds `tintColor: Color.accent` as before.
  There is no baked colour and no raster source. `fillRule` is
  `ShapePath.WindingFill`, the SVG default nonzero rule.
- Exposed for the harness: `svgFile`, `pathModel`, `pathData`, `pathCount`,
  `isVector`, `fillColor`, `renderedColor`, `artAspect`.

### Placement — `Panel.qml`

- The header block now explicitly includes the status row. While
  `service.status !== ""` (including `Syncing library…`), a caption row
  (`headerStatusRow`, `headerStatus`) sits under the search row; the status text
  stops before the cat zone. The toolbar no longer duplicates the status text.
- `headerStack.height` and `headerCatZoneHeight` both grow by the status row +
  the column spacing while it is visible. The cat zone still starts at the
  panel's top border and is as wide as before.
- The mark is fitted on **both** axes with the same one-pixel margin:
  `width = min(zoneW - 2m, (zoneH - 2m) * aspect)`, `height = width / aspect`,
  then `anchors.centerIn: parent`. Aspect is never stretched.
- Measured in the harness:

  | state | zone | art | art centre vs zone centre | top/bottom margins |
  |-------|------|-----|---------------------------|--------------------|
  | normal | 125.88 × 75.98 | 108.65 × 74.00 | 756.45,78.00 vs 756.06,78.00 (0.39 / 0.00 px) | 1.00 / 1.00 px |
  | syncing (tall) | 125.88 × 100.00 | 123.88 × 84.37 | 756.06,90.19 vs 756.06,90.00 (0.00 / 0.19 px) | 8.00 / 7.63 px |

- In the tall state the art is width-limited and keeps the 508/346 aspect; it is
  centred in the whole block rather than pinned to the top, and the ear tips are
  8 px below the top border. The normal state keeps its 1 px breathing margin.

### Button behaviour

- Unchanged: same settings menu (`toggleMenu`), `Settings` tooltip, Tab position
  immediately after the search action, hover tint, and accent focus outline on
  the zone. Only the zone's height grows with the status row.

### Changed checks (enumerated)

Removed/replaced in phase 1 (the raster invariants no longer apply):

- `v3.5.2: the cat mark is the shipped stencil image, not the old vector trace`
  → `v3.5.3: the cat mark is the shipped SVG trace, not a raster stencil`
  (asserts `catStencil`, no `catMaskCanvas`/`catMaskImage`, `cat-flute.svg`,
  508 × 346, 5 paths, `catPath0`/`catPath4`).
- `v3.5.2: the stencil is rendered through its alpha mask in the theme accent`
  → `v3.5.3: every cat path is filled from the theme accent binding (no baked
  colour)`.
- `v3.5.2: the stencil's bounding-box centre matches the cat-zone centre on
  both axes` → same assertion renamed `v3.5.3` for the SVG mark.
- `v3.5.2: the stencil fills at least 90% of the cat-zone height` → `v3.5.3`.
- `v3.5.2: the stencil preserves the asset aspect ratio (never stretched)` →
  `v3.5.3`, now against 508/346.
- `v3.5.2: the stencil sits with equal small top/bottom margins (no blank band
  under the flute)` → `v3.5.3: … and clear of the top border`.
- `v3.5.2: the header rendered at the real panel size (full popup, no scaling)`
  → `v3.5.3: the normal header rendered at the real panel size …`, saving
  `/tmp/omatime-v353-header.png`.

Added in phase 1 (normal/tall geometry + screenshots):

- `v3.5.3: the SVG mark's bbox sits fully inside the cat zone (no clipping)`.
- `v3.5.3: the syncing status row is inside the header block and grows the cat
  zone`.
- `v3.5.3: tall syncing header: the art centre matches the zone centre on both
  axes` (≤ 1 px).
- `v3.5.3: tall syncing header: the art bbox stays inside the zone, clear of the
  top border`.
- `v3.5.3: tall syncing header: equal top/bottom margins and aspect preserved`.
- `v3.5.3: the tall syncing header rendered at the real panel size (full popup,
  no scaling)`, saving `/tmp/omatime-v353-syncing.png`.
- `v3.5.3: the status row hides again and the cat zone returns to its normal
  height`.

Replaced on the script side (same slot, stricter):

- `PASS the rendered cat stencil is the theme accent, with no baked white` →
  `PASS the rendered cat SVG paths are the theme accent at full strength, with
  no baked white`. The probe now requires `peak == Color.accent` exactly
  (previously within 10/255) and at least one exact-accent pixel, plus no pure
  white and nothing above the accent.

Replaced in Python (2 raster tests → 3 SVG tests, net +1):

- Deleted `tests/test_cat_mask_asset.py` and its PNG decoding/alpha-ramp tests.
- `tests/test_cat_svg_asset.py::test_svg_is_the_shipped_vtracer_trace` — file
  present, VTracer header, 508 × 346, 5 paths, PNG gone and unreferenced.
- `…::test_every_svg_path_is_current_color` — all 5 paths `currentColor`, no
  hex/RGB fill, no `<image>`/base64.
- `…::test_qml_path_data_matches_the_svg_and_is_fill_bound` — the 5 `d` strings
  and transforms in `CatMark.qml` equal the SVG exactly; fill is
  `tintColor: Color.accent`, not a literal colour.

No existing check was weakened or deleted without a replacement above.

### Results

- Python: **100 tests OK, 5 skipped** (`99 → 100`).
- Live fixtures: **5 tests OK**.
- QML: **580 checks**, `FAILS=0` in every phase (phase 1 540, relaunch 15,
  real-data 17, script-side 8); `QML tests: OK` (`573 → 580`).
- Pixel probe on the saved normal screenshot:
  `rect=705,4,104,69 accent=#cacccc inkPixels=982 exactAccentPixels=6
  peak=#cacccc pureWhitePixels=0 overAccentPixels=0`.
- Normal screenshot: `/tmp/omatime-v353-header.png`, **835 × 570** (the whole
  popup at its real size).
- Tall syncing screenshot: `/tmp/omatime-v353-syncing.png`, **835 × 594** (the
  header is 24 px taller; the whole popup grows with it). Both images are
  `saved=true`, `Image.Ready`, and match `keyboardPanel()` dimensions.

### Deviations / owner-visible decisions

- The `Syncing library…` status line moved from the toolbar's right end into a
  dedicated header row under the search field. This is what makes the header
  block (and the cat zone) genuinely taller while a status is shown; the text
  stops before the zone so it never runs under the button. Other statuses
  (`Library updated…`, errors) use the same row for consistency.
- In the tall state the art becomes width-limited (123.88 × 84.37) instead of
  growing vertically. It keeps the asset's aspect and the fit rule; no vertical
  stretch or blank band. The ears stay 8 px clear of the top border.
- The SVG stays the reviewed asset; `docs/cat-flute.svg` is kept as provenance
  alongside the shipped copy, and no generator is committed.
- `docs/radio-spike-2026-10.md` remains an unrelated untracked research note.

### Owner live check

1. `omarchy restart shell`, open the panel. The cat-and-flute mark is now a
   crisp vector trace in the live theme accent — no white raster edges. Switch
   theme/accent and reopen; the fill follows immediately.
2. Normal header: the mark is centred in the zone, ears clear of the top border,
   and the flute/body are fully visible.
3. Trigger a library refresh so `Syncing library…` appears: the header grows by
   the status row, the mark stays centred in the taller block (not pinned to the
   top), and the ears do not clip the border. After the status clears, the
   header returns to its normal height.
4. Click the mark: the same settings menu opens, with the same tooltip and Tab
   position; hover and accent focus outline are unchanged.
5. Look at `/tmp/omatime-v353-header.png` (835 × 570) and
   `/tmp/omatime-v353-syncing.png` (835 × 594): both are the full popup at real
   size, and the mark is centred in its zone in both.

## v3.5.4 cat column + bold art + eye-slash (2026-10-28)

### Baseline (fresh session, before editing)

- Branch/commit: `v2` @ `8f330de` (the v3.5.3 SVG-trace commit).
- Python: **100 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK** (`OMATIME_LIVE=1`).
- QML: **580 checks**, `FAILS=0` in every phase (phase 1 540, relaunch 15,
  real-data 17, script-side 8); `QML tests: OK`.
- The counts matched the quoted baseline exactly before any file was changed.

### Input audit — `docs/cat-flute-bold.svg`

- Present, exactly **15,203 bytes**, with the header comment
  `<!-- Generator: visioncortex VTracer 0.6.12 -->`.
- Root size is **508 × 346**, and it has exactly **3 `<path>`** elements, all
  `fill="currentColor"`. The asset was copied byte-for-byte to
  `assets/cat-flute.svg`; both files hash to
  `a8dfadbd8b06a38543a986328148396210178e2bca8a0f494eb39e3e50710fe2`.

| # | transform | `d` length | `d` sha256 (first 16) |
|---|-----------|-----------:|-----------------------|
| 1 | `translate(34.01953125,-0.609375)` | 14,097 | `4a5c5cf2f5351caa` |
| 2 | `translate(95,103)` | 345 | `ec8cf09c2f76323f` |
| 3 | `translate(179.8125,103.3125)` | 372 | `6b80937e8d601ae6` |

### Bold art — `CatMark.qml`

- The same `Shape` / `ShapePath` / `PathSvg` renderer is kept; only the path
  inventory changed from 5 paths to the bold file's **3 paths**. Each `d`
  string is copied exactly from the SVG, each file `translate(...)` sits on its
  Shape, and the inner 508 × 346 layer is scaled into the fitted item.
- Every `ShapePath.fillColor` is `root.tintColor`; `tintColor` is
  `Color.accent` and Panel binds it again. No raster and no baked colour.
- Added `inkCentroidX = 0.3739915779`, `inkCentroidY = 0.5262729689`: the
  alpha-weighted centroid of a high-resolution render of the bold SVG,
  normalised to the 508 × 346 viewBox. Panel positions the mark by this point.

### Layout — `Panel.qml`

- **Header:** title + search only. The v3.5.3 status row was removed from the
  header, and `headerStack.height` is back to two control rows plus one gap.
- **Search field:** `searchFieldWidth = round(panel.contentWidth * 0.72) -
  headerTopInset` (the first attempt used `panel.width`; see the retry
  postmortem below for the live-only failure). Measured right edge is
  **71.98%** of the popup width (accepted 68–75%). Field height, styling,
  placeholder, clear/magnifier and Tab behaviour are unchanged.
- **Cat column:** an overlay sibling of the content column (so it does not
  participate in the Column layout), `x = searchFieldWidth`, from the panel top
  border (`y = -headerTopInset`) down to the top of the panes. Measured
  **218 × 112**; the whole column is the one `settingsButton`, so hover and the
  accent focus outline frame all of it.
- **Mark:** fit with a 4 px margin on both axes, aspect preserved; positioned so
  the ink centroid lands on the column centre:
  `x = colW/2 - inkCentroidX*width`, `y = colH/2 - inkCentroidY*height`, with
  bbox clamps that keep at least 1 px above the top border.
  Measured art **152.69 × 104.00**, bbox top **1.27 px** below the border,
  centroid exactly on the column centre in QML (`710.00,96.00` vs
  `710.00,96.00`).
- **Sync status:** a `syncStatusLabel` Text in the toolbar row, visible only
  while `service.status` starts with `Syncing library`. It is an overlay, not a
  Row child. Measured rect **505,127,96 × 14**, right edge **601.00** (flush
  with the field), Sort-direction right edge **455.84**, clearance **49.16 px**
  (≥ 8 required). The label overlaps no control and shifts no geometry.
- **Hide pre-orders:** leading icon is now the Font Awesome eye-slash
  `\uf070`; the same leading slot, font, icon size and row height are used, and
  the original check slot (`\uf00c` / blank) is unchanged.

### Changed checks (enumerated)

Removed/replaced (phase 1) because the tall-header design was replaced:

- `v3.5.3: the syncing status row is inside the header block and grows the cat
  zone` → removed; the header no longer contains a status row.
- `v3.5.3: tall syncing header: the art centre matches the zone centre on both
  axes` → replaced by the centroid/column checks.
- `v3.5.3: tall syncing header: the art bbox stays inside the zone, clear of
  the top border` → replaced by the column bbox/ear-clearance check.
- `v3.5.3: tall syncing header: equal top/bottom margins and aspect preserved`
  → removed with the tall header; aspect fit is asserted in the new fit check.
- `v3.5.3: the status row hides again and the cat zone returns to its normal
  height` → replaced by the label-hides/column-stays-put check.
- `v3.5.1: the cat zone spans the title band and the search row…`, the old
  field-width/zone-width checks, and `v3.5.1: only the cat settings control is
  deliberately taller (it spans both header rows)` were replaced by the column
  geometry checks below.
- `v3.5.3: the cat mark is the shipped SVG trace` → `v3.5.4: the cat mark is
  the bold shipped SVG trace`, now 3 paths.
- `v3.5.3: every cat path is filled from the theme accent binding` → `v3.5.4:
  every bold cat path…`, now 3 paths.
- `v3.5.1: the settings control is the cat-and-flute mark at the right end of
  the header` → `v3.5.4: the settings control is the cat-and-flute mark with its
  menu`, now checked against the column.
- `v3.5.3: the normal header rendered at the real panel size` → `v3.5.4: the
  normal header rendered at the real panel size`, saving
  `/tmp/omatime-v354-header.png`.
- `v3.5.3: the tall syncing header rendered at the real panel size` → `v3.5.4:
  the syncing-state panel rendered at the real panel size`, saving
  `/tmp/omatime-v354-syncing.png`.
- `v3.5.1 addendum: Hide pre-orders adds the theatre-masks icon…` → `v3.5.4:
  Hide pre-orders uses the eye-slash glyph in the same leading slot and keeps
  its check slot unchanged`.

Added/replaced (phase 1):

- `v3.5.4: the header is title + search only, with no status row in it`.
- `v3.5.4: the search row holds only the field; the cat column sits beside it`.
- `v3.5.4: the search field's right edge sits at ~72% of the panel width
  (68–75% accepted)`.
- `v3.5.4: the cat column starts at the field's right edge and ends at the
  panel's right inner edge`.
- `v3.5.4: the cat column runs from the panel top border to the top of the
  panes`.
- `v3.5.4: the whole cat column is the settings button`.
- `v3.5.4: the title is still centred in the band above the search row`.
- `v3.5.4: the bold mark is fitted inside the column on both axes, aspect
  preserved`.
- `v3.5.4: the mark's ink centroid matches the cat-column centre on both axes`.
- `v3.5.4: the mark's bbox sits fully inside the column with the ears clear of
  the top border`.
- `v3.5.4: the bold mark still fills at least 90% of the column height`.
- `v3.5.4: the ink centroid is measured from the bold asset, not the bbox`.
- `v3.5.4: the syncing label appears in the Albums/Playlists/Sort row only
  while syncing`.
- `v3.5.4: the syncing label's right edge is flush with the search field's
  right edge`.
- `v3.5.4: the syncing label clears Sort direction by at least 8 px and
  overlaps nothing`.
- `v3.5.4: showing the syncing label shifts no header, field, column or control
  geometry`.
- `v3.5.4: the cat column and art geometry are identical in normal and syncing
  states`.
- `v3.5.4: the syncing label hides again and the cat column stays put`.
- `v3.5.4: the label stays hidden for non-sync status text`.

Replaced in Python (same 3 SVG tests, bold inventory):

- `test_svg_is_the_shipped_vtracer_trace` — now asserts the 15,203-byte bold
  asset, VTracer header, 508 × 346, 3 paths.
- `test_every_svg_path_is_current_color` — now 3 `currentColor` paths.
- `test_qml_path_data_matches_the_svg_and_is_fill_bound` — now compares the
  bold file's 3 exact `d` strings/transforms with `CatMark.qml`.

Script side (same accent check plus one new centroid check):

- `PASS the rendered bold cat paths are the theme accent at full strength, with
  no baked white`.
- `PASS the rendered bold cat's ink centroid is centred in the column` — crops
  the column from the saved PNG, alpha-weights the ink against the panel
  background, and requires the centroid within 3 px of the column centre on
  both axes.

No existing check was weakened or deleted without a replacement above.

### Results

- Python: **100 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK**.
- QML: **585 checks**, `FAILS=0` in every phase (phase 1 544, relaunch 15,
  real-data 17, script-side 9); `QML tests: OK` (`580 → 585`).
- Normal geometry: field right edge **71.98%** of panel width; cat column
  **218 × 112**; art **152.69 × 104.00**, top margin **1.27 px**.
- Syncing state: same column/art geometry; label right edge **601.00**, field
  right edge **601.00**, Sort-direction right edge **455.84**, clearance
  **49.16 px**.
- Accent probe:
  `rect=655,4,148,99 accent=#cacccc inkPixels=2855 exactAccentPixels=1470
  peak=#cacccc pureWhitePixels=0 overAccentPixels=0`.
- Centroid probe:
  `column=601,0,219,113 centroid=709.60,55.84 target=710.50,56.50
  error=-0.90,-0.66 inkWeight=2498.6`.
- Normal screenshot: `/tmp/omatime-v354-header.png`, **835 × 570**.
- Syncing screenshot: `/tmp/omatime-v354-syncing.png`, **835 × 570** (same
  layout; only the toolbar label appears). Both are `saved=true`,
  `Image.Ready`, and match `keyboardPanel()` dimensions.

### Deviations / owner-visible decisions

- The cat column is an overlay rather than a Column child. This is deliberate:
  as a Column child it would add its own height to the popup and push the panes
  down. As an overlay it spans the required area without shifting layout.
- The cat column covers the otherwise-empty right end of the toolbar row. No
  control lives there, and the syncing label stops exactly at the column's left
  edge, so nothing is covered.
- The field lands at **71.98%** (inside the allowed 68–75%) rather than exactly
  72.0% because the width is rounded to whole pixels and the panel's left inset
  is subtracted.
- Only `Syncing library...` statuses are rendered in the toolbar label. The
  other transient statuses (`Library updated…`, failures) are not shown in the
  header; the header is title + search only in every state.
- `docs/radio-spike-2026-10.md` remains an unrelated untracked research note.

### Owner live check

1. `omarchy restart shell`, open the panel. The header is just the title and the
   shorter search field; the cat/flute mark is bold, vector, and fills the tall
   right-hand column down to the panes.
2. Confirm the mark's visual centre looks balanced: the ink centroid (body +
   flute mass), not the empty bounding-box centre, is centred in the column.
3. Trigger a refresh: `Syncing library…` appears in the Albums/Playlists/Sort
   row, right-aligned under the search field, with clear space before the
   direction button. Nothing moves while it appears/disappears.
4. Click anywhere in the column: the same settings menu opens. Tab to it: the
   accent outline frames the whole column; hover tints the whole column.
5. Open the gear menu: Hide pre-orders now uses the eye-slash glyph in the same
   left slot, with its check unchanged.
6. Compare `/tmp/omatime-v354-header.png` and `/tmp/omatime-v354-syncing.png`
   (both 835 × 570): identical layout, only the status label differs.

## v3.5.4 retry — live-path width basis (2026-10-28)

The v3.5.4 feature set above is kept: bold 3-path SVG art, shortened search
field, cat column from the panel top border to the panes with the mark placed
by its ink centroid, the syncing label in the controls row (right-aligned to
the field's right edge), and the eye-slash gear glyph. This retry fixes the
live-only geometry failure in the first attempt and adds a harness regression
that reproduces it.

### Baseline (fresh session, before editing)

- Branch/commit: `v2` @ `a486a82` (`Revert "v3.5.4: cat column, bold SVG art,
  eye-slash icon"` on top of `531b8f7`); `git diff 8f330de HEAD` was empty, so
  the tree content equalled `8f330de`.
- Python: **100 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK** (`OMATIME_LIVE=1`).
- QML: **580 checks**, `FAILS=0` (phase 1 540, relaunch 15, real-data 17,
  script-side 8); `QML tests: OK`.
- All four figures matched the quoted baseline exactly before any file changed.

### Phase 1 postmortem — why the harness passed and the live panel did not

The bad tree was checked out in a scratch worktree at
`/tmp/opencode/omatime-531b8f7`; the live plugin directory was never checked
out over.

**a. Live-path instantiation and logs.** The panel was loaded through its real
bar-widget entry point (`Panel.qml`) with the real `qs.Ui.KeyboardPanel` — a
full-screen layer surface with an 835 px card — not `tests/qml/shell.qml`'s
plain-Item stub. Measured on the live session's logical screen:

```
screen=1280x720 KeyboardPanel.width=1280 height=720 contentWidth=835 contentHeight=120
contentColumn at 0,0 size 803x88 searchRow.width=803 searchBand.width=803
searchField at 0,32 size 906x28 right=906 contentRight=803 overflow=103
headerCatColumn at 906,-16 size 0x112 catStencil at 908.99,42.87 size -8x-5.45
```

No `CatMark.qml` error or warning appeared. The shell's own log
(`/run/user/1000/quickshell/by-id/vc0dty1nnt/log.log`) shows no OmaTimeAtBandcamp
panel/widget failure; its only plugin warnings are from unrelated
`rohirik.agent-monitor` / `asdfsnlr.omabricktetris` widgets, plus the expected
`Module path ".../omatimeatbandcamp" is outside of the config folder`. So the
cat was absent because its column was zero-wide, not because the QML failed to
load.

**b. The width basis.** In the harness the field resolves against
`KeyboardPanel.stub.qml`'s root `Item`, whose `width: contentWidth` made
`panel.width == 835`. In the live parent chain it resolves against the real
`KeyboardPanel` `PanelWindow`, which is anchored full-screen, so
`panel.width == 1280` while the visible card is `panel.contentWidth == 835` and
the content column is **803**. The same expression therefore produced:

| value | harness | live |
|---|---:|---:|
| `panel.width` (basis) | 835 | 1280 |
| `contentColumn.width` | 803 | 803 |
| `searchFieldWidth` = `round(panel.width * 0.72) - 16` | **585** | **906** |
| field right edge vs content right | 601 vs 819 | 906 vs 803 (**+103 overflow**) |

**c. The zero-width cat.** `headerCatColumnWidth = max(0,
contentColumn.width - searchFieldWidth)` was `max(0, 803 - 585) = 218` in the
harness and `max(0, 803 - 906) = 0` live. `CatMark` was then fitted to
`parent.width - 2 * fitMargin = 0 - 16`, giving the measured **-8 × -5.45**
item; it painted nothing.

**One root cause:** `searchFieldWidth` was bound to `panel.width`, which in the
real `KeyboardPanel` is the full-screen layer surface (1280 px), not the popup
card width (835 px); the test stub made those two equal (835 px), so the
harness measured 585 px and 218 px of cat while the live panel measured 906 px
and a zero-width cat column.

### Fix at the source

`Panel.qml` now derives the field from the card width that both the real
KeyboardPanel and the stub expose explicitly:

```qml
readonly property real searchFieldWidth: Math.min(contentColumn.width, Math.max(0,
  Math.round(panel.contentWidth * 0.72) - headerTopInset))
```

`contentWidth` is 835 in the real shell and in the stub; the extra
`contentColumn.width` clamp means the field can never run past the card on a
narrow surface. Nothing about the art, centroid placement, column extent,
syncing label or eye-slash glyph changed.

### Regression check — named for this incident

The stub now separates `surfaceWidth` (the full-screen surface, defaulting to
`contentWidth`) from `contentWidth` (the card), and keeps the card/holder sized
by `contentWidth`. Three new harness steps change only `surfaceWidth` to
1280 / 1920 / 2560 px and assert, for each:

- the field is still `round(contentWidth * 0.72) - headerTopInset` (585 px);
- its right edge stays inside the content column and flush with the column's
  left edge;
- the cat column has non-zero width and `CatMark` has non-zero width/height.

Added checks:

- `v3.5.4 retry: at a 1280 px live surface the field stays inside the card and
  the cat keeps nonzero width (531b8f7 regression)`.
- `v3.5.4 retry: at a 1920 px live surface … (531b8f7 regression)`.
- `v3.5.4 retry: at a 2560 px live surface … (531b8f7 regression)`.

Run against `531b8f7`'s `Panel.qml` with the new test files, all three fail:

```
surface=1280 expectedField=585 actualField=906 column=0.00 cat=-8.00x-5.45 ok=false
surface=1920 expectedField=585 actualField=1366 column=0.00 cat=-8.00x-5.45 ok=false
surface=2560 expectedField=585 actualField=1827 column=0.00 cat=-8.00x-5.45 ok=false
FAILS=3 ... QML tests: FAILED
```

With the fix they pass:

```
surface=1280 expectedField=585 actualField=585 fieldRight=601.00 contentRight=819.00 column=218.00 cat=152.69x104.00 ok=true
surface=1920 … ok=true
surface=2560 … ok=true
```

No existing check was removed or weakened. Added **3** QML checks (`585 → 588`);
phase 1 went from 544 to **547**, with relaunch 15, real-data 17 and script-side
9 unchanged.

### Results

- Python: **100 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK**.
- QML: **588 checks**, `FAILS=0` in every phase (phase 1 547, relaunch 15,
  real-data 17, script-side 9); `QML tests: OK`.
- Accent probe: `rect=655,4,148,99 accent=#cacccc inkPixels=2855
  exactAccentPixels=1470 peak=#cacccc pureWhitePixels=0 overAccentPixels=0`.
- Centroid probe: `column=601,0,219,113 centroid=709.60,55.84
  target=710.50,56.50 error=-0.90,-0.66 inkWeight=2498.6`.
- Harness geometry: field **585**, field right **601 (71.98%)**, cat column
  **218 × 112**, art **152.69 × 104.00**, top margin **1.27 px**.
- Live-path geometry with the real KeyboardPanel at 1280 × 720: field **585**
  (right **585**, content right **803**, overflow **-218**), cat column
  **218 × 112**, cat **152.69 × 104.00** — normal and syncing states identical.
- Harness screenshots (full popup, real size): `/tmp/omatime-v354-header.png`
  and `/tmp/omatime-v354-syncing.png`, both **835 × 570**, `saved=true`,
  `Image.Ready`.
- Live-path screenshots (real KeyboardPanel, 1.5 device scale):
  `/tmp/omatime-v354-live-normal.png` and
  `/tmp/omatime-v354-live-syncing.png`, both **1253 × 180** physical px
  (**835 × 120** logical card). The field ends before the cat, the cat paints,
  and only the syncing label changes.

### Owner live check

1. `omarchy restart shell`, open the panel on the real 1280 × 720 logical
   screen. The search field ends around 72% of the popup, not past its right
   edge.
2. The bold cat/flute fills the column from the top border down to the panes;
   the ink centroid is centred, not the empty bbox.
3. Trigger a refresh: `Syncing library…` appears in the controls row,
   right-aligned to the field's right edge; nothing moves.
4. The gear menu still uses the eye-slash leading glyph, and Tab/hover/focus
   still frame the whole cat column.
5. Compare the two live-path screenshots above; the cat column and field are
   identical in both, only the status label differs.

## v3.5.4.1 art swap + fit + status fixups (2026-10-28)

### Baseline (fresh session, before editing)

- Branch/commit: `v2` @ `1cd6b3e`.
- Python: **100 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK** (`OMATIME_LIVE=1`; the full discovery run is
  100 tests OK with the 5 live checks included).
- QML: **588 checks**, `FAILS=0` (phase 1 547, relaunch 15, real-data 17,
  script-side 9); `QML tests: OK`.
- All three surface-width regression checks (1280 / 1920 / 2560 px live
  surfaces) passed before any file changed and still pass after this change.

### ITEM 1 — slim smoothed art

Input audit — `docs/cat-flute-smooth.svg`:

- Present, exactly **19,564 bytes**, SHA-256
  `aeaeed62a216dcac1e9c4d2fd883c3aa289de1492f7e189c4a16cd6e7d19a6cf`.
- Header: `<!-- Generator: visioncortex VTracer 0.6.12 -->`.
- Root is **508 × 345**, exactly **3 `<path>`** elements, all
  `fill="currentColor"`. The file was copied byte-for-byte to
  `assets/cat-flute.svg` (both files hash to the value above).
- The old bold source `docs/cat-flute-bold.svg` remains as history; it is no
  longer the shipped asset.

| # | transform | `d` length | `d` sha256 |
|---|-----------|-----------:|------------|
| 1 | `translate(34,0)` | 18,357 | `1b85727bfea49c32a8075ab79d1c4ebde26009d8d17a74430fe6bd5e883b42fb` |
| 2 | `translate(87.8125,103.5625)` | 416 | `d0b73e1444dc3411fef318638b5cae0c514f5529722759e0ab589e98f20eb5e2` |
| 3 | `translate(172.8125,103.5625)` | 409 | `bdd4109181f3125f34d6d7f31a4e4d615e6a5df0a63dcba32e6ca85a5052d956` |

`CatMark.qml` now carries those three exact `d` strings and transforms, with
`artWidth = 508`, `artHeight = 345`, and the alpha-weighted centroid of a
5,080 × 3,450 render of this asset:

```
inkCentroidX = 0.3889005865
inkCentroidY = 0.5202530254
```

The renderer, `tintColor: Color.accent`, `fillColor`, `pathData`, `pathCount`,
`isVector`, and the Shape/ShapePath/PathSvg structure are unchanged. The
Python asset tests now assert the 19,564-byte asset hash, its byte identity to
`docs/cat-flute-smooth.svg`, the 508 × 345 root, all three path lengths and
full path hashes, and the exact QML path/transform inventory.

### ITEM 2 — 95% fit + 3 px down-nudge

- New Panel constants: `catFitScale = 0.95`, `catCentreNudgeY = 3`.
- The old fit was 152.69 × 104.00 for the bold asset. The slim asset's old fit
  would be 153.14 × 104.00; at 95% it renders **145.48 × 98.80** (the requested
  ~145 × 99).
- Placement still uses the ink centroid, but the vertical target is now the
  column centre **+ 3 px**. The top clamp is `Style.space(6)` (6 px).
- Harness geometry: art **145.48 × 98.80**, bbox top **7.60 px** below the
  panel top border, centroid **710.00,99.00** against target **710.00,99.00**
  (column centre 710.00,96.00 + nudge 3). All ink stays inside the 218 × 112
  column; column, field, Sort direction and the settings button are unchanged.
- Live-path geometry with the real `qs.Ui.KeyboardPanel` at 1280 × 720:
  surfaceWidth **1280**, contentWidth **835**, content column **803 × 88**,
  field **585**, column **218 × 112**, art **145.48 × 98.80**, art card y
  **7.60** logical. The pixel probe on the live card found the first ink row at
  **7.33 logical px** below the card's top border (>= 6).
- The three surface-width regression checks still report
  `field=585, column=218.00, cat=145.48x98.80, ok=true` at 1280/1920/2560.

### ITEM 3 — status label fits its longest string

Every service status value (measured at `Style.font.caption`; `N/N` uses the
worst-case 4-digit `9999/9999`). Only values starting `Syncing library` are
visible in this label:

| status string (before shortening) | width |
|---|---:|
| `Syncing library…` | 96 |
| `Syncing library · album lists…` | 180 |
| `Syncing library · album lists N/N…` | 240 |
| `Syncing library · matching…` | 162 |
| `Syncing library · playlists…` | 168 |
| `Syncing library · playlists N/N…` | 228 |
| `Syncing library · album pages N/N…` | 240 |
| `Syncing library · tracklists N/N…` | 234 |
| `Syncing library · done N/N…` | 198 |

Other service status values (never shown by this sync-only label, but
enumerated for completeness): `Importing browser session…` **156**,
`No browser session found — sign in to Bandcamp to see private items.` **408**,
`Library updated · N albums` **174**, `Sync failed: <message>` variable
(example 396), `Cleared imported session` **144**.

At the real harness panel size the available gap is
**601.00 − (455.84 + 8) = 137.16 px**. The longest old string, 240 px, would
elide badly, so the strings were trimmed at the source in `Service.qml`: the
headline `Syncing library…` is kept verbatim and the detail suffix is reduced
to a 0–100 % value. `Service.syncStatusText(done, total)` was the single source
of truth for these strings at v3.5.4.1; v3.5.6 keeps the headline and replaces
that formatter with `syncStatusText(percent)`, fed by the whole-sync percentage
below.

Changed strings before -> after:

| before | after |
|---|---|
| `Syncing library · album lists…` | `Syncing library…` |
| `Syncing library · album lists N/N…` | `Syncing library… P%` |
| `Syncing library · matching…` | `Syncing library…` |
| `Syncing library · playlists…` | `Syncing library…` |
| `Syncing library · playlists N/N…` | `Syncing library… P%` |
| `Syncing library · album pages N/N…` | `Syncing library… P%` |
| `Syncing library · tracklists N/N…` | `Syncing library… P%` |
| `Syncing library · done N/N…` | `Syncing library… 100%` |

After shortening, all **102** strings the label can show (base plus every
0–100 %) were measured:

| after string | width |
|---|---:|
| `Syncing library…` | 96 |
| `Syncing library… 0–9%` | 114 |
| `Syncing library… 10–99%` | 120 |
| `Syncing library… 100%` | 126 |

Layout:

- The label is now sized to the **full available gap**:
  `x = Sort direction right + 8 px`, `width = search field right − x`; it is
  right-aligned, remains an overlay, and still only appears for
  `Syncing library` statuses.
- Harness: rect **463.84,127.00,137.16 × 14**, field right **601.00**,
  Sort-direction right **455.84**, clearance exactly **8.00 px**.
- Live scratch shell: label width **180.28 px** (its theme font metrics are
  wider), longest string **126.00 px**, `truncated=false`.
- New check iterates all 102 strings: each measured width is <= the real label
  width, and the displayed longest string is not truncated.

### Changed checks (enumerated)

Replaced/renamed (phase 1):

- `v3.5.4: the cat mark is the bold shipped SVG trace…` -> `v3.5.4.1: the cat
  mark is the slim smoothed shipped SVG trace…`; implicit height 346 -> 345.
- `v3.5.4: every bold cat path…` -> `v3.5.4.1: every slim cat path…`; aspect
  508/346 -> 508/345.
- `v3.5.4: the bold mark is fitted inside the column…` -> `v3.5.4.1: the slim
  mark is fitted…`; aspect updated.
- `v3.5.4: the mark's ink centroid matches the cat-column centre on both axes`
  -> `v3.5.4.1: …matches the column centre plus the 3 px down-nudge`; same
  2 px tolerance.
- `v3.5.4: the mark's bbox sits fully inside…` -> `v3.5.4.1: …with all ink
  clear of the edges`; still asserts left/top/right/bottom inside.
- `v3.5.4: the bold mark still fills at least 90% of the column height` ->
  `v3.5.4.1: the slim mark renders at 95% of the previous fit (~145 x 99)`.
  This is a deliberate requirement change: 95% of the old fit is 88.2% of the
  column height, so the old 90% check would contradict the requested fit; the
  replacement asserts the exact 95% width and aspect instead.
- `v3.5.4: the ink centroid is measured from the bold asset…` -> `v3.5.4.1:
  …from the slim asset…`; constants updated.
- Script-side accent check name bold -> slim; its ink-pixel floor was
  recalibrated from **150** (solid bold silhouette) to **1,200** for this thin
  outline. The reference render at ~145 × 99 has ~1,864 non-transparent ink
  pixels (~988 alpha-weighted); the harness probe measures **1,333** ink
  pixels. The semantic requirements are unchanged: peak is exactly the theme
  accent, no pure white, none over accent.
- Script-side centroid probe target changed from column centre to column
  centre **+ 3 px**; same 3 px tolerance.
- Python test names/docstrings changed bold -> slim; assertions now use the
  smooth asset's byte hash, 508 × 345 root, and path lengths/hashes above.
  Test count remains 3.

Added:

- `v3.5.4.1: the rendered ink's top edge sits at least 6 px below the panel top
  border` (QML geometry).
- `v3.5.4.1: the label spans the full gap from Sort direction + 8 px to the
  field's right edge` (QML).
- `v3.5.4.1: every enumerated sync status fits the full label width at the real
  panel size` (QML, 102 strings).
- Script-side `PASS the rendered ink's top edge is at least 6 px below the
  panel top border` (pixel probe on the saved harness PNG).

No existing check was weakened or deleted silently; the one semantic change
(90% height coverage -> 95% of the previous fit) is the requested fit change.

### Results

- Python: **100 tests OK, 5 skipped**; with `OMATIME_LIVE=1`: **100 tests OK**
  (the 5 live fixtures run).
- QML: **592 checks**, `FAILS=0` in every phase (phase 1 **550**, relaunch 15,
  real-data 17, script-side **10**); `QML tests: OK` (`588 -> 592`, +3 QML,
  +1 script-side).
- Surface-width regression: all three pass with field **585**, column
  **218.00**, cat **145.48 × 98.80**, `ok=true`.
- Accent probe: `rect=656,10,141,94 accent=#cacccc inkPixels=1333
  exactAccentPixels=177 peak=#cacccc pureWhitePixels=0 overAccentPixels=0`.
- Centroid probe: `column=601,0,219,113 centroid=709.33,58.49
  target=710.50,59.50 nudge=3 error=-1.17,-1.01 inkWeight=992.4`.
- Harness top-edge probe: `topEdge=8 limit=6` (geometric bbox top 7.60).
- Live-path top-edge probe: `topEdge=11 physical / 7.33 logical limit=6`
  (card 1253 × 180 physical = 835 × 120 logical at 1.5×).
- Harness screenshots (full popup, real size): `/tmp/omatime-v3541-header.png`
  and `/tmp/omatime-v3541-syncing.png`, both **835 × 570**, `saved=true`,
  `Image.Ready`. The syncing shot uses the longest string,
  `Syncing library… 100%`.
- Live-path screenshots (real KeyboardPanel): `/tmp/omatime-v3541-live-normal.png`
  and `/tmp/omatime-v3541-live-syncing.png`, both **1253 × 180** physical
  (**835 × 120** logical). The cat/column geometry is identical in both; only
  the status label appears. The scratch live shell does not resolve its theme
  accent (`Color.accent` is undefined there), so the mark appears black in
  these two diagnostic captures; the harness accent probe above is the
  semantic check.

### Owner live check

1. `omarchy restart shell`, open the panel. The slim, smoothed cat is slightly
   smaller than the bold v3.5.4 mark and sits a few pixels lower; the ears are
   clearly clear of the top border.
2. Confirm the ink looks centred in the right-hand column with the 3 px
   downward nudge. Clicking the whole column still opens Settings.
3. Trigger a refresh. The label shows `Syncing library…` and then short
   percentage updates such as `Syncing library… 57%`; it is right-aligned to
   the search field, starts 8 px after Sort direction, and never elides.
4. Compare `/tmp/omatime-v3541-header.png` and
   `/tmp/omatime-v3541-syncing.png`: identical layout, only the status label
   differs. Compare the two live-path captures for the same geometry with the
   real KeyboardPanel.

## v3.5.5 queue persistence — Up Next survives a shell restart (2026-10-28)

### Decision and why it reverses v3.4

v3.4 deliberately made the user queue session-only: it started empty on every
shell launch and disappeared with the session. That assumption is wrong on
Omarchy. The shell is restarted for reasons unrelated to music — switching
themes, applying tweaks, updating the shell — and a queue built up while
listening must survive those restarts. v3.5.5 therefore reverses the v3.4
policy for the Up Next list.

The reversal is deliberately narrow:

- **Persist only the user queue — the Up Next list.** Playback context,
  now-playing, position, resume point and queue history stay session-only. On
  startup the panel restores the queue; playback itself starts stopped, exactly
  as it does today.
- **Store the minimum identity needed to re-resolve each entry** against
  `library.json`. Entries are never stored as tracks: no stream URL, no cover
  URL, no cookie, no credential-bearing value reaches disk. At restore every
  entry is re-resolved against the loaded library and streamability is
  re-derived exactly as when queueing by hand. Duplicates remain allowed and
  order is preserved.
- **Save on every mutation.** Add to Queue, Play Next, remove, Clear,
  consumption (a queued item starting playback leaves `pending`) and Previous
  (which moves items back into `pending`) all rewrite the persisted copy. There
  is no user reorder feature in the queue, so there is no separate reorder
  hook; the only operation that reorders pending items is Previous, and it is
  persisted.
- **Restore revalidates.** An entry whose track is gone from the library, or
  is no longer streamable, is dropped silently. A missing or corrupt file
  restores as an empty queue, never an error and never a broken panel.
- **Unchanged.** Clear empties both the live queue and the persisted copy.
  Starting a new playback context clears the queue (the v3.4 rule) and its
  persisted copy with it. Play Next ordering and the Up Next frame are
  untouched.

### Scope guard

The queue is the v3.4 immutable `{ pending, current, resumeIndex, history }`
object whose `pending` items are ordinary library tracks. Persistence only
needed a pure identity projection and a resolver, both added to `UserQueue.js`;
no playback refactor was required and no playback code changed shape. The guard
did not trigger.

### What changed

- **`UserQueue.js`** gains pure, Qt-free persistence helpers:
  `identityOf(track)`, `serialize(state)`, `resolveEntry(entry, tracks)`,
  `restorePending(entries, tracks)`. They are exercised by the same Node-under-
  unittest path as the rest of the model.
- **The persisted record** is a small JSON object at
  `~/.local/state/omatimeatbandcamp/queue.json`, next to `ui.json`:

  ```json
  {"version":1,"pending":[
    {"uid":"<album uid>#<index>","subsonicId":"<id or empty>",
     "bandcampId":"<id or empty>","title":"<title>",
     "artist":"<artist>","album":"<album>"}
  ]}
  ```

  `uid` is the primary lookup. `subsonicId`/`bandcampId`, when present, are
  stable ids that survive an album re-order. `title`/`artist`/`album` stop a
  stale `uid` pointing at a different track and let a rebuilt library still
  re-resolve the same track. Nothing else from the track is stored.
- **`Service.qml`** adds `queue.json` as a `FileView` with the same state
  directory and `blockLoading`/`atomicWrites` pattern as `ui.json`, plus
  synchronous writes and reads (`blockWrites`, `blockAllReads`). Writes are
  synchronous so a mutation followed immediately by a shell restart cannot
  race and resurrect an item; reads are synchronous so restore always sees the
  file rather than a cached previous copy. `saveQueue()` writes
  `{version, pending: UserQueue.serialize(userQueueState)}` after every queue
  mutation. `restoreQueue()` parses and revalidates; `maybeRestoreQueue()`
  runs once, when the library has first loaded, and never again on later
  library reloads.
- **Restore is stopped.** `restoreQueue()` sets
  `{ pending: restored, current: null, resumeIndex: -1, history: [] }`; it
  never starts mpv and never restores a now-playing row.
- **Restored entries are live library objects.** They are looked up in
  `collection` and `playlists`, so a restored row is the same object the UI
  would have queued by hand and carries re-derived `streamable`.

### Tests changed or added

No existing product assertion was weakened or removed. One relaunch assertion
had to be replaced because it asserted the reversed v3.4 policy:

- `[relaunch] session-only user queue starts empty on a fresh service` →
  `[relaunch] v3.5.5: the persisted Up Next queue is restored, stopped`. Reason:
  the queue is no longer session-only; the new check still proves the relaunch
  is a fresh service by requiring `currentUserTrack === null` and
  `isPlaying === false`, while asserting the two persisted fixture tracks came
  back in order.

The harness `resetUserQueueChecks()` helper (test setup, not an assertion) now
also calls `svc.saveQueue()` after clearing in memory, so the directly-mutated
model and the persisted copy stay in step between test blocks.

New model tests (Python, 5; `UserQueue.js` run under Node):

- `test_persisted_queue_round_trips_without_urls_or_credentials` — save/load
  round-trip; serialized text contains no stream URL, no `streamUrl`, no
  credential, no cover id; restored entries are the live library tracks.
- `test_duplicates_and_order_survive_a_save_load_round_trip` — `A,B,A,B,A`
  returns identical, duplicates intact.
- `test_restore_drops_an_entry_whose_track_is_gone` — deleted album/track
  entry dropped silently, neighbours kept in order.
- `test_restore_drops_an_entry_that_is_no_longer_streamable` — the
  now-unstreamable entry is dropped, the streamable one stays.
- `test_restore_rejects_a_stale_uid_and_keeps_metadata_matches` — a recycled
  `uid` with different metadata is not restored; the same track under a new
  `uid` still resolves by exact metadata.

New QML checks (phase 1, 14; all named `v3.5.5`):

- a clean slate starts with an empty Up Next queue (setup guard);
- `the Up Next queue survives a save/load round-trip`;
- `a restored queue starts stopped (playback is not restored)`;
- `duplicates and their order survive a save/load round-trip`;
- `starting a queued track consumes it from Up Next`;
- `consumption persists across a simulated restart`;
- `Clear persists across a simulated restart`;
- `a new playback context clears the persisted queue`;
- `restore silently drops an entry whose track is gone`;
- `restore silently drops an entry that is no longer streamable`;
- `a corrupt persisted queue restores as empty and leaves the panel working`;
- `a missing persisted queue restores as empty (no error)`;
- `an on-disk corrupt queue.json restores as empty, panel fine` (the harness
  writes a real corrupt file, then the service reloads it from disk);
- `the queue left for the relaunch phase is the fixture album's first two
  tracks`.

New script-side check (1): phase 1's `queue.json` exists, is valid JSON, has
only the top-level `version`/`pending` keys, has exactly the six identity keys
per entry, contains no `://`/`token=`/credential-bearing value, and holds the
two expected fixture titles. The file itself is not echoed, so a regression
could not print a URL or credential.

### Results

- Baseline (fresh session, before editing), matching the quoted figures:
  Python **100 tests OK, 5 skipped**; live fixtures **5 OK**; QML **592**
  checks, `FAILS=0` (phase 1 550 + relaunch 15 + real-data 17 + script-side 10).
- Python: **105 tests OK, 5 skipped** (100 + 5 persistence model tests).
- Live fixtures (`OMATIME_LIVE=1`): **5 tests OK** (unchanged; the full
  discovery run is 105 with the 5 live checks included when enabled).
- QML: **607 checks**, `FAILS=0` in every phase (phase 1 **564**, relaunch 15,
  real-data 17, script-side **11**); `QML tests: OK` (`592 → 607`, +14 QML,
  +1 script-side).
- `omarchy plugin validate .`: exit 0.
- `qmllint -s Service.qml` and `qmllint -s BcButton.qml`: exit 0.
  `qmllint` on `Panel.qml` did not finish in this environment (pre-existing,
  the file is unchanged by v3.5.5); no new warning was reported before it was
  stopped.
- Credential files were not opened (paths/modes only). No stream URL, cover
  URL or credential value was printed or committed. `--load-scripts=no` is
  untouched and the MPRIS whitelist is untouched.

### Deviations / owner-visible decisions

- **Writes and reads are synchronous** for `queue.json` only. This is a
  deliberate durability choice for the shell-restart case; the queue is tiny
  and mutations are user-driven, so the blocking cost is negligible.
- **Restore does not rewrite the file.** Revalidation drops entries in memory;
  the cleaned list is written on the next mutation. This avoids rewriting or
  truncating the file if the library is temporarily incomplete at startup.
- **Restore happens once per service.** A later library reload does not replace
  a queue the user has since changed.
- **No user queue reorder exists**, so `queue.json` has no reorder hook; the
  Previous operation's move back into `pending` is persisted.
- **Queue history and the resume point are not persisted.** A restart with a
  restored queue has no Previous history and no context to resume when the
  queue drains; Next from the stopped state plays the restored head, and the
  context underneath starts empty.

### Owner live check

1. Open the panel, right-click two or three tracks and choose Add to Queue (or
   Play Next), then `omarchy restart shell`.
2. Open the panel again. Up Next shows the same tracks in the same order,
   including duplicates, and playback is stopped (no now-playing row is
   restored).
3. Press Play/Next. The restored queue head plays; check that it disappeared
   from Up Next, then restart the shell again and confirm it does not come back.
4. Press Clear, restart, and confirm Up Next is empty. Then queue something,
   start a track in a different album, restart, and confirm the queue is still
   empty.

## v3.5.6 whole-sync percentage (2026-10-29)

### Baseline (fresh session, before editing)

- Branch/commit: `v2` @ `31ecd71`.
- Python: **105 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK** (`OMATIME_LIVE=1`).
- QML: **607 checks**, `FAILS=0` (phase 1 **564**, relaunch 15, real-data 17,
  script-side 11); `QML tests: OK`.
- These match the quoted baseline exactly; the stop-if-different guard did not
  trigger.

### Problem and decision

v3.5.4.1 made every sync string truthful at the *phase* scale: the front
phases had no denominator, so the label showed the bare `Syncing library…`
headline, and only the counted tail phases showed `P%`. On a real sync the
uncounted front (album lists, matching) is most of the wall clock, so the
number appeared briefly at the end and was absent when the owner looked.

v3.5.6 composes **one overall percentage for the whole sync** in the Service
layer, from the `stage/done/total` events the backend already emits. The label
format, placement, visibility rule and no-layout-shift behaviour are unchanged.
This trades the old per-phase percentages (truthful but mostly invisible) for a
number that is always present and never moves backwards. It does not invent
progress inside a phase that has no denominator: such a phase holds at its band
floor.

### Phase map (in order)

The backend prints JSON progress lines `{stage, done, total}`. The real-library
sizes below come from the cached 688-album / 33-playlist library and
`spike/SUBSONIC-REPORT.md`.

| # | stage | events the backend emits | real-library size | role |
|---|---|---|---:|---|
| 0 | *(browser import)* | none (status `Importing browser session…`, not a sync label) | — | precedes the sync; outside the percentage |
| 1 | `album lists` | start `0/0`; end `N/N`, N = web feed + Subsonic list | 645 + 687 = **1332** | no intermediate denominator; holds, then reaches the band top at the end |
| 2 | `matching` | start `0/0` only; next event is the playlists start | **688** merged albums | uncounted; holds at its floor |
| 3 | `playlists` | start `0/0`; then `i/33` for i = 0…32; no final `33/33` | **33** playlists | counted; last event is `(N-1)/N` |
| 4 | `album pages` | `i/N` before each page; no final `N/N` | **1** pre-order/web-only target | counted; `0/1` is the only real event here |
| 5 | `tracklists` | start `0/N`; then every `SAVE_EVERY` (100) albums; no final `N/N` | **608** fetched in the cold real sync | counted; the longest tail phase |
| 6 | `done` | `N/N` (688/688) | **688** | actual completion; the only event allowed to print 100% |

`matching` has no completion count, and `tracklists` previously had no start
event. The other phases already announced their start. Backend change required
for the map to be exact (enumerated here, nothing else changed):

- `backend/library.py`: one added `_checkpoint("tracklists", 0, total,
  progress)` immediately before the worker pool when `total > 0`. Without it
  the first tracklists event is after 100 albums, leaving the overall number in
  the previous band for that interval. No event shape/field changed; no event
  was removed or reordered.

### Weights and derivation

Weights are the measured cold-sync timing shares on the real library
(`spike/SUBSONIC-REPORT.md`: 93.6 s total) rounded to whole points. Cold timing
is used, not the latest incremental sync, so the bands also cover a first/deep
sync. The item counts in the phase map corroborate the same order of work.

| stage | band | weight | cold timing | share |
|---|---:|---:|---:|---:|
| `album lists` | 0 → 36 | 36 | 33.63 s | 35.9% |
| `matching` | 36 → 53 | 17 | 15.76 s | 16.8% |
| `playlists` | 53 → 66 | 13 | 12.15 s | 13.0% |
| `album pages` | 66 → 67 | 1 | 0.79 s (remainder) | 0.8% |
| `tracklists` | 67 → 100 | 33 | 31.27 s | 33.4% |
| `done` | 100 | — | completion marker | — |

The weights sum to **100**. A counted phase interpolates
`floor + floor((ceiling − floor) × done / total)` inside its band (ratio
clamped to 0…1). A phase with `total <= 0` or `done <= 0` returns its floor.
Because an uncounted phase never consumes its reserved weight, the number holds
there and resumes at the next phase's floor; that jump is deliberate and is not
invented progress.

### Composition and invariants

`Service.qml` now owns the whole calculation, next to the label text:

- `syncPhaseBand(stage)` — the table above.
- `syncPercentFor(stage, done, total)` — pure band interpolation.
- `advanceSyncProgress(stage, done, total)` — advances the single
  `syncPercent`, clamps it to `max(previous, next)`, and writes the label
  string.
- `beginSyncProgress()` — resets to 0 only when a new sync starts.
- `syncStatusText(percent)` — the only formatter: `Syncing library… P%`.

Invariants:

1. **Monotonic non-decreasing for the whole sync.** A revised denominator, a
   late event or a phase change can never move the number backwards.
2. **100 only at actual completion.** Every non-`done` result is capped at 99,
   including a tracklists checkpoint where `done == total`; only the backend's
   explicit `done` stage prints 100%.
3. **A percentage whenever a band is active.** `startSync()` enters at
   `Syncing library… 0%`, so after the opening instant every sync state is
   numeric. The bare headline remains a possible string only at the opening
   instant/manual setup.
4. **Everything else unchanged.** The string format, the label's position
   (Sort direction + 8 px to the search field's right edge), its
   `Syncing library` visibility rule, its overlay/no-layout-shift behaviour,
   and `Panel.qml` are untouched.

Label budget remains pre-proven: the new string set is the headline plus every
0–100% value (102 strings). Measured at the label font, widths are **96 px**
(headline), **114 px** (0–9%), **120 px** (10–99%), **126 px** (100%) against
the real **137.16 px** gap. The v3.5.4.1 every-string-fits check now enumerates
the new formatter and stays green (`count=102`, `max=126.00`,
`labelWidth=137.16`).

### Checks changed or added

- **Extended** `v3.5.4.1: every enumerated sync status fits the full label width
  at the real panel size`: it now builds the set through the new
  `syncStatusText(percent)` formatter (headline + 0–100), still 102 strings.
  Reason: the formatter is now percent-first; the budget and assertions are
  unchanged.
- **Added** `v3.5.6: the label shows a percentage during the front album-list
  phase`. Reason: the front phase used to show only the bare headline.
- **Added** `v3.5.6: the whole scripted phase sequence never moves the overall
  percent backwards`. Reason: end-to-end monotonicity over every phase in
  order.
- **Added** `v3.5.6: a revised denominator never moves the percent backwards
  (304/608 = 83%, then 200/800 stays 83%)`. Reason: proves the clamp, not just
  a naturally increasing script.
- **Added** `v3.5.6: an uncounted phase holds at its band floor (matching stays
  at 36%)`. Reason: no invented progress.
- **Added** `v3.5.6: a counted phase interpolates inside its band (album lists
  666/1332 = 18%, tracklists 100/608 = 72%, 304/608 = 83%)`. Reason: proves
  N/total inside the band.
- **Added** `v3.5.6: 100% appears only at the backend's done event`. Reason:
  the 99 cap plus the real completion event.
- **Added** `v3.5.6: the label hides at completion per the existing rule`.
  Reason: completion still uses the existing `Library updated` status and
  visibility rule; no new hide path.

No existing check was weakened or deleted. The scripted sequence uses the
backend's real event shapes (last playlist/page event `(N-1)/N`, tracklists
start `0/N`, then every 100) plus the explicit revised-denominator event.

### Results

- Python: **105 tests OK, 5 skipped** (backend change adds no test; the existing
  count is unchanged).
- Live fixtures (`OMATIME_LIVE=1`): **5 tests OK**.
- QML: **614 checks**, `FAILS=0` in every phase (phase 1 **571**, relaunch 15,
  real-data 17, script-side 11); `QML tests: OK` (`607 → 614`, +7 QML checks).
- Scripted sequence logged:
  `album lists 0/0=0`, `666/1332=18`, `1332/1332=36`,
  `matching 0/0=36`, `playlists 0/0=53`, `16/33=59`, `32/33=65`,
  `album pages 0/1=66`, `tracklists 0/608=67`, `100/608=72`,
  `304/608=83`, revised `200/800=83` (clamped), `600/608=99`,
  `done 688/688=100`.
- `omarchy plugin validate .`: exit 0.
- Credential files were not opened (paths/modes only). No stream URL, cover URL
  or credential value was printed or committed. `--load-scripts=no` is
  untouched; the MPRIS whitelist is untouched.

### Owner live check

1. Trigger Refresh. The label should read `Syncing library… 0%` immediately,
   then step through the bands; it never returns to the bare headline during
   the sync.
2. Confirm it never goes backwards and that the only `100%` is the last sync
   frame, after which the label disappears and `Library updated · N albums`
   (or the existing failure text) takes over.
3. Confirm the label still sits in the Albums/Playlists/Sort row, right-aligned
   to the search field, starts 8 px after Sort direction, and opens no gap or
   shift when it appears.

## v3.5.6.1 100% label clip fix (2026-10-29)

### Baseline (fresh session, before editing)

- Branch/commit: `v2` @ `69fa1a0`.
- Python: **105 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK** (`OMATIME_LIVE=1`).
- QML: **614 checks**, `FAILS=0` (phase 1 571, relaunch 15, real-data 17,
  script-side 11); `QML tests: OK`.
- These matched the quoted baseline exactly; the stop-if-different guard did
  not trigger.

### Reproduction with the real theme (live path)

The live-path probe loaded the owner's real theme from `$HOME`: the real
`Color`/`Style` singletons (`accent=#9a724a`, `foreground=#afa89c`,
`caption=10`, `spacingScale=1`) and the real `Bar.qml` (not a fake bar) plus
the real `qs.Ui.KeyboardPanel`. The service was a deterministic stub only so
the label could be driven straight to `Syncing library… 100%` without racing
a real sync. The toolbar used the owner's real library size: **688 albums /
33 playlists**, sort **Recently added**, descending.

At 100%, with the label still at caption size:

| measurement | live path | fixture |
|---|---:|---:|
| label rect | `462.22, 71.00, 122.78 × 14.00` | `463.84, 127.00, 137.16 × 14` |
| label gap (width) | **122.78** | **137.16** |
| Sort-direction right | 454.22 | 455.84 |
| search-field right | 585.00 | 601.00 |
| `Syncing library… 100%` in the live font | **126.00** | — |
| `Syncing library… 100%` in the fixture font | — | **126.00** |
| label `truncated` | **true** | false |

The hypothesis that the live theme font draws the string wider is **refuted**:
both fonts measure **126.00 px**. The defect is real, but it is a **gap-width**
failure, not a string-width failure. The real library counts widen the
Albums/Playlists buttons under the real theme, moving Sort direction right and
shrinking the label from the fixture's 137.16 px to **122.78 px** — 3.22 px
less than the 126 px worst string. That is why 100% elided while the shorter
single/double-digit strings still fitted.

### Layer chosen

Measured options against the live gap of 122.78 px:

| option | result | 100% margin |
|---|---|---:|
| a. drop the space before `%` | string 126.00 → 120.00 | 2.78 px (below 6) |
| b. clearance 8 px → 4 px | gap 122.78 → 126.78 | 0.78 px (below 6) |
| **c. caption 10 → 9 px** | worst string 126.00 → **114.20** | **8.58 px** |

Because neither a nor b alone reached 6 px, the formatter was left untouched
(no visible-text change) and the label font was reduced by one pixel:
`font.pixelSize: Math.max(1, Style.font.caption - 1)`. Clearance stays at
8 px, so the label still starts 8 px after Sort direction and never overlaps.
The percent composition, monotonicity, 99-cap and hide-at-completion
invariants are unchanged. After the fix: label rect
`462.22, 71.00, 122.78 × 14.00`, worst live-font string **114.20 px**, margin
**8.58 px**.

### Hardened check

New live-path launch in `tests/qml/run.sh` (real `$HOME` theme/font, real
`Bar.qml`, real `qs.Ui.KeyboardPanel`) runs `tests/qml/live_theme.qml` and
enumerates all **102** strings. The deterministic stub uses the real library
counts and Recently-added sort that exposed the clip.

Changed checks:

- **Added** `v3.5.6.1: every enumerated sync status fits the live-path label
  with the real theme font (100% clip incident)`. Reason: the existing
  every-string check used the fixture font/gap and could not see the live
  real-library gap. It asserts every string has rendered width <= label width
  and `truncated == false` in the live path.
- **Added** `v3.5.6.1: the live-path 100% capture shows the full string, not
  truncated`. Reason: saves and checks the real 100% frame, not just the
  measurement.
- **Unchanged**: `v3.5.4.1: every enumerated sync status fits the full label
  width at the real panel size` still runs with the fixture font. All v3.5.6
  percent/invariant checks remain as written. No check was weakened or removed.

Against `69fa1a0` the new live-path check fails exactly as the owner reported:
`labelWidth=122.78`, `max=126.00`, `margin=-3.22`, `truncated=true`. After the
fix it passes with `max=114.20`, `margin=8.58`, `truncated=false`.

### Results

- Python: **105 tests OK, 5 skipped**.
- Live fixtures: **5 tests OK** (`OMATIME_LIVE=1`).
- QML: **616 checks**, `FAILS=0` (phase 1 571, relaunch 15, real-data 17,
  script-side 11, live-theme 2); `QML tests: OK` (`614 → 616`, +2 live-path
  checks).
- Live-path capture of the 100% state:
  `/tmp/omatime-v3561-live-100.png`, **1253 × 855** physical (835 × 570
  logical at 1.5×), showing the complete `Syncing library… 100%` string.
- Credential files were not opened (paths/modes only). No stream URL, cover
  URL or credential value was printed or committed. `--load-scripts=no` is
  untouched.

### Owner live check

1. On the real panel with 688 albums / 33 playlists, trigger Refresh. The
   label is one pixel smaller than before and reads single/double-digit
   percentages normally.
2. At completion it must show the whole `Syncing library… 100%` for its final
   frame, then hide as before; no `10`-only frame.
3. Confirm the label still starts 8 px after Sort direction, stays right-aligned
   to the search field, and does not overlap or shift any control.

## Security audit — HEAD @ 88d4175 (2026-10-29, read-only)

Scope: HEAD and all reachable refs, plus local reflog/unreachable objects, and the
working tree. The tree was not edited during the audit except for this section.
No credential file was opened; `credentials.toml`, `cookies.txt` and the cookie
backup were inspected by path/mode/size only.

Baseline confirmed first: Python **105 OK, 5 skipped**; live fixtures **5 OK**;
QML **616 checks, FAILS=0**.

Method: gitleaks 8.30.1 (official release) over full git history and the working
tree; a redacted targeted scan of every reachable commit, reflog commit and
unreachable commit/blob for the requested identities, paths, hostnames, IP
shapes, Subsonic URL parameters, cookie names, auth/token/password assignments,
private-key markers and Anthropic key shapes; `git ls-files` and historical path
inventory; fixture/data inventory; and a manual review of the subprocess,
network, cookie, MPRIS, file-permission, IPC/JSON and error-path surfaces.

### Findings

1. **Medium — Bandcamp cookies can be sent to a non-Bandcamp `userUrl`.**
   `backend/bandcamp.py:40-47,98-99` attaches the Cookie header to whatever URL
   it fetches, while `Service.qml:447-449` passes the user-configured
   `settings.userUrl` straight through. The legacy `fetch.py:42-48` has the same
   shape. If the setting is a typo or a hostile host, the imported Bandcamp
   session can go off-domain. Redacted evidence: cookie jar contains an
   `identity` cookie; no cookie value was read or printed.
   *Remediation:* require `https` and a `bandcamp.com` host (or explicit
   allow-list) before attaching cookies; reject other URLs.

2. **Medium — browser cookie database copied through `tempfile.mktemp`.**
   `cookies.py:66-70` copies the whole Chromium/Firefox cookie database to a
   `/tmp` path chosen by the deprecated, race-prone `mktemp`, with no explicit
   `0600` mode. Only Bandcamp rows are later selected, but the temporary copy is
   the full browser jar. Redacted evidence: full-database copy, local temp path.
   *Remediation:* use `mkstemp` inside the `0700` cache directory, `chmod 0600`
   immediately, and unlink in `finally`.

3. **Low — Subsonic credential permissions are not enforced.**
   `backend/subsonic.py:49-57` opens `~/.config/omatimeatbandcamp/credentials.toml`
   without checking its mode. Observed: credentials file `0600`, but its parent
   directory is `0755`, while the spec calls for directory `0700` and refusal on
   looser permissions. No value was read.
   *Remediation:* `stat` the directory/file and refuse if group/other bits are
   set; create and repair the directory as `0700`.

4. **Low — state and MPRIS files are `0644` in a `0755` state directory.**
   `Service.qml:204-229,1318-1339` writes `ui.json`, `queue.json` and
   `mpris-state.json`; observed state directory `0755`, files `0644`. Contents
   are identity-only (sort/filter/queue and title/artist/album), with no stream
   URL or credential. This is local metadata exposure, not credential exposure.
   *Remediation:* create the state directory `0700` and write state files `0600`.

5. **Low — predictable mpv log path in `/tmp`, default mode `0644`.**
   `mpvctl.py:69-71` opens `/tmp/omatime-mpv-<uid>.log` without `0600` or
   `O_NOFOLLOW`; observed log `0644` and empty, IPC socket `0600`. If mpv ever
   writes a load URL to that log, another local user can read it; a pre-created
   symlink is also a local race.
   *Remediation:* keep the log under the `0700` cache directory, open it `0600`
   with `O_NOFOLLOW`, and leave the socket private.

6. **Low — error paths can echo public collection/album URLs.**
   `fetch.py:54`, `backend/bandcamp.py:52-55`, `backend/library.py:315-317` and
   `Service.qml:495-505` can put a Bandcamp URL into stderr, the sync log or the
   panel. These URLs can identify the owner's public collection/profile but do
   not contain Subsonic `u/t/s` or session-cookie values. The current
   `library/sync.log` scan found no auth parameters, emails, home paths, IPs or
   URLs.
   *Remediation:* redact to host/path or omit the URL in errors; parse and
   whitelist backend stderr before showing it in the panel.

7. **Low — the log redaction filter does not cover traceback text.**
   `backend/__main__.py:33-36` rewrites `record.msg`, while
   `backend/library.py:158-159` uses `log.exception`; `record.exc_text` can carry
   an unredacted exception string into `sync.log`. Subsonic network exceptions
   are already redacted and the current log is clean, so this is a defense gap.
   *Remediation:* redact the formatted exception text too, or set `exc_info` to a
   sanitized exception before logging.

8. **Info — legacy `t.streamUrl` branch would put a URL in process argv.**
   `Service.qml:933-935` can call `mpvctl.py load <URL>`; `mpvctl.py:202-256`
   then accepts the URL from argv. Current `LibraryModel.js:94-110` does not
   populate `streamUrl`, and Subsonic playback uses the in-process
   `backend play` path, so no credential URL reaches argv today.
   *Remediation:* remove or guard the branch; load any URL through IPC/in-process.

9. **Info — `.gitignore` covers `*.bak-*` but not plain `*.bak`.**
   `.gitignore:13` is `*.bak-*`; `git check-ignore foo.bak` reports not ignored.
   No `.bak` file is tracked or present in the repo tree.
   *Remediation:* add `*.bak`.

10. **Info — owner identity/local host metadata is in docs and commit metadata.**
    `docs/omatimeatbandcamp-v2-spec.md:3-4,531` and
    `docs/omatimeatbandcamp-v3-spec.md:4` contain the owner's first name and
    `<owner-handle>`; all 40 commit objects use local author/committer identity
    `<local-username>@<local-hostname>` rather than a GitHub noreply address.
    `spike/SUBSONIC-REPORT.md:118` contains one real playlist name and ID;
    `V2-NOTES.md:366` contains the hostname. No secret value is present.
    *Remediation:* for public publication, use a noreply commit identity and
    scrub owner/host/playlist identifiers from docs and reports.

11. **Info — tracked fixtures contain a little real public library data.**
    `tests/qml/fixtures/library.json:11,16,17,133,138,217` has 3 of 13 album
    titles matching the owner's cache, one real public Bandcamp album URL and
    two real Bandcamp album IDs. `tests/fixtures/first_impressions_page.html`
    matches a real album ID/title; `spike/phase1_results.py:28` hardcodes the
    same public album URL; `spike/SUBSONIC-REPORT.md` records real library
    measurements and names. No stream URL, cover URL, cookie or credential is
    present in these files.
    *Remediation:* treat as public album data; replace with synthetic values if
    collection anonymity matters.

12. **Info — gitleaks false positive in a test fixture.**
    `tests/test_library.py:16` (`SECRET_S`) is an 8-character dummy test value
    used to prove the cache write guard. It is not a live secret.
    *Remediation:* add a `.gitleaksignore` entry or rename the placeholder.

### Secret and identity scan result

- **No live secret found** in HEAD or history: no cookie value, Subsonic
  `u/t/s/p` value, Authorization value, API key/token/password literal,
  private-key marker or `sk-ant-` key.
- gitleaks: **1 finding**, the dummy test value above; working tree and full
  history agree.
- Historical `cookies.py`: **no commit in the current object database contains
  `cookies.py`** (40 commits considered, including 3 unreachable/reflog
  commits). The old incident commit `12471a4` is absent (`git cat-file` says
  missing). The ignored working-tree loader has no hardcoded cookie values.
- `git ls-files`: only the synthetic fixture `tests/qml/fixtures/library.json`
  matches a data-file name; no `credentials.toml`, `cookies.txt`, `*.bak`,
  real `library.json`, cache or state file is tracked.
- Historical paths: 67 unique paths ever tracked; the only sensitive-looking
  one is the tracked fixture library. No historical `cookies.py` path.
- Requested patterns: no requested hostname, home-path literal, LAN/Tailscale IP
  literal, `Authorization` literal, Subsonic URL credential value, private-key
  marker or Anthropic key was found. The targeted identity failures are only
  the documented owner handle/local host metadata and the public fixture data
  above.

### Verified controls

- Subprocesses use argument lists, never `shell=True`; no `eval`, `exec` or
  `pickle` on untrusted data. mpv receives metadata through IPC
  (`--load-scripts=no` remains at `mpvctl.py:63`), not through a shell.
- TLS uses `urllib`/`requests` defaults; no `verify=False`, custom unverified
  SSL context, or disabled hostname check.
- MPRIS reads only the explicit `STATE_KEYS` whitelist
  (`backend/mpris.py:37-38,64-84`), never `path`/`url`; `mpris:artUrl` is built
  only from a local `file://` file. Current state file has no URL/credential
  keys.
- IPC methods take ids/numbers only and resolve them against the library;
  `openExternal` accepts only `https`. JSON parsing is `json.loads`/`JSON.parse`,
  with malformed input ignored.
- Credential/cache files observed with `ls -l` only: credentials `0600`,
  cookies `0600`, cookie backup `0600`, cache library files `0600`; cache
  directory `0700`. State directory/file permissions are the low finding above.

### Verdicts

1. **Is HEAD safe to publish as-is? YES for secret safety** — no credential,
   session-cookie, token, private-key or credential-bearing URL is present in the
   tracked tree. It is **not anonymity-clean**: it publishes the owner handle,
   local host metadata and some real public album/playlist references noted
   above.
2. **Is HISTORY safe to publish as-is? YES for secret safety** — no credential
   material exists in reachable refs or the local unreachable/reflog objects,
   and the old hardcoded-cookie commit is absent. The same low-sensitivity
   identity/privacy caveat applies to commit metadata and docs.

## Audit fixes — findings 1-9, 12 + doc scrub (2026-10-29)

Work order: the security-audit findings above. Baseline at `d3386a2` was
confirmed before editing: Python **105 tests OK, 5 skipped**; live fixtures
**5 OK**; QML **616 checks, FAILS=0**. The dummy-only history rewrite for
finding 12 changes that audit commit's hash to `14cf791`; its tree is identical.
Nothing was weakened; every change below adds a regression check where the
behaviour is testable.

### Finding-to-fix map

1. **Medium — cookies only go to Bandcamp.**
   `backend/bandcamp.py` now has `cookie_allowed()`: the `Cookie` header is
   attached only for `https` URLs whose host is exactly `bandcamp.com` or ends
   in `.bandcamp.com`. Lookalikes (`bandcamp.com.evil.example`), plain `http`,
   userinfo tricks and non-Bandcamp hosts get no cookie. `Service.qml` has the
   matching `isBandcampUrl()` gate and refuses a non-conforming `userUrl`
   before starting a sync. The legacy `fetch.py` was dead code (no live caller;
   only prose/spike references), so it was deleted rather than patched.
   *Checks:* `tests/test_audit_fixes.py::CookieHostGate` (non-Bandcamp/http get
   no header; `bandcamp.com` and subdomains do), plus three QML checks that an
   http URL and a lookalike host are refused and the helper accepts only the
   real host/suffix.

2. **Medium — browser cookie copy.**
   `cookies.py::private_copy()` uses `tempfile.mkstemp()` inside the `0700`
   cache directory, `fchmod`s the descriptor to `0600`, copies with
   `shutil.copyfile` (so it cannot inherit a looser browser mode), and unlinks
   the copy on any failure. Both readers already unlink in `finally`.
   *Checks:* `CookieTempCopy` verifies the copy's location, `0600`/`0700`
   modes, contents, and that the cache directory is empty after both a direct
   copy and a reader call.

3. **Low — Subsonic credential permissions.**
   `backend/subsonic.py::load_credentials()` stats the credential file and its
   plugin-owned directory before opening either. Group/other bits are tightened
   to `0600`/`0700`; if the path cannot be tightened the call fails with an
   error naming the exact `chmod` command. No credential value is read on the
   failure path.
   *Checks:* `CredentialPermissions` covers the repair case and the refusal
   message (`chmod 700 <dir>`).

4. **Low — state/MPRIS permissions.**
   `Service.qml` creates the state directory with `install -d -m 700` (which
   also tightens an existing directory) and each `FileView` runs `chmod 600`
   after saving `ui.json`, `queue.json` and `mpris-state.json`. The MPRIS cache
   directory is created the same way.
   *Checks:* four QML harness checks read the real modes on disk after phase 1:
   state dir `700`, `ui.json`/`queue.json`/`mpris-state.json` `600`.

5. **Low — mpv log.**
   `mpvctl.py` writes the log as `~/.cache/omatimeatbandcamp/mpv-<uid>.log`
   instead of `/tmp`. `_open_log()` creates/repairs the cache directory at
   `0700`, opens with `O_NOFOLLOW` where available and mode `0600`, then
   `fchmod`s the descriptor; the parent closes its copy after spawn.
   *Checks:* `MpvLog` verifies the location, `0600` file/`0700` directory, and
   that a pre-created symlink is refused without touching its target.

6. **Low — public URLs in error paths.**
   `backend/bandcamp.py` reduces HTTP/network error URLs to
   scheme+host+path with `safe_url()` and scrubs embedded URLs in exception
   text with `scrub_urls()`; `backend/library.py` logs the same safe form; and
   `Service.qml::redactUrls()` strips userinfo, query and fragment from any
   backend error shown in the panel. `fetch.py`'s copy of this path is gone
   with the file.
   *Checks:* `ErrorUrlRedaction` covers the HTTP-error and embedded-URL cases;
   one QML check covers the panel-side redaction.

7. **Low — traceback redaction.**
   `backend/__main__.py::_Redact.filter()` now formats `record.exc_info` into
   `exc_text` and runs the existing redactor over it (and over `stack_info`),
   so `log.exception()` cannot carry an unredacted exception string into
   `sync.log`.
   *Checks:* `TracebackRedaction` raises an exception containing a
   credential-shaped URL and asserts the formatted traceback shows the
   placeholder, not the value.

8. **Info — legacy `t.streamUrl` argv branch.**
   Verified: `LibraryModel.adaptTrack()` does not populate `streamUrl`; only the
   QML first-track regression uses a synthetic local tone. Removing the branch
   cascades into that check, so the branch is **guarded** instead of removed:
   `Service.qml` only passes `file://` URLs to `mpvctl.py`, and `mpvctl.py`
   refuses credential-bearing URLs (userinfo or `u/t/s/p/token/password/...`
   query parameters) arriving in argv before any player call. The in-process
   `backend play` path still calls `do_load()` directly and is unaffected.
   *Checks:* `ArgvCredentialGuard` covers detection and the refusal (no
   `do_load` call, no secret echoed); the existing first-track QML check still
   proves local-file playback.

9. **Info — `.gitignore` backups.**
   Added plain `*.bak` beside the existing `*.bak-*`.
   *Checks:* `GitignoreBackups`.

10. **Info (partial) — doc scrub.**
    Replaced the one audit-cited real playlist name/ID in
    `spike/SUBSONIC-REPORT.md` with a generic `Example Playlist`
    (`pl:000000`). The owner handle stays (it is the product name). Fixtures
    (finding 11) were left alone as public, load-bearing data.

12. **Info — gitleaks placeholder.**
    Renamed the dummy test values in `tests/test_library.py` from the
    secret-shaped names to `DUMMY_T`/`DUMMY_S`. No `.gitleaksignore` was added.
    The rename was also applied to the single historical commit that introduced
    the placeholder so the reachable history is clean too.

### Changed checks and results

- Python: **119 tests OK, 5 skipped** (105 + 14 new audit regression tests).
- Live fixtures: **5 tests OK**.
- QML: **624 checks, FAILS=0** (616 + 8 new: 3 F1, 1 F6, 4 F4).
- Existing checks were not loosened or removed. `tests/test_library.py` only
  renamed its dummy sentinels; the QML first-track check still exercises the
  local `file://` tone.
- `--load-scripts=no` remains, all subprocess calls remain argument lists, and
  no credential file was opened by this pass (`ls -l` only).
- gitleaks 8.30.1 over the working tree and reachable history: **0 findings**
  after the rename, with no ignore file.

---

## v1.0.0-beta.1 — public release preparation

The internal v3.5.x lineage ends here; public versioning starts at
`v1.0.0-beta.1`. The internal history stays documented above and is not
retagged or rewritten.

### Merge and tag

- `v2` merged into `master` with a merge commit (`--no-ff`); the resulting tree
  is byte-for-byte `v2`'s tree (`git diff v2 HEAD` empty). `master` and the new
  tag were pushed. No history was rewritten.
- Annotated tag `v1.0.0-beta.1` is on the merge commit.
- `manifest.json` version is now `1.0.0-beta.1`; its stale "streams extracted
  from Bandcamp pages" description was replaced with the Subsonic/bar-panel
  description. The older `0.1.0` value belonged to the internal lineage.

### Installability fix

`cookies.py` had been left untracked and `.gitignore`d after the cookie
incident remediation. That was safe for the private working tree but made a
fresh clone unable to import a browser session, so the public install would
have failed at setup. The current loader contains no cookie values (only generic
browser paths and code), and is now tracked; `.gitignore` still ignores the
cookie jar (`cookies.txt*`), credentials, backups, caches and logs.

### Documentation and screenshots

- `README.md` was rewritten as the tester's front door: what it is, the Omarchy
  plugin install command, the full cookie and Subsonic setup walkthrough, one
  short security section, panel/queue shortcuts, the two optional (not shipped)
  `bindings.lua` lines, and screenshots.
- `docs/release-notes-v1.0.0-beta.1.md` drafts the GitHub Release: feature
  summary, beta environment-testing asks (resolutions, scaling, themes, library
  sizes), known limitations (streaming only, no downloads, pre-orders list but
  do not play until release day) and the issue tracker.
- Fresh captures were generated through the live-theme lane (real `$HOME` theme
  tokens and font, real `Bar.qml` and `qs.Ui.KeyboardPanel`, synthetic fixture
  data, no credentials/network/mpv/MPRIS): `docs/images/panel-normal.png`,
  `panel-queue.png`, `panel-syncing.png`. The README embeds the normal and queue
  captures.

### Verification

- Python: **119 tests OK, 5 skipped**. Live fixtures: **5 tests OK**.
- QML: **624 checks, FAILS=0**. `omarchy plugin validate .` passes.
- `--load-scripts=no` is unchanged; no credential or cookie value was read or
  printed during release preparation. No history rewrite, no visibility change,
  and nothing was published beyond the requested branch and tag push.
- Wording pass (docs only): MPRIS is now stated as the plugin's own bridge that
  publishes only playback state and track title/artist, does not use mpv-mpris
  and never puts stream URLs on the bus; reader-facing prose now says "kitty
  logo" instead of "cat mark"/"cat logo" (code identifiers such as
  `CatMark.qml` are unchanged).
