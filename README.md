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

- Click the bar icon to open the panel (toggle from anywhere with
  `omarchy-shell shell toggle com.github.dtotheatothevtothee.omatimeatbandcamp`).
- Middle-click the bar icon to play/pause.
- Panel has tabs for Collection and Playlists, a search box, and a now-playing bar.

## Features

- Browse Albums (collection) and Playlists tabs
- Global search across albums and playlist tracks
- Shuffle modes: Off, Shuffle All, Shuffle Album, Shuffle Playlist
- Streams resolved from Bandcamp's player API (`/api/player/2/player_data_web`),
  played via a persistent idle mpv with optional cookie headers
- Album tracklists are fetched lazily on selection and cached in memory
- Local on-disk cache in `~/.cache/omatimeatbandcamp/`

## Data sources

- Collection list: `POST /api/fancollection/1/collection_items` (paginated)
- Playlists: `POST /api/fan_collection/1/playlists`
- Tracklists/streams: `POST /api/player/2/player_data_web`
- Account auto-detect: `GET https://bandcamp.com/settings` (`identities.fan`)

## IPC

- `omarchy-shell omatimeatbandcamp status`
- `omarchy-shell omatimeatbandcamp playPause|next|previous|stop|refresh`
- `omarchy-shell omatimeatbandcamp play <itemId>`
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
  CLI: `python3 backend sync | status | summary`.
- Tests: `python3 -m unittest discover -s tests -t .` (offline); `tests/qml/run.sh` (QML window interaction tests, offscreen); `OMATIME_LIVE=1 python3 -m unittest tests.test_live_fixtures` (real services).
- Measurements and findings: `spike/SUBSONIC-REPORT.md`.

