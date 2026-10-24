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

## Bar art module

Omarchy's current shell is Quickshell, not Waybar, so the art is a companion bar
widget instead of a Waybar `image` module. Its source lives in `bar-art/`; install
it as a sibling plugin and put its id immediately before the BC id in
`~/.config/omarchy/shell.json`:

```sh
ln -s ~/.config/omarchy/plugins/com.github.dtotheatothevtothee.omatimeatbandcamp/bar-art \
      ~/.config/omarchy/plugins/com.github.dtotheatothevtothee.omatimeatbandcamp-art
```

The main plugin still emits `RTMIN+8` after every art write for a legacy Waybar
`image` module; Quickshell updates through its file watcher.

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
- Use the clear-session button in the panel header (or `clearCookies` over IPC) to
  delete the imported jar; the next refresh re-imports it.
- If your browser is not running or the keyring is locked, cookies may be
  unavailable; set `cookiePath` to a file you export yourself instead.

## Usage

- Left-click the bar item to open/close the panel (toggle from anywhere with
  `omarchy-shell shell toggle com.github.dtotheatothevtothee.omatimeatbandcamp`).
- Right-click the bar item to play/pause; middle-click goes to the next track.
- The module text is always `BC`. Playback state is only a suffix: `BC ❚❚` playing,
  `BC ▶` paused, plain `BC` stopped.
- The album-art module sits immediately left of `BC` and follows the current track.
- Panel has tabs for Collection and Playlists, a search box, and a now-playing bar.

## Features

- Browse Albums (collection) and Playlists; global search across albums and playlist tracks
- Library = the union of your Bandcamp collection and Bandcamp's Subsonic server (so owned albums whose
  pages Bandcamp no longer lists still show up and stream)
- Pre-orders: PRE-ORDER pill and release date on the row, "N of M tracks available" in the header, unreleased
  tracks greyed (no hover, not clickable, duration "—"); only streamable tracks are ever queued
- Two-line rows (titles wrap, artist on a dimmed second line); selected row and playing track highlighted
- Sort (Recently added, Artist A–Z, Title A–Z, Release date) and a Hide pre-orders filter; both are remembered
  (`~/.local/state/omatimeatbandcamp/ui.json`)
- Shuffle: one On/Off toggle, remembered per context (each album, each playlist, search results, whole library);
  click the selected row again to deselect it and get back to the whole-library context
- Footer: Prev / Play-Pause / Next (no Stop), a seekable progress bar with elapsed/total time, two-line now-playing
  text, and a visible notice plus automatic skip when a stream fails
- Refresh runs the backend sync in the background (cached library stays on screen); streams for Subsonic tracks
  are resolved by the backend (`backend play`), so stream URLs/credentials never appear in argv or logs
- Bar art: `backend art` fetches the current Subsonic cover, downscales it to <=128 px and writes
  `~/.cache/omatimeatbandcamp/current-art.jpg`; when stopped it writes the bundled BC placeholder.
  No cover URL ever reaches QML, the bar config or a log

## Data sources

- Library cache: `~/.cache/omatimeatbandcamp/library/library.json`, written by `python3 backend sync`
  (web collection feed via your browser session + Subsonic `getAlbumList2`/`getAlbum`/`getPlaylist`)
- Subsonic credentials: `~/.config/omatimeatbandcamp/credentials.toml` (`user`, `pass`)
- Browser session: imported by `cookies.py` (gitignored) into `~/.cache/omatimeatbandcamp/cookies.txt`
- Bar art: `~/.cache/omatimeatbandcamp/current-art.jpg` (local copy only; source is Subsonic `getCoverArt`)
- `fetch.py` (the v1 scraper) is no longer used by the UI

## IPC

- `omarchy-shell omatimeatbandcamp status`
- `omarchy-shell omatimeatbandcamp playPause|next|previous|stop|refresh`
- `omarchy-shell omatimeatbandcamp play <itemId>` (the library id, e.g. a Subsonic album id like `a:4039254352` or `pl:783164`)
- `omarchy-shell omatimeatbandcamp clearCookies`

## Notes

- Data stays local. Cookie jar and cache are never committed (see `.gitignore`).
- Stream URLs are time-limited; the library refreshes on an interval.
- This is for personal use; respect Bandcamp ToS.

## Backend (v2, in progress)

`backend/` is the new data layer; the QML UI does not use it yet.

- `backend/subsonic.py`: Subsonic client for `bandcamp.com/api/subsonic` (token auth, fresh salt per session, JSON and XML errors,
  secrets never logged). Credentials: `~/.config/omatimeatbandcamp/credentials.toml` (`user`, `pass`).
- `backend/model.py`: Album/Track/Playlist. Explicit per-track `streamable` + reason; declared vs returned track counts; pre-order fields;
  never pads or substitutes tracks.
- `backend/match.py`: matches the web collection to Subsonic by normalised artist+title, and single-track purchases via their parent album.
- `backend/library.py`: local cache (`~/.cache/omatimeatbandcamp/library/`) plus background, incremental sync.
  CLI: `python3 backend sync | status | summary | art`.
- Tests: `python3 -m unittest discover -s tests -t .` (offline); `tests/qml/run.sh` (QML window interaction tests, offscreen); `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures` (real services).
- Measurements and findings: `spike/SUBSONIC-REPORT.md`.

