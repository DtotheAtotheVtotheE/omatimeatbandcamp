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

## Phase 5: footer transport and now playing

Changed: `Panel.qml` (footer rebuilt), `Service.qml` (progress/seek state, polling, end-of-track and
failure handling), `mpvctl.py` (`status`/`seek`, no title reads), `backend/__main__.py` (`fatal` flag),
`LibraryModel.js` (`fmtClock`), `tests/test_phase5_playback.py`, `tests/qml/` (new checks + socket isolation),
README.

Done per spec: 1 three transport buttons (Prev, Play/Pause, Next), identical `BcButton` size/style, centred in
the footer · 2 the middle button is Play when idle/paused and Pause while playing (icon, tooltip and active
highlight all follow), **Stop removed** · 3 progress bar under the transport with elapsed/total labels,
click-to-seek and drag-to-seek (preview follows the pointer; seek is sent on release) · 4 now-playing title wraps
to max 2 lines with `Artist · Album` dimmed on line 2 (the Phase 4 single-line truncation is gone) · 5 a failed
stream shows a visible urgent-coloured footer notice `Couldn't play <title> — skipped` and advances the queue.

Where the existing code forced a decision:

1. **Two classes of playback failure.** `backend play` now returns `fatal` for a *configuration* failure
   (credentials file missing/wrong, server rejected the call, mpv did not start) and no `fatal` for a *stream*
   failure (mpv rejected the file). A fatal failure shows `Playback unavailable: …` and does **not** advance:
   every track would fail identically, so skipping would burn through the queue for nothing. A stream failure
   advances as the spec asks. This also keeps the QML harness (fake HOME, no credentials) from auto-skipping
   every fixture track. A 3-consecutive-skip cap stops a dead server spinning through a long queue; a
   single-track context says `Couldn't play <title>` (nothing to skip to).
2. **End-of-track detection is new.** mpv goes idle at EOF; the 1 s position poll treats `idle`/`eof` after a
   2.5 s grace (mpv is idle until the load lands) as the end. A track that stops >2 s short of its library
   duration is a failure; otherwise it advances silently. The last track stops instead of wrapping (manual Next
   still wraps); a stream that never produces a position is failed after 8 s. Without this, nothing would advance
   the queue at all, and Phase 5's failure requirement could not be met.
3. **Seek works on the stream.** `mpvctl.py seek` uses `absolute+exact`; verified live on a throwaway silent mpv
   against Subsonic: position 2.7 s → `seek 120` → 120.0 s, duration 558.3 s. So no "cannot seek" limitation to
   note; the bar is determinate from the library duration even before mpv's first reply.
4. **Stop stays available over IPC only** (`omatimeatbandcamp stop`). mpv needs no stop to release a stream
   (loading another file replaces it, and idle drops the connection), so no long-press/right-click mapping was
   added to the Pause button — there is no fourth button.
5. **Footer error replaces the `Artist · Album` line** rather than adding a third line. The footer is 84 px
   (was 64) so two title lines fit; the list height is unchanged and the popup still fits its 660 px cap (the
   screenshots show no clipping). The error is always visible while set (not a timed toast) and clears when the
   next track loads.
6. **`pluginDir` was broken under Quickshell's `qs:` URL scheme.** `Qt.resolvedUrl("Service.qml")` can return
   `qs:@/qs/plug/Service.qml`, which python cannot open: every `backend play` in the harness (and every
   `backend sync`/`cookies.py` call there) had been failing silently with "can't open file …/qs:@/qs/plug/backend".
   It now uses the `file://` path when that is a real file, else the documented third-party plugin directory
   (`~/.config/omarchy/plugins/<id>`), with `OMATIME_PLUGIN_DIR` as an explicit override. The harness sets that
   override. The live shell likely resolved `file://` all along, but this removes the ambiguity for playback,
   Refresh and the cookie import.
7. **Harness isolation.** `tests/qml/run.sh` now gives each launch its own `OMATIME_MPV_SOCK` and
   `OMATIME_MPV_FLAGS=--ao=null`. The new end-of-track poller exposed that the harness had been querying the
   *user's live idle mpv* on the default socket and reading "idle" as "track finished" (it skipped a fixture
   queue). Tests no longer touch the real player.
8. Position polling runs while `isPlaying`, including while paused: mpv owns `pause`, and stopping the
   poll on the plugin's own flag let an inverted pause state freeze the footer (fixed after v3.2; see the
   v3 spec's post-v3.2 section). The poll runs at 250 ms until the first second is on the clock, then 1 s.
   A pending seek is displayed optimistically until mpv reports a position within 1.5 s of the target (or
   2.5 s pass), so the bar does not bounce back for a tick after a seek. `applyPlaybackStatus()` is the
   single parse point, which is what the harness feeds.
9. Not done (later phases): keyboard seek/list keys and MPRIS (Phase 8); the Waybar `BC` suffix (Phase 6).
   `statusJson()` still exposes only title/artist/album — no URL — and mpv's `path` remains a URL for Phase 8 to
   keep private.

Tests run:

- `python3 -m unittest discover -s tests -t .`: **76 tests, OK (5 live-only skipped)** — baseline was 66. The 10
  new ones pin: `status` asks only for progress properties (never title/path/URL), seek is absolute+exact and
  clamped, bad numbers never reach mpv, `do_load` distinguishes environment vs stream failure, missing
  credentials are fatal, and a stream failure is skippable without leaking the URL.
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: **5 tests, OK**.
- `tests/qml/run.sh`: **219 checks, OK** = phase 1 (fixture) 195 + relaunch 6 + real-data smoke 15 + 3 script-side
  checks. Baseline was 197; the 22 new checks cover: exactly 3 footer buttons, no Stop glyph, identical style,
  centred; Play↔Pause icon/tooltip/highlight; two-line footer title measured (`lineCount`, `truncated`) and the
  `Artist · Album` line; measured progress fill at 25% with `0:50`/`3:20` labels; click-to-seek to 50%; drag
  preview (`2:40` while dragging) then release at 80%; a mid-stream failure shows the exact notice, advances the
  queue and draws in `Color.urgent`; a natural end advances with no error.
- Live: real `backend play` + `mpvctl.py seek 120` on a throwaway `--ao=null` mpv — load `{"ok": true}`, position
  2.7 s → 120.0 s, no URL in any output; only the user's original idle mpv remained afterwards.
- `omarchy plugin validate .`: OK. `qmllint`: only the pre-existing `Service.qml environment:` type warning.

Not verified by the harness: the real `KeyboardPanel` and live-shell look. Run `omarchy restart shell`.

## Phase 6: Waybar module (BC suffix, clicks, album art)

Changed: `Panel.qml` (bar text/click targets), `Service.qml` (art jobs + RTMIN signal),
`backend/art.py` + `backend/__main__.py` (`art` command), `LibraryModel.js` (cover/subsonic
album ids), `bar-art/` (separate companion bar widget), `assets/current-art-placeholder.jpg`,
`tests/test_phase6_art.py`, `tests/qml/`, README.

Done per spec: 1 the module text is always `BC`; state is only a suffix — `BC ❚❚` playing,
`BC ▶` paused, plain `BC` stopped. It never becomes a bare play/pause glyph. 2 left-click
opens/closes the window, right-click toggles play/pause, middle-click goes to the next track
(the optional middle-click is implemented). 3 album art is a separate bar widget placed
immediately left of `BC`; on every track change the backend writes
`~/.cache/omatimeatbandcamp/current-art.jpg`, downscaled to <=128 px, and the service emits
`RTMIN+8`; stopping writes the bundled BC placeholder. A missing/partial file falls back to
the placeholder, so the bar never paints a broken image.

Where the environment/code forced a decision (flagging because the spec says Waybar):

1. **This machine has no Waybar.** Omarchy's bar is Quickshell; there is no
   `~/.config/waybar/`, no `image` module type, and no module signal numbers to inspect.
   The equivalent is a second bar widget (`bar-art/ArtWidget.qml`), installed as the sibling
   plugin `com.github.dtotheatothevtothee.omatimeatbandcamp-art` (a symlink to `bar-art/` so
   the source stays in git) and inserted immediately before the BC entry in
   `~/.config/omarchy/shell.json`. That config file is outside the repo and was backed up to
   `shell.json.bak-2026-10-23` before editing. Quickshell updates through `FileView` watching
   the local file; a 900 ms retry keeps the placeholder up if the file is not written yet.
   `RTMIN+8` is still emitted (`pkill -RTMIN+8 waybar`) for a legacy Waybar image module, but
   nothing on this machine consumes it. No existing config used any RTMIN signal.
2. **Art source.** The library is hybrid: tracks carry `subsonic_album_id`, albums carry
   `cover_art_id`. `Service.coverArtIdFor()` uses a track's own cover id, else the album's
   cover id by Subsonic album id, else album+artist. Web-only/pre-order tracks have no cover
   id and get the placeholder (they are unplayable anyway).
3. **Downscaling uses ImageMagick.** Pillow is not installed. `backend/art.py` fetches through
   the authenticated Subsonic client and runs `convert ... -resize '128x128>'` (shrink-only).
   The raw URL is local to the backend function; neither the CLI nor QML ever sees it.
4. **Always-valid file.** A fetch/scale failure still writes the bundled placeholder and
   returns `{ok:false, placeholder:true}`; the UI never shows a broken image.
5. **Test seam.** `OMATIME_ART_FIXTURE_DIR` maps a cover id to `<dir>/<id>.jpg` so the QML
   harness exercises the real downscale path offline; it is only set by `tests/qml/run.sh`.

Tests run (final):

- `python3 -m unittest discover -s tests -t .`: **82 tests, OK (5 live-only skipped)** — baseline
  was 76. Six new tests pin: placeholder is a valid 128x128 private JPEG; downscale shrinks but
  never enlarges; a track change replaces the bytes; fetch uses the client URL internally; a
  fetch failure message contains no URL/token/salt; the CLI prints only local paths.
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: **5 tests, OK** (unchanged).
- `tests/qml/run.sh`: **242 checks, OK** = phase 1 (fixture) 218 + relaunch 6 + real-data smoke
  15 + 3 script-side checks. Baseline was 219. The 23 new checks cover: stopped/playing/paused
  suffix text, the separate art module loading and showing the local file, placeholder written
  byte-identically on stop, first cover 300x120 -> 128x51, pause keeps the cover, a track change
  replaces it with 90x260 -> 44x128, stop restores 128x128, right-click play/pause, middle-click
  next, left-click open/close.
- `omarchy plugin validate .` and `omarchy plugin validate bar-art`: OK. `qmllint`: only the
  pre-existing import/unqualified warnings (no new errors).

Not verified by the harness: the real shell bar after `omarchy restart shell`, and the legacy
Waybar `image` module (Waybar is not installed here).

## Phase 7: external links row

Changed: `Panel.qml` (links row + URLs, list height), `Service.qml` (`openExternal` + opener
process), `tests/qml/run.sh` (xdg-open recorder, script-side URL check), `tests/qml/shell.qml`
(11 phase-1 checks + 1 real-data check), README.

**Placement: one row of six uniform `BcButton`s directly beneath the search box**, not the ⋯
overflow menu. Measured at the fixture window width: the six labels plus `sm` spacing occupy
about 640 px of the 920 px content width, so there was no genuine space pressure. The row is
inside the 660 px popup cap (see deviation 1).

**Verified URLs (checked live 2026-10-23, logged-in session where noted):**

| Button | URL | Verification |
|---|---|---|
| Bandcamp | `https://bandcamp.com` | spec URL, HTTP 200 |
| Discover | `https://bandcamp.com/discover` | spec URL, HTTP 200 |
| Editorials (Daily) | `https://daily.bandcamp.com` | spec URL, HTTP 200 (final URL has a trailing `/`) |
| Radio | `https://bandcamp.com/radio` | link found on the bandcamp.com homepage (`/radio?from=homepage&ui_context=bcradio`); clean base URL returns HTTP 200 |
| Your Feed | `https://bandcamp.com/<username>/feed` | with the saved Bandcamp session: HTTP 200, title "Music feed — Bandcamp". Logged out, `/feed` redirects to the collection page, so this path is the logged-in feed. Verified for this account as `https://bandcamp.com/dtotheatothevtothee/feed` |
| Your Collection | `https://bandcamp.com/<username>` | with the saved session: HTTP 200, title "<username>'s collection — Bandcamp". Verified for this account as `https://bandcamp.com/dtotheatothevtothee` |

The username is not hardcoded: `Panel.bandcampUser` comes from `Service.detectedUser`, which is
read from the library cache metadata (`meta.user`). The two per-user buttons stay disabled
(tooltip "Username not known yet") until that value is loaded, so no guessed URL can be opened.
Only `https://` URLs are passed to the opener.

Where the existing code/environment forced a decision:

1. **The links row needed 34 px.** It pushed the footer's seek area just below the 660 px popup
   cap, and the four Phase 5 seek checks started failing (the clicks landed outside the visible
   window). Fixed in the product, not the tests: the library/detail row is now 396 px instead of
   430 px, restoring the previous popup height. No existing assertion was weakened.
2. **Test seam instead of a browser.** `Service.openExternal()` runs
   `$OMATIME_OPEN_CMD` (default `xdg-open`) with the URL as the only argument. The harness sets
   it to a recorder script that appends the URL to `$OMATIME_OPEN_LOG`; the shell script then
   asserts the log contains exactly the six verified URLs in order, so no browser can be
   launched from the harness.
3. **Button count.** The shared-style check now expects 16 buttons (10 controls + 6 links), not
   10; the style invariants (one height, one icon size, bordered) are unchanged.

Tests run (final):

- `python3 -m unittest discover -s tests -t .`: **82 tests, OK (5 live-only skipped)** — unchanged.
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: **5 tests, OK** — unchanged.
- `tests/qml/run.sh`: **255 checks, OK** = phase 1 (fixture) 229 + relaunch 6 + real-data smoke
  16 + 3 script-side checks. Baseline was 242. New: all six labelled buttons present, one row,
  uniform style, placed between search and toolbar; the four fixed URLs exact; Feed/Collection
  built from the fixture username; each button opens its exact URL through the real
  `Service.openExternal` path; on the real library, Feed/Collection use the real username; and
  the script-side check that the recorder received exactly the six URLs in order.
- `omarchy plugin validate .`: OK. `qmllint`: only the pre-existing unqualified-access warnings.

Not verified by the harness: the live shell look after `omarchy restart shell`, and that the
owner's default browser actually opens (the harness deliberately intercepts the opener).

## Phase 8: keyboard navigation + MPRIS

Changed: `Panel.qml` (panel-scoped key model, list/track cursors, row click focus, shared Esc
layering), `Service.qml` (whitelisted MPRIS state file, daemon spawn, IPC `resume`/`pause`/`seek`/`restartPlayer`),
`backend/mpris.py` (new MPRIS D-Bus service), `mpvctl.py` (`--load-scripts=no`), `tests/qml/run.sh`
(`OMATIME_MPRIS=0`, harness mpv cleanup, no-global-shortcut source check), `tests/qml/shell.qml`
(25 keyboard + metadata-fence checks), `tests/test_phase8_mpris.py` (new D-Bus tests), README.

### Keybind inventory (2026-10-24)

- **Hyprland/Omarchy:** `hyprctl binds -j` reports **235 active binds**. Every bind whose key is
  an arrow, Return, Space, slash or Escape carries SUPER (`modmask 64`) or ALT (`8`): e.g.
  SUPER+arrows focus/swap/move/group windows, SUPER+SLASH monitor scaling, SUPER+SPACE Omarchy
  menu, SUPER+ESCAPE system menu, SUPER+RETURN terminal, ALT+SPACE oma-cast. **There is no
  unmodified global bind on any Phase 8 key**, so the panel-scoped bare keys cannot collide.
- **Quickshell shell:** `Ui/PanelKeyCatcher.qml` is a per-panel dispatcher wrapped by
  `Ui/KeyboardPanel.qml`; it is only active while that panel owns keyboard focus. The shell has
  no global single-key shortcut API in use. `Ui/KeyboardPanel.qml` gives this plugin's window
  keyboard focus only while the popup is open (Exclusive prime, then OnDemand).
- **This plugin before Phase 8:** only the search `TextField` handled keys (`Keys.priority:
  BeforeItem`): Esc layering (confirmation → menu → search text → close) and Up/Down/Enter while
  the ⋯/Sort menu was open. Nothing was registered globally.
- **Media keys:** `XF86AudioPlay/Pause/Next/Previous` are globally bound by
  `/usr/share/omarchy/default/hypr/bindings/media.lua` to `omarchy-shell media ...`, i.e. MPRIS.
  Exposing the player is what makes the laptop media keys work; no new bind was added.

No key conflict was found, so nothing was remapped. All new handling lives in the plugin's
`searchField` and a panel-only `listKeyCatcher` Item (`Keys.priority: Keys.BeforeItem`); no
Hyprland `bind`, `GlobalShortcut`, or owner keybind file was touched.

### Keyboard model

Search owns focus on open. Down/Up from search enters the left list (album/playlist/search
results) at the current selection or row 0; Up from search enters at the last row. Inside a list:

- Up/Down move the cursor; the left list's selection follows it with a non-toggling
  `selectAlbum`/`selectPlaylist` (clicking still deselects, per Phase 4.0).
- Enter plays the focused album/playlist/track (or the focused search result).
- Space toggles play/pause. Space in the search field still types a space, which is the spec's
  "when not typing in search" case.
- Left/Right switch between the left list and the detail track list (panel-only extension; both
  are "the focused list").
- `/` returns focus to search (consumed from a list; typed normally inside search).
- Typing any printable character while a list is focused returns to search and keeps the
  character, so navigation never traps the keyboard.
- Esc uses the existing layering: cancel logout confirmation → close menu → clear search →
  close window. It is now shared by both focus panes (`handleEscape()`).
- Clicking a row also focuses its list and sets the cursor, so mouse and keyboard agree.

### MPRIS

Implemented, not deferred. `backend/mpris.py` is a standalone dbus-python service that owns
`org.mpris.MediaPlayer2.omatimeatbandcamp` at `/org/mpris/MediaPlayer2`. It publishes
`PlaybackStatus`, `Position`, `Metadata` (`xesam:title`, `xesam:artist`, `xesam:album`,
`mpris:length`, `mpris:artUrl`), `CanPlay/Pause/Seek/GoNext/GoPrevious/Control`, and implements
Play/Pause/PlayPause/Stop/Next/Previous/Seek/SetPosition. Controls call the plugin's existing IPC:
`omarchy-shell omatimeatbandcamp playPause|resume|pause|next|previous|stop|seek <seconds>`.

The QML side writes `~/.cache/omatimeatbandcamp/mpris-state.json` every second with an **explicit
whitelist**: `title, artist, album, status, position, duration, updatedAt, canSeek, canPlay,
canPause, canNext, canPrevious`. The daemon copies only those keys and ignores everything else.
`mpris:artUrl` is built by the daemon from its `--art` argument (the local cached
`current-art.jpg`), never from the state file, so a remote cover URL cannot enter metadata.

**Security finding:** `/etc/mpv/scripts/mpris.so` (mpv-mpris) is auto-loaded into *every* mpv on
this machine, including our headless player. mpv-mpris publishes `xesam:url` from mpv's `path`,
which for Bandcamp is the signed stream URL with `u`/`t`/`s` parameters. It also created duplicate
MPRIS players (14 stale harness mpv processes were owning names). `mpvctl.spawn_mpv()` now passes
`--load-scripts=no`: our mpv loads no auto scripts, so it can never publish the stream URL, and
only `backend/mpris.py` appears to MPRIS clients. The daemon itself never reads mpv's `path`; the
metadata comes from the library track object. A decoy `path`/`url`/`coverArtUrl` written into the
test state file is ignored (asserted in `tests/test_phase8_mpris.py`).

`OMATIME_MPRIS=0` disables the daemon; `tests/qml/run.sh` sets it so the harness never starts a
real player. The daemon exits if another instance owns the name, after 60 s without a state
update (the plugin writes every second while loaded), and when its Quickshell parent dies
(`PR_SET_PDEATHSIG`), so a shell restart does not leave an orphan holding the MPRIS name.

`playerctl` is not installed on this machine, so the D-Bus test dumps the same properties with
dbus-python on a private `dbus-daemon` session and asserts: title/artist/album match the library
track; `mpris:artUrl` is exactly the local `file://` cover; no `path`/`url`/`coverArtUrl` key is
published; and no non-art value contains `://`, `?`, `u=`/`t=`/`s=`, token/password/credential/salt.
The daemon is also exercised through `PlayPause`, `Next`, `Previous`, `Pause`, `Play`, `Seek` and
`SetPosition`, and the test asserts `--load-scripts=no` is in the spawn args.

Tests run (final, raw counts):

- `python3 -m unittest discover -s tests -t .`: **86 tests, OK (5 live-only skipped)**. Baseline was
  82. Four new MPRIS tests: published metadata is clean and local; state updates are published;
  control methods reach the plugin IPC; our mpv spawn disables the global MPRIS script.
- `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures`: **5 tests, OK** (unchanged).
- `tests/qml/run.sh`: **281 checks, OK** = phase 1 (fixture) 254 + relaunch 6 + real-data smoke 16 +
  5 script-side checks. Baseline was 255 = 229 + 6 + 16 + 4 script-side (the Phase 7 note said 3
  script-side; the actual run.sh has four: logout deletion, phase-1 ui.json, link log, phase-2
  ui.json). New checks cover: search focus on open; Down enters the list and selects row 0;
  non-toggling selection; second Down/Up; Enter plays the album context; Space pauses/resumes in
  the list; `/` returns to search; typing in a list refocuses search and keeps the character;
  Space in search types a space and does not toggle; Esc clears then closes; track-pane focus,
  cursor tint, Down/Up, Enter plays the focused track; and the metadata fence (title/artist/album
  present, exact whitelist, no path/url/cover field, no URL scheme/query/credential word). One
  script-side check scans the plugin for `GlobalShortcut`/window `Shortcut`.
- `omarchy plugin validate .`: OK. `qmllint`: only the pre-existing unqualified-access warnings.
- Harness mpv cleanup: `tests/qml/run.sh` now kills only processes whose IPC socket is under its
  own `$work` dir, so harness runs no longer leave 14 idle mpv players holding MPRIS names.

Not verified by the harness: the live shell after `omarchy restart shell`, the physical media
keys, and the real Quickshell `KeyboardPanel` focus/click-outside behavior (stubbed offscreen).

### Owner live check

1. `omarchy restart shell`, then open the panel from `BC`.
2. **One-time migration:** an mpv started before this update still has the global
   `/etc/mpv/scripts/mpris.so` loaded and publishes `xesam:url` for the loaded track. On this
   machine the pre-update player was paused mid-track, so it was left alone. After the shell
   restart (which installs the new IPC), run
   `omarchy-shell omatimeatbandcamp restartPlayer` (keeps the queue, resets to stopped, quits the
   old mpv) and press Play; the next mpv is spawned with `--load-scripts=no`, and only then is the
   old MPRIS name gone.
3. Type a search; press Esc once (search clears), Esc again (window closes).
4. Reopen; press Down (list focus), Down/Up (selection moves), Enter (album plays).
5. With the list focused, press Space (pause), Space again (resume); press `/` (search focus).
6. Click an album, then Right (track list), Down/Up, Enter.
7. Play a track and check the media keys: Play/Pause, Next, Previous.
8. Dump the published player without `playerctl` (not installed):
   `busctl --user list | grep omatimeatbandcamp` and
   `gdbus call --session --dest org.mpris.MediaPlayer2.omatimeatbandcamp --object-path /org/mpris/MediaPlayer2 --method org.freedesktop.DBus.Properties.GetAll org.mpris.MediaPlayer2.Player`.
   Expect title/artist/album and a `file://.../current-art.jpg` art URL; no stream URL, query
   parameters, or credentials. There should be no `org.mpris.MediaPlayer2.mpv.*` name for our
   player (the global mpv-mpris script is disabled for it).
