# V2 notes

Per-phase results for `docs/omatimeatbandcamp-v2-spec.md`. Phase 0/1 measurements live in `spike/SUBSONIC-REPORT.md`.

## Phase 2: header and window chrome

Changed (`Panel.qml`, new `BcButton.qml`, one line in `Service.qml`):

- **One button style.** `BcButton.qml` wraps the shell `Button` with a fixed look: bordered, 16px icon
  (`Style.space(16)`), `Style.spacing.controlHeight` high, icon-only buttons square, dimmed when disabled.
  Every control in the window uses it: header, toolbar (Albums / Playlists / Play all / Shuffle / Refresh), the
  ⋯ menu entries and the footer transport. No bare glyph controls remain.
- **× removed.** Esc and click-outside are unchanged shell behaviour (`KeyboardPanel`).
- **Clear-session icon removed from the header.** "Log out / Clear Bandcamp session" is now the only entry of a
  single ⋯ overflow menu (Esc / click-outside / the ⋯ button close the menu; Up/Down/Enter work in it). It opens a
  `ConfirmDialog` with Cancel preselected; confirming calls the existing `Service.clearCookies()`.
- **Refresh** is a labelled toolbar button (icon + "Refresh"), right-aligned in the toolbar row next to the status
  text, disabled, dimmed and spinning while a refresh runs (`Service.refreshing`).
- **Esc is layered**: confirmation, then menu, then search text, then window.

Spec vs. existing QML (spec wins):

- Spec 2.1 says ALL controls. The old toolbar buttons were already the shell `Button`, but the header icons were
  `PanelActionButton` glyphs and the footer play button had its own accent fill and larger icon; all now use BcButton.
- Spec 2.3 offers two wordings depending on Phase 0. The decision was B (hybrid), where the plugin still holds a Bandcamp
  session, so the item is "Log out / Clear Bandcamp session". Nothing in the UI reads Subsonic credentials yet, so no
  "Remove saved Subsonic credentials" item was added.
- Kept on purpose for later phases: Play all and the cycling Shuffle (Phase 3), the Stop button (Phase 5).

Tests run:

- `python3 -m unittest discover -s tests -t .`: 54 tests, OK (5 live-only skipped); with `OMATIME_LIVE=1` the 5 live fixture checks pass.
- `tests/qml/run.sh` (new): 31 interaction checks + decoy-cookie deletion, all pass. It runs the real Panel/Service/BcButton
  inside a throwaway copy of the shell with a stubbed `KeyboardPanel` and a fake `$HOME`. It caught a real bug during
  development (Esc with the menu open closed the whole window because the search field's own Esc handler ran first).
- `omarchy plugin validate .`: OK. `qmllint`: no errors beyond the shell's untyped-property noise.

Not verified by the harness: the real `KeyboardPanel` click-outside-to-close and focus priming (shell code, unchanged;
needs a look in the live shell after `omarchy restart shell`).

Noticed, not fixed (outside Phase 2):

- `cookies.py`, which `Service.refresh()` runs to import the browser session, is not in the working tree (it is in
  `.gitignore` and was removed by the history rewrite). Refresh therefore cannot import a session right now, and
  "Log out" will delete the cache `cookies.txt` with no importer to bring it back. The old file survives only in the
  local `refs/original/*` backup refs (commit `12471a4`), which were never pushed.

## Phase 3: toolbar (no Play all, one Shuffle toggle)

Changed (`Panel.qml`, `Service.qml`, `tests/qml/shell.qml`, README):

- **Play all deleted** (button, `Service.playAll()`). Playback scope is the current context.
- **Shuffle is one toggle**, `Shuffle: On` / `Shuffle: Off`, highlighted (the shell's selected style, same as the
  active tab) when On. The 0..3 `shuffleMode`, `shuffleNames`, `shuffleLabel` and `cycleShuffle()` are gone.
- **Albums (N) / Playlists (N)** stay as the view switch, shared BcButton style, counts live.

Where the existing code forced a decision (flagging because the spec is silent or assumes otherwise):

1. **Per-context shuffle.** The spec says Shuffle "applies to the current context", and "toggling in an album must not change
   a playlist". A single global flag cannot do that, so state is kept per context, keyed by what the detail pane shows:
   `album:<id>`, `playlist:<id>`, `search`, `library` (nothing selected). Each album and each playlist has its own state
   (memory only, not persisted). Toggling a context other than the one that is playing never touches the live queue;
   toggling the playing context reorders its queue and keeps the current track playing. Keying per type (all albums share
   one flag) would be a one-line change in `Panel.contextKey`.
2. **Whole-library entry point.** With Play all gone nothing could start the library, and the footer Play button did nothing
   when idle. It now starts the *current context* when no track is loaded: selected album, selected playlist, search
   results, or (nothing selected) the library via `Service.playLibrary()`. Limits: (a) "library" is only the tracks loaded
   so far (collection items carry tracks only after their album is opened; this is the same data Play all used) until the
   Phase 1 backend is wired into the UI; (b) the UI has no way to return to "nothing selected" once an album/playlist has
   been clicked, so the library context is reachable at the start of a session only. A natural fix (click the selected row
   again to deselect) touches row behaviour, so it was left for Phase 4 / your call.
3. **The Albums/Playlists switch never worked.** `Service.activeTab` was never declared (also absent in v1), so Panel's
   assignment was silently dropped: neither tab ever highlighted and the list never switched. Declared as
   `property int activeTab: 0`; the harness now checks highlight and list content.
4. **Shuffle start track.** Old behaviour with shuffle on: clicked track ignored, queue started at a random track. Now the clicked
   track plays first and the rest of that context follows shuffled (spec 1.4 "starting at the clicked track").
5. **IPC `status`**: `shuffle` is now 0/1 for the playing context (was 0..3), so truthiness checks in scripts still work.

Not touched, as instructed: the Stop button (Phase 5) and row rendering (Phase 4).

Tests run:

- `python3 -m unittest discover -s tests -t .`: 54 tests, OK (5 live-only skipped).
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: 5 tests, OK.
- `tests/qml/run.sh`: 74 checks + decoy-cookie check, all pass (Phase 2 had 31). New: no Play-all string anywhere in the item
  tree and no `playAll()`; exactly one Shuffle control; 7 presses show only the two labels strictly alternating, highlighted
  exactly when On; album/playlist/library/other-album states independent through the real UI; queue behaviour with
  synthetic tracks (clicked track first, permutation, album toggle leaves a playing playlist's queue untouched and vice
  versa, playing context reorders and restores in place); idle footer Play for library and for a selected album; view switch
  highlight, list content and live counts.
- `omarchy plugin validate .` OK; `qmllint` no errors beyond the shell's untyped-property noise.
