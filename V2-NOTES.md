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
