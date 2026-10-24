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
