# OmaTimeAtBandCamp

Bandcamp collection/playlists player with stream extraction for Omarchy.

## Configuration

- `userUrl`: Your Bandcamp collection URL. Leave **empty** to auto-detect your
  account from the Bandcamp session in your browser (recommended). Set it
  explicitly to browse a different profile.
- `cookiePath`: Advanced. Leave empty to auto-import cookies from your browser on every refresh. Set it to force a specific Netscape-format cookies.txt instead (auto-import is then skipped).
- `browser`: Which browser to import the session from (`auto`, `chrome`, `chromium`,
  `brave`, `edge`, `vivaldi`, `firefox`). `auto` picks the best candidate.
- `includePlaylists`: Include playlists in library
- `refreshIntervalMin`: How often to refresh cache (5-240 min)
- `mpvFlags`: Extra mpv flags (optional; video is always disabled)
- `autoPlayOnSelect`: Auto-play on track selection (reserved)

## Cached cover art

The bar-art widget was removed in v3. The backend still writes the current
Subsonic cover, downscaled to <=128 px, to
`~/.cache/omatimeatbandcamp/current-art.jpg` because MPRIS publishes that local
file as `mpris:artUrl`; when stopped it writes the bundled BC placeholder. No
cover URL ever reaches QML, the bar config or a log.

## Credentials & privacy

There are no usernames, passwords, or API tokens in this plugin. Authentication is
your Bandcamp session cookie (`identity`), which is imported automatically:

- With `userUrl` empty, the account is auto-detected from the session cookie via
  `https://bandcamp.com/settings` (`identities.fan`), so no manual URL is needed.
- `cookies.py` reads the cookies straight out of the browser you are already signed
  in to (Chromium family decrypted via the `secretstorage` keyring + AES-128-CBC, or
  Firefox's plaintext `cookies.sqlite`) and writes a Netscape `cookies.txt` into the
  cache. `fetch.py` sends it as a `Cookie` header; `mpvctl.py` passes it to mpv.
- The cookie jar and cache live in `~/.cache/omatimeatbandcamp/` (dir `0700`,
  `cookies.txt` `0600`) and are **never** part of the plugin source.
- Use the gear menu's "Log out / Clear Bandcamp session" item (or `clearCookies`
  over IPC) to delete the imported jar; the next refresh re-imports it.
- If your browser is not running or the keyring is locked, cookies may be
  unavailable; set `cookiePath` to a file you export yourself instead.

## Usage

- Left-click the bar item to open/close the panel (from anywhere:
  `omarchy-shell omatimeatbandcamp toggle`, which uses the shell's own panel
  lifecycle).
- Right-click the bar item to play/pause; middle-click goes to the next track.
- The module text is always plain `BC`; there is no playback suffix and no separate
  album-art bar widget (v3).
- The search row has the flexible search field (with a click-to-clear ×, or a magnifier
  when empty, inside its right end), the single Collection link built from the username in the library cache
  (`xdg-open`; disabled until the username is known), and the gear button.
- The gear menu holds Refresh library, Hide pre-orders (checkable, remembered) and
  Log out / Clear Bandcamp session (with confirmation).
- Panel has tabs for Albums and Playlists, a search box, and a now-playing bar.
- **Keyboard (panel-scoped only):** these shortcuts work only while the popup is open and focused.
  The plugin registers no global shortcut; optional user binds are in
  [Keyboard shortcuts](#keyboard-shortcuts).
  - `↓` / `↑` from search enters the focused list and moves the cursor; `Enter` plays the
    selected album, playlist, search result or track.
  - `←` / `→` switch between the album/playlist list and the track list.
  - `Space` toggles play/pause when a list is focused; while typing in search it types a space.
  - `/` returns focus to search. Typing while a list is focused also returns to search and keeps
    the character.
  - `Tab` / `Shift+Tab` walk the header in visual order (search → ×/magnifier → Collection → gear → Albums → Playlists → Sort); click the × (or press Enter/Space on it) to clear the search.
  - `Esc` backs out one layer: cancel confirmation, close menu, clear search, close window.
- **Media keys:** the plugin publishes MPRIS (`org.mpris.MediaPlayer2.omatimeatbandcamp`), so the
  laptop's Play/Pause, Next and Previous keys work through Omarchy's existing
  `omarchy-shell media ...` bindings.

## Queue

- Right-click a track row for **Play Next** (front of the queue) or **Add to Queue** (end).
  Duplicates are allowed; unstreamable/unreleased tracks cannot be queued and both actions are
  disabled on them. Right-click an album or playlist row to append its streamable tracks.
- A non-empty queue appears as **Up Next (n)** above the current album/playlist/search contents,
  in the order you added it. Double-click a row to play it immediately (dropping it and the rows
  ahead of it), right-click for **Remove from queue**, or use **Clear** to drop all pending rows.
- The queue is **session-only**: it is never written to disk, so a shell restart starts empty. It
  is also cleared when you start something in a different context (another album, playlist or
  search result set, or a single track). Starting another track in the same context keeps it.
- Queued tracks keep their added order even with Shuffle On (Shuffle reorders only the context).
  When the queue drains, the context resumes with the track after the one that was interrupted.
  Previous steps back through what actually played (queued track, then the interrupted track).

## Keyboard shortcuts

### Global transport (recommended)

The plugin **ships no keybindings** (store rule). Add these two to your personal
Hyprland bindings — on current Omarchy that is `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + B", "OmaTimeAtBandCamp panel",
       "omarchy-shell omatimeatbandcamp toggle")
o.bind("SUPER + ALT + P", "OmaTimeAtBandCamp play/pause",
       "omarchy-shell omatimeatbandcamp playPause")
```

They take effect when the file is saved (Hyprland reloads the Lua bindings);
otherwise run `hyprctl reload`. They work with the panel closed, from any app.
With nothing loaded this session, play/pause is a harmless no-op.

On an older `~/.config/hypr/hyprland.conf`:

```
bind = SUPER ALT, B, exec, omarchy-shell omatimeatbandcamp toggle
bind = SUPER ALT, P, exec, omarchy-shell omatimeatbandcamp playPause
```

**Check before you paste:** `SUPER + ALT + B` and `SUPER + ALT + P` were free on
the machine this was written on, but always check your own setup first (below).

#### Optional: previous / next

If you also want global track skipping, add these. On current Omarchy
`SUPER + ALT + LEFT` and `SUPER + ALT + RIGHT` already mean "Move window to
group on left/right" (Omarchy's tiling defaults), so either unbind those two
first (see below) or pick different keys.

```lua
o.bind("SUPER + ALT + LEFT",  "OmaTimeAtBandCamp previous", "omarchy-shell omatimeatbandcamp previous")
o.bind("SUPER + ALT + RIGHT", "OmaTimeAtBandCamp next",     "omarchy-shell omatimeatbandcamp next")
```

Or in `~/.config/hypr/hyprland.conf`:

```
bind = SUPER ALT, LEFT,  exec, omarchy-shell omatimeatbandcamp previous
bind = SUPER ALT, RIGHT, exec, omarchy-shell omatimeatbandcamp next
```

### Make them yours

- **Change a key** by editing only the first string of its line, e.g.
  `"SUPER + ALT + B"` → `"SUPER + SHIFT + B"`. Leave the command (third
  argument) alone.
- **Check a combo is free:** press `SUPER + K` for Omarchy's keybindings list,
  or run `omarchy menu keybindings --print` / `hyprctl binds`.
- **Unbind before rebinding** a key that already exists, in the same personal
  file (for example, if you add the optional previous bind on Omarchy's taken
  arrow):
  ```lua
  hl.unbind("SUPER + ALT + LEFT")
  o.bind("SUPER + ALT + LEFT", "OmaTimeAtBandCamp previous", "omarchy-shell omatimeatbandcamp previous")
  ```
  The plugin never unbinds or overwrites anything for you.

### Built-in panel keys (no setup)

These work only while the popup is open and focused:

- `↓` / `↑` from search enters the focused list and moves the cursor; `Enter`
  plays the selected album, playlist, search result or track.
- `←` / `→` switch between the album/playlist list and the track list.
- `Space` toggles play/pause when a list is focused; while typing in search it
  types a space.
- `/` returns focus to search. Typing while a list is focused also returns to
  search and keeps the character.
- `Esc` backs out one layer: cancel confirmation, close menu, clear search,
  close window.

## Features

- Browse Albums (collection) and Playlists; global search across albums and playlist tracks
- Library = the union of your Bandcamp collection and Bandcamp's Subsonic server (so owned albums whose
  pages Bandcamp no longer lists still show up and stream)
- Pre-orders: PRE-ORDER pill and release date on the row, "N of M tracks available" (plus
  "Play available" when partially released) in the header; unreleased tracks greyed and
  non-playable by any gesture; only streamable tracks are ever queued
- Two-line rows (titles wrap, artist on a dimmed second line); selected row and playing track highlighted
- Sort (Recently added, Artist A–Z, Title A–Z, Release date) from the toolbar and a Hide pre-orders
  filter in the gear menu; both are remembered (`~/.local/state/omatimeatbandcamp/ui.json`)
- Shuffle: one On/Off icon in the footer transport, remembered per context (each album, each playlist,
  search results, whole library), with a small dot under the glyph while the current context is On;
  click the selected row again to deselect it and get back to the whole-library context
- Footer: Shuffle / Prev / Play-Pause / Next (no Stop), right-justified, a seekable progress bar with
  elapsed/total time, compact spacing between the now-playing text and the bar, two-line now-playing
  text, and a visible notice plus automatic skip when a stream fails. Track rows select on single-click
  and play on double-click; Enter and the footer also start playback. The detail header has no Play
  button (v3).
- Session-only Up Next queue: right-click for Play Next / Add to Queue (tracks) or Add to Queue
  (albums/playlists), shown above the context with Clear / Remove / play-now, and cleared by a shell
  restart or a new context; see [Queue](#queue).
- Refresh runs the backend sync in the background from the gear menu (cached library stays on screen);
  streams for Subsonic tracks are resolved by the backend (`backend play`), so stream URLs/credentials
  never appear in argv or logs
- Cached cover art: `backend art` fetches the current Subsonic cover, downscales it to <=128 px and
  writes `~/.cache/omatimeatbandcamp/current-art.jpg` for MPRIS; when stopped it writes the bundled
  BC placeholder. No cover URL ever reaches QML, the bar config or a log
- Collection link: opens the verified collection page with `xdg-open`; the username comes from the
  library cache, so no per-user URL is hardcoded
- MPRIS: `backend/mpris.py` publishes title/artist/album, a **local** `file://` cover URL,
  playback status, position and transport controls. mpv's `path` (the credential-bearing stream
  URL) is never read or published; our mpv runs with `--load-scripts=no` so the system
  `/etc/mpv/scripts/mpris.so` cannot publish it either. `OMATIME_MPRIS=0` disables the bridge.

## Data sources

- Library cache: `~/.cache/omatimeatbandcamp/library/library.json`, written by `python3 backend sync`
  (web collection feed via your browser session + Subsonic `getAlbumList2`/`getAlbum`/`getPlaylist`)
- Subsonic credentials: `~/.config/omatimeatbandcamp/credentials.toml` (`user`, `pass`)
- Browser session: imported by `cookies.py` (gitignored) into `~/.cache/omatimeatbandcamp/cookies.txt`
- Cached cover: `~/.cache/omatimeatbandcamp/current-art.jpg` (local copy only; source is Subsonic `getCoverArt`)
- `fetch.py` (the v1 scraper) is no longer used by the UI

## IPC

- `omarchy-shell omatimeatbandcamp status`
- `omarchy-shell omatimeatbandcamp toggle` (opens the panel if closed, closes it if open)
- `omarchy-shell omatimeatbandcamp playPause|resume|pause|next|previous|stop|refresh`
- `omarchy-shell omatimeatbandcamp restartPlayer` (resets to stopped and quits mpv; the next Play uses `--load-scripts=no`)
- `omarchy-shell omatimeatbandcamp seek <seconds>`
- `omarchy-shell omatimeatbandcamp play <itemId>` (the library id, e.g. a Subsonic album id like `a:4039254352` or `pl:783164`)
- `omarchy-shell omatimeatbandcamp clearCookies`

## Notes

- Data stays local. Cookie jar and cache are never committed (see `.gitignore`).
- Stream URLs are time-limited; the library refreshes on an interval.
- This is for personal use; respect Bandcamp ToS.

## Backend (v2, in progress)

`backend/` is the data and playback layer; QML invokes its CLIs and the MPRIS daemon.

- `backend/subsonic.py`: Subsonic client for `bandcamp.com/api/subsonic` (token auth, fresh salt per session, JSON and XML errors,
  secrets never logged). Credentials: `~/.config/omatimeatbandcamp/credentials.toml` (`user`, `pass`).
- `backend/model.py`: Album/Track/Playlist. Explicit per-track `streamable` + reason; declared vs returned track counts; pre-order fields;
  never pads or substitutes tracks.
- `backend/match.py`: matches the web collection to Subsonic by normalised artist+title, and single-track purchases via their parent album.
- `backend/library.py`: local cache (`~/.cache/omatimeatbandcamp/library/`) plus background, incremental sync.
  CLI: `python3 backend sync | status | summary | art`.
- `backend/mpris.py`: MPRIS D-Bus bridge. Reads only the whitelisted playback state file, builds
  `mpris:artUrl` from the local cover path, and sends transport commands through the plugin IPC.
- Tests: `python3 -m unittest discover -s tests -t .` (offline); `tests/qml/run.sh` (QML window interaction tests, offscreen); `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures` (real services).
- Measurements and findings: `spike/SUBSONIC-REPORT.md`.

