# OmaTimeAtBandCamp — v3 UI Spec

For: OpenCode working in the existing OmaTimeAtBandCamp repo on branch `v2`.
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
- **Header.** The title row now contains only `OmaTimeAtBandCamp`; the title is
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
