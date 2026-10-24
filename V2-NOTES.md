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

## Phase 4: lists, wrapping, pre-order presentation (+ deselect, spec item 0)

Changed: `Panel.qml` (rewritten lists/header/track rows/menus), `Service.qml`, new `LibraryModel.js`, backend
(`model.py`, `library.py`, `match.py`, `bandcamp.py`, `__main__.py`), `mpvctl.py`, `tests/`, README, spec item 0.

Done per spec: 0 deselect (click the selected row again; selection, detail pane, Shuffle context follow; the album's
own Shuffle state is remembered) · 1 two-line rows (title max 2 lines, ellipsis only after line 2; artist on a
smaller dimmed line) · 2 right-pane header with the same treatment, wrapping track titles · 3 selected row (tint +
accent bar + bold) and playing track (tint + bar + ▶ marker + bold) · 4 pre-order rendering (row pill + date,
`PRE-ORDER · releases <date>`, `<n> of <total> tracks available`, unreleased rows at 45% opacity / no hover / `—` /
click only shows "Not yet released", Play reads "Play available" when streamable < total) · 5 sort menu (Recently added,
Artist A–Z, Title A–Z, Release date), Hide pre-orders toggle, both persisted in `~/.local/state/omatimeatbandcamp/ui.json`.

Where the existing code forced a decision:

1. **The UI now reads the backend's library cache.** v1's `collection.json` has no pre-order flag, release date, purchase
   date or per-track streamable flag (and still contained `&amp;`), so none of item 4/5 was renderable from it. `Service.qml`
   now displays `library/library.json` (the Phase 1 union: 688 albums incl. 47 Subsonic-only), Refresh = browser-session
   import then `backend sync` in the background (progress in the status line, "Library updated · N albums" on completion,
   the cached library stays on screen), and `fetch.py` is no longer used by the UI. Albums (N) therefore reads 688, not 645.
   IPC `play <id>` now takes the library id (e.g. `a:4039254352`); `status.user` comes from the library metadata.
2. **Playback of Subsonic tracks goes through `backend play <id> --title T`**, which builds the stream URL (it embeds
   u/t/s) inside the process and hands it to mpv: not in argv, not in output. The queue only ever holds streamable tracks.
   **A leak was found and fixed during verification:** the first version echoed mpv's `media-title`, which is the full URL
   (with u/t/s) for a stream without metadata, and that output reached the session transcript. Fixed in `mpvctl.do_load`
   (always sets `force-media-title`, never reads the URL back) and `backend play` (prints only `ok`/redacted `error`);
   pinned by 4 unit tests and re-verified live (mpv's title is the track name, output has only `ok`).
   Open: mpv's `path` property necessarily holds the URL, so the Phase 8 MPRIS work must not publish it.
3. **Backend additions the sort needed:** track `year` and album `year` (earliest track year; Subsonic has no album
   release date), epoch `purchased_ts`/`release_ts`, `detail_version` (old caches refetch their tracklists once), single-
   track parent albums inherit the web purchase date, library metadata `user`, and `sync` options
   `--cookies/--user-url/--no-playlists` so the existing settings keep working.
4. **Release date sort**: pre-orders by their page release date, released albums by 1 Jan of their earliest track year,
   unknown last (4 of 688 albums have no year), newest first.
5. **Why highlights never showed in v1**: it compared `modelData` objects by identity (`===`), which fails for list-model
   copies. Selection is now a uid resolved against the live library (it survives a background sync), track identity is a
   per-track uid, and `Service.indexOfTrack` replaces `indexOf` on objects.
6. **Whole-library context** (Phase 3) is now every streamable *album* track (no longer album + playlist tracks, which
   duplicated each other).
7. The artist line may also wrap to two lines (spec: "no mid-word single-line truncation anywhere"). Playlist rows use
   "N tracks" as their second line. Header totals use the tracks actually returned; truncated albums add
   "Showing 3 of 50 tracks (the source returned fewer)"; empty/unloaded albums say so instead of showing nothing.
8. Sort and Hide pre-orders are offered on the Albums list only; playlists keep the source order.
9. **Not done (belongs to Phase 5):** the footer now-playing title is still single-line with an ellipsis.

Lint note: `qmllint` now reports `Service.qml:523 QVariantMap -> QVariantHash` on the unchanged `environment:` binding (not
reported at HEAD); the harness loads that binding without error and the shell ran it before, so it is lint-only.

Tests run:

- `python3 -m unittest discover -s tests -t .`: 66 tests, OK (5 live-only skipped). New: timestamps/year, parent date,
  detail_version refetch, sync options, `play` never leaking (8 + 4).
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: 5 tests, OK.
- `tests/qml/run.sh`: 197 checks, OK = phase 1 (fixture library) 173 + relaunch 6 + real-data smoke 15 + 3 script-side
  checks (decoy cookie deleted; sort/filter written to `ui.json` after phase 1 and phase 2). Covers the deselect round trip,
  measured wrapping (`lineCount`, `truncated`, row heights), unreleased rows non-interactive, highlights in both states,
  all four sort orders + filter + persistence across a relaunch, and, on your real library, no HTML entity in any of
  26,860 strings, all four orders over every adjacent pair, and the First Impressions / La Dee La La / Crocbrain fixtures.
  Harness artefacts (not product bugs): synthetic clicks never deliver hover-leave, so "not highlighted" asserts the
  selection tint (0.22) rather than "no fill" (hover is 0.08); `FileView.reload()` in a probe goes stale, so persistence is
  read from disk by the script.
- Real `backend play` against Subsonic, throwaway mpv with `--ao=null`: streams, duration 558 s, position advances.
- `omarchy plugin validate .` OK.

Not verified by the harness: the real `KeyboardPanel` (click-outside/focus) and how it looks in the live shell. Run
`omarchy restart shell` to load this phase.
