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
