# OmaTimeAtBandcamp — v2 Fix-Everything Spec

For: OpenCode (Qwen3-Coder) working in the existing OmaTimeAtBandcamp repo on oma.
Owner: David Sewall. Date: 2026-10-23.

## How to use this spec

1. Read the whole spec first. Then inspect the existing codebase and Waybar config
   before changing anything. Work inside the existing stack/language/framework —
   do not rewrite from scratch and do not switch UI frameworks.
2. **Phase -1 comes before everything.** Freeze the current working code in
   git and back it up to a PRIVATE GitHub repo before the first edit (details
   below). Commit after each phase with a message naming the phase, and push
   after each phase commit.
3. **Phase 0 is a hard gate.** Do the Subsonic spike first, write the report, and
   stop for David's go/no-go before doing the backend swap. UI fixes (Phases 2–6)
   may proceed regardless of the Phase 0 outcome.
4. Never put a credential in code, in this spec, in a commit, in a log, or in a
   fixture. See "Credentials" below — this includes the Subsonic password.
5. Every phase ends with its acceptance tests actually run and the results noted
   in the commit message or a `V2-NOTES.md` changelog. "It should work" is not done.

---

## Background (what exists today, verified from screenshots 2026-10-23)

- Waybar custom module showing the text `BC`; clicking it opens the plugin window.
- Plugin window titled `OmaTimeAtBandcamp`, with:
  - Header icons top-right: refresh (small ↻ glyph), clear-session (bracket/arrow),
    close (×) — all different sizes/styles from everything else.
  - Search box: "Search albums, playlists, tracks..."
  - Toolbar: `Albums (645)` · `Playlists (33)` · `Play all` · `Shuffle: Off`
    (shuffle cycles Off → All → Album/context → Playlist on repeated clicks).
  - Left pane: one-line album rows `Title • Artist`, hard-truncated mid-word.
  - Right pane: selected album title + track list with durations.
  - Footer: now-playing title/artist/album + transport (prev, play, stop, next).
    No progress bar, no seek, no elapsed/total time.
- Known bugs visible in the screenshots:
  - HTML entities are not decoded: a row renders literally as
    `Shamek Farrah &amp; Folks`.
  - No visible highlight for the selected album (left) or the playing track (right).
  - The Waybar `BC` text changes into a pause icon while playing.
- Known playback bug (owner-reported): on the pre-order album
  *First Impressions (Deluxe Edition)* by Shamek Farrah, clicking any track plays
  only the one released track, "First Impressions". The other tracks are listed
  with full durations as if playable. Root cause to confirm: Bandcamp only provides
  a stream for released tracks; the current queue builder appears to fall back to
  the album's featured/first-streamable track instead of treating the clicked
  track as unplayable.

Library size at spec time: **645 albums, 33 playlists** (one playlist,
"Postpunky?", has 213 tracks). Performance work must be tested at this size.

---

## Phase -1 — Freeze v1: git + PRIVATE GitHub backup (do first, before any edit)

The owner has a GitHub account but has never created a repository or used git
for a project. OpenCode does ALL of this; the owner's only manual step is the
one-time `gh` browser login if prompted. Explain each result in plain language
in the Phase -1 report — no unexplained jargon.

1. **Locate the code.** Find the existing OmaTimeAtBandcamp project directory
   and the Waybar config entries that launch it. Report the path, file list,
   and total line count (this doubles as the start of the v1 audit: note how
   fetching, playback and UI are organised — separate modules or one file).
2. **Check the tools.** `git --version`, `gh --version`,
   `gh auth status`. If `gh` is missing, install it
   (`sudo pacman -S --needed github-cli` — pause and ask the owner for the
   sudo password; never guess it). If `gh` is not logged in, run
   `gh auth login` (GitHub.com, HTTPS, login with browser) and pause for the
   owner to complete it in the browser. Do not proceed until
   `gh auth status` is clean.
3. **Secrets sweep BEFORE the first commit — critical.** The current plugin
   keeps a logged-in Bandcamp session somewhere (cookies/session file) and
   may have cache or credential files inside the project folder. Inventory
   the folder for anything like: cookie/session files, `credentials*`,
   `.env*`, token files, library caches, logs, downloaded art. Write a
   `.gitignore` covering all of them (plus `__pycache__/`,
   `~/.cache`-style artefacts and `*.log`) BEFORE `git add` is ever run.
   A committed Bandcamp session cookie is account access — treat any such
   file as a credential under this spec's credential rules.
4. **Initialise and freeze.** `git init` (if not already a repo), set the
   local commit identity using the GitHub **noreply** email for the account
   (`<id>+<username>@users.noreply.github.com`, from `gh api user`) so the
   owner's real email is not published in commit history. Stage, review
   `git status` and the staged file list line by line against the secrets
   sweep, then make the first commit: `v1: freeze working plugin as-is`.
   Tag it: `git tag v1-working`. Do not refactor, rename or "tidy" anything
   in this commit — it must be a byte-for-byte snapshot of the working v1.
5. **Create the GitHub repo — PRIVATE, and verify it.** 
   `gh repo create omatimeatbandcamp --private --source=. --remote=origin --push`
   then confirm with `gh repo view --json visibility` that visibility is
   `PRIVATE` and report the result to the owner. If it is not PRIVATE, stop
   and fix that before pushing anything else. Never make this repo public,
   and never change its visibility, without the owner's explicit say-so in
   that moment.
6. **Branch for the work.** Create and push branch `v2`
   (`git switch -c v2; git push -u origin v2`). All spec phases happen on
   `v2`; `main` stays at the frozen v1 until v2 passes the full acceptance
   checklist, when the owner will be asked before any merge.
7. **Phase -1 report** (in `V2-NOTES.md` and summarised to the owner):
   repo URL, visibility = PRIVATE confirmation, tag name, project path,
   file/line counts, what was git-ignored and why, and the audit note from
   step 1 — including a straight answer to: is a clean v2 folder alongside
   v1 (porting the proven fetcher/player code) practical, or is the code
   separable enough to refactor in place? Recommendation, no action yet.

Rollback at any later point = `git switch main` (or re-point Waybar at the
frozen v1) — v1 must keep working untouched throughout.

---

## Phase 0 — Subsonic spike (GATE — report before building on it)

Bandcamp now runs an official Subsonic/OpenSubsonic API server (open beta):

- Server URL: `https://bandcamp.com/api/subsonic`
- Credentials: generated by the user in Bandcamp → Fan Settings → Subsonic.
  This is a dedicated, revocable app-style username/password pair. It is **not**
  the user's Bandcamp account password. Never ask the user to paste it into chat,
  a prompt, or this project. The user enters it once, locally, into the config
  location defined under "Credentials".
- Bandcamp's stated supported clients are Amperfy, Feishin and Submariner, and
  its stated scope is: stream/download your collection, and create/edit
  playlists (edits show up in Bandcamp on web/app too). Beta warning from
  Bandcamp: "things might be a little slow if you have a big collection" —
  this collection has 645 albums, so measure it.

### Credentials

- Read from, in priority order:
  1. Environment: `OMATIME_SUBSONIC_USER`, `OMATIME_SUBSONIC_PASS`
  2. `~/.config/omatimeatbandcamp/credentials.toml` (create with mode `0600`,
     directory `0700`, and verify/refuse if permissions are looser)
- Auth: prefer Subsonic token auth — per request generate a random salt `s`,
  send `u=<user>`, `t=md5(password + salt)`, `s=<salt>`, `v=1.16.1`,
  `c=OmaTimeAtBandcamp`, `f=json`. Test whether Bandcamp accepts token auth.
  Only if `ping` proves it unsupported may you fall back to `p=enc:<hex>`, and
  record that fact in the spike report.
- Redact credentials, tokens and signed stream URLs from ALL logs and from the
  spike report.

### Spike script (standalone, throwaway is fine, e.g. `spike/subsonic_probe.py`)

Call and record status, item counts, field names, and timings for:

1. `ping.view` — auth works? Server version / type / OpenSubsonic extensions
   (`getOpenSubsonicExtensions` if offered — record, don't assume).
2. `getAlbumList2.view?type=newest&size=10` and a full paged pull
   (`size=500`, `offset=`) — total album count vs. the known 645.
3. `getPlaylists.view` — count vs. the known 33; then `getPlaylist.view` for
   "Postpunky?" — track count vs. the known 213.
4. `getAlbum.view` for *First Impressions (Deluxe Edition)* — Shamek Farrah.
   **The critical test.** Record: how many tracks are returned (7 expected in
   the current UI)? Do the unreleased tracks appear at all? Is there any field
   distinguishing them (missing duration? a flag? stream attempt result)?
   Attempt `stream.view` on one unreleased track and on "First Impressions"
   and record the HTTP result for each (do not download whole files — a
   ranged/HEAD-style probe or the first bytes is enough).
5. `getCoverArt.view?id=<coverArt id from an album>` — does it return art?
   What sizes are available (`size=` param)? 
6. `search3.view?query=Shamek` — sanity: search works across albums/artists/songs.
7. One normal album end-to-end: pick any fully released album, list tracks,
   confirm every track streams, note the stream content-type/bitrate.

### ⚠️ Request-shape correction (learned the hard way, 2026-10-23)

The ONLY confirmed-working request shape (proven by `test_credentials.py`,
whose ping succeeded) is the standard one used above: the method goes in
the URL path — `https://bandcamp.com/api/subsonic/rest/<method>.view` —
with `f=json` as a query parameter meaning *response format*. A previous
probe attempt treated the value of `f` as the method name, producing
`/rest/json` URLs and Bandcamp replies of `{"error": true,
"error_message": "bad version"}`, then misdiagnosed this as a version
problem. If you see "bad version", check the URL path first. Also: use a
fresh random salt per session (never a hardcoded one), and NEVER print
`u`, `t`, or `s` values in output or logs.

Confirmed by that working ping: server type `BandcampServer`, API
version `1.16.1`, OpenSubsonic extensions present (`openSubsonic: true`).

⚠️ Trust warning: on 2026-10-23 a SUBSONIC-REPORT.md was written BEFORE
any successful measurement, and its "actual" numbers simply mirrored the
expected values in this spec (645, 33, "12 tracks", invented timings).
That report is void. Only report numbers accompanied by the raw
responses that produced them.

### Spike report — `spike/SUBSONIC-REPORT.md` must answer

- Token auth: yes/no. API version + server type string.
- Counts: albums ___ / 645, playlists ___ / 33, Postpunky? tracks ___ / 213.
- Pre-order behaviour: unreleased tracks absent / present-but-flagged /
  present-and-indistinguishable. Stream attempt result for each case.
- Cover art: available? id field name? usable sizes?
- Speed: time to pull the full album list and one full playlist.
- Playlist write: NOT to be tested against the real account in the spike
  (no create/edit/delete calls without the user's explicit OK later).
- Recommendation, one of:
  - **A — Subsonic primary:** library, playlists, search, streams and art all
    come from Subsonic. The old session/cookie scraping is deleted.
  - **B — Hybrid:** Subsonic for library/playlists/art/streams, PLUS the
    existing Bandcamp page data (`data-tralbum`) kept only to obtain
    `album_is_preorder` / `is_preorder` / `album_release_date` / per-track
    stream availability, IF the spike shows Subsonic can't express pre-orders.
  - **C — Stay on scraping:** Subsonic is missing something essential
    (say exactly what). UI phases still proceed.

STOP after the report. The user picks A / B / C.

### ✅ Phase 0 RESULTS (measured 2026-10-23, Sonnet 5.5 run, commit f2f6242 on v2)

- Server: BandcampServer, API 1.16.1, `openSubsonic: true` — but ZERO
  OpenSubsonic extensions are actually listed. Don't rely on extensions.
- **Albums: 687 via API vs 645 via the scrape.** Unique IDs; same total in
  one unpaged request, so not a paging artefact. The +42 is UNEXPLAINED —
  a coverage diff (normalised artist+title, both directions) is required
  before the backend build; do not assume either source is a subset.
- Playlists: 33 ✓. "Postpunky?" = **234 tracks** (the 213 figure is stale;
  the playlist changed 2026-10-23 14:56).
- *First Impressions (Deluxe Edition)*: absent from album list, search,
  artist page, and playlist membership — **the API never mentions it.**
  Pre-orders are invisible to Subsonic, confirmed at API level.
- *La Dee La La*: present under artist "Shamek Farrah & Folks", **4
  tracks**, all stream. (The earlier "12 tracks" was fabricated.)
- Search quirk: searching an artist name finds the artist but returns NO
  albums in the results — do not use search3 for album lookup; use
  getAlbumList2 / getArtist.
- Cover art: works via redirect to bcbits.com (JPEG), but the `size`
  parameter is IGNORED — always the full-size image (~159 KB in the
  test). The plugin must downscale and cache locally (dropdown thumbs,
  32px Waybar art).
- Streaming: works, Range requests supported. All 234 Postpunky? tracks
  stream.
- Track-count trap: getAlbum can return FEWER tracks than the album's
  declared count — two compilations returned 103/500 and 95/100
  (that is the entire 6,378-declared vs 5,976-returned gap). Never trust
  the declared count; count what you got. Two albums have 0 tracks
  ("TERMINALS", "White Boy and the Average Rat Band") — must render
  gracefully.
- Errors arrive as XML even when `f=json` is requested — the client must
  parse BOTH formats.
- Timings: full album list ~0.7 s; Postpunky? pull ~0.5 s; pulling tracks
  for ALL albums = 687 calls ≈ 95 s. Track-level sync is a background
  job against a local cache, never a blocking load.
- **Decision: B (Hybrid) CONFIRMED.** Scrape stays the library of record
  for pre-orders; Subsonic supplies streams, playlists and art where the
  album exists in both. The +42 coverage diff is Phase 1's first task.

### ✅ Phase 1 RESULTS (measured 2026-10-23, Sonnet 5.5, commits 31a217c + d9f9d20)

- **+42 reconciled exactly.** Web list 645 = 609 albums + 36 single
  tracks. Subsonic-only: +47 (43 Macroblank albums sharing one
  timestamp + 4 others — best explanation, labelled inference: the web
  feed drops items whose artist pages are gone; ALL 47 stream).
  16 single-track purchases map to 12 Subsonic parent albums: −4.
  Pre-order missing from Subsonic: −1. Net +42. **Design consequence:
  the library is a UNION of both sources**, not scrape-only — Subsonic-
  only albums are real, owned, streamable library items. Match rate:
  644 of 645 web items matched (99.8%); sole miss = the pre-order.
- Backend client `backend/subsonic.py`: JSON errors, XML errors, and
  empty HTTP 500s all handled; fresh salt per session; credentials
  never logged (cache-write guard refuses to persist them).
- Data model: explicit per-track `streamable` flag WITH a reason;
  declared vs returned counts kept separate; truncated (103/500,
  95/100) and empty albums represented as returned; featured tracks
  never read; entities decoded everywhere (v1 cache had them in 4
  titles, incl. "Shamek Farrah & Folks").
- Sync: cold ≈ 94 s (web feed is the bottleneck, ~30 sequential
  requests), incremental ≈ 31 s, cache read ≈ 120 ms offline.
- ⚠️ **Auth caveat:** Subsonic `ping` returns OK even with WRONG
  credentials — ping proves nothing about auth. A real `check_auth()`
  (authenticated call) exists; use it everywhere a check is needed.
- Tests: 54 offline pass (5 skipped), 5 live fixture checks pass, with
  the First Impressions live test asserting the measured 0-of-7 (see
  the corrected Phase 4 fixture).

### Preliminary finding (2026-10-23, owner-reported from Feishin — confirmed check)

The user connected Feishin to Bandcamp's Subsonic server with his generated
credentials. Other collection albums appear in Feishin, but
*First Impressions (Deluxe Edition)* by Shamek Farrah — the pre-order fixture
album — **does not appear at all**. The distinguishing check has since been
run: *La Dee La La* by Shamek Farrah & Folks, a fully released album by the
same artist, **does** appear in Feishin. So this is specific to the
pre-order album, not an artist/index/sync gap. (A raw `getAlbumList2` probe
in the spike should still confirm it at API level, but design for the
outcome below.)

- With the pre-order album absent from Subsonic while *La Dee La La* is
  present, **option A (Subsonic-only) is ruled out**:
  a Subsonic-only library would silently lose pre-order albums the user
  owns. The decision defaults to **B — Hybrid**, with this shape:
  - The existing Bandcamp collection source remains the library of record
    (it is what lists all 645 albums, including pre-orders, with
    pre-order/release-date/tracklist data).
  - Subsonic is used where the album exists in both sources: streams,
    playlists, and cover art.
  - Albums/tracks missing from Subsonic (pre-orders) keep the existing
    Bandcamp-page stream path for their released tracks, with the
    Phase 1/Phase 4 streamable-flag and greyed-track treatment.
  - Match albums across sources by normalised artist + title; log
    unmatched albums (count only) so coverage is measurable
    ("N of 645 albums available via Subsonic").
- If a raw API probe shows the album IS in Subsonic and Feishin was at
  fault, record that and A stays on the table.

---

## Phase 1 — Data model fixes (backend, whichever source wins Phase 0)

1. **Decode HTML entities everywhere** on ingest (`&amp;` → `&`, `&#39;` → ', etc.).
   Acceptance: the library contains "Shamek Farrah & Folks", and a library-wide
   scan finds no literal `&amp;`, `&quot;`, `&#` strings in any title/artist field.
2. **Every track gets an explicit `streamable: bool`.**
   - From page data: a track is streamable only if it has an actual stream URL
     (the trackinfo entry's file/stream field is present and non-null).
   - From Subsonic: use the spike's findings; if indistinguishable there, the
     hybrid tralbum check supplies it.
   - No code path may substitute a different track when the requested track is
     not streamable. Remove any featured-track / first-track fallback.
3. **Albums get `is_preorder: bool`, `release_date` (if known), and
   `streamable_track_count` / `total_track_count`.** Source fields in Bandcamp
   page data: `album_is_preorder`, `is_preorder`, `album_release_date`.
4. **Queue building uses streamable tracks only**, starting at the clicked
   track, in album/playlist order (or shuffled, Phase 3). Clicking a
   non-streamable track does nothing except show the notice in Phase 4.
5. Cache the library locally (as today, if a cache exists) and make Refresh a
   background job that does not block or blank the UI; show a spinner on the
   Refresh button and a "Library updated · N albums" status line/toast on
   completion. A pre-order whose release date has passed must clear its
   pre-order state on refresh.

## Phase 2 — Header and window chrome

1. One button style for ALL controls: a single shared class/style —
   same height, same padding, same border/radius, same icon size (16px),
   same hover/active states. No control may be a bare text glyph in a corner.
2. **Remove the × close button.** Esc and click-outside already close the
   window; verify both still work after removal.
3. **Remove the clear-session icon from the header.** Replace with a labelled
   item "Log out / Clear Bandcamp session" inside a single overflow (⋯) menu,
   behind a confirmation prompt. (If Phase 0 lands on Subsonic-primary, this
   becomes "Remove saved Subsonic credentials" and deletes the credentials
   file instead — same menu slot, same confirmation.)
4. **Refresh** becomes a normal toolbar button (Phase 2.1 style), labelled
   with the refresh icon + "Refresh", placed with the other toolbar controls,
   disabled + spinning while a refresh runs.

## Phase 3 — Toolbar: kill Play all, fix Shuffle

1. **Delete the `Play all` button entirely.** Playback scope is the current
   context (selected album, selected playlist, or whole library).
2. **Replace the cycling Shuffle button** (Off → All → Album → Playlist…)
   with a single toggle: `Shuffle: On` / `Shuffle: Off`, visually highlighted
   when On. It applies to the current context. There is no cycle-through-states
   control anywhere in the UI after this change.
3. Keep `Albums (N)` / `Playlists (N)` as the view switch, same style/height
   as every other toolbar button, counts still live.

## Phase 4 — Lists, wrapping, pre-order presentation

0. **Deselect** (owner-approved addition, 2026-10-23; added after Phase 3 showed the
   whole-library context was unreachable once any row had been clicked). Clicking the
   currently selected album or playlist row again **deselects** it and returns the UI
   to the whole-library context. Selection state, the detail pane and the Shuffle
   context (Phase 3: per-context state) must all follow: after deselect the detail
   pane shows the empty prompt, Shuffle shows the library context's own state, the row
   highlight is gone, and the album/playlist's own Shuffle state is remembered for
   when it is selected again. Clicking a *different* row moves the selection.
1. **Two-line rows in the left pane.** Line 1: album/playlist title, wrapping
   to a maximum of 2 lines, ellipsis only after line 2. Line 2: artist name,
   smaller, dimmed. No mid-word single-line truncation anywhere.
2. Right pane header uses the same two-line treatment
   (title wraps, artist on its own dimmed line). Track titles in the right
   pane wrap instead of truncating.
3. **Selected states:** the selected album/playlist row is visibly
   highlighted; the currently playing track row is highlighted with a small
   playing indicator. Both states must be visible in the screenshots used
   for acceptance.
4. **Pre-order rendering:**
   - Album row: a `PRE-ORDER` tag/pill plus release date if known.
   - Right pane header: `PRE-ORDER · releases <date>` and
     `<streamable> of <total> tracks available`.
   - Unreleased tracks: ~45% opacity, no hover effect, not clickable,
     duration shown as `—`, and a click (if it registers at all) only shows
     a "Not yet released" notice.
   - The album's play control reads "Play available" when
     `streamable_track_count < total_track_count`.
   Fixture for all of the above: *First Impressions (Deluxe Edition)* —
   Shamek Farrah. CORRECTED 2026-10-23 (Phase 1 measurement): the album
   page marks ALL 7 tracks unreleased with no stream file; streaming
   starts at release, **27 Nov 2026**. Expected: **0 of 7 playable**, all
   7 greyed, "0 of 7 available" until release. (The original "1 of 7"
   came from v1's behaviour — clicking any track played the single —
   which was the featured-track substitution bug itself, not a source
   saying one track is legitimately streamable. Separately noted:
   Bandcamp's player API currently serves full-length audio for all 7
   tracks even anonymously — an enforcement gap. DECIDED by the owner
   2026-10-23: streamable follows the PAGE. That gap is documented,
   never built on.)
5. **Sorting/filtering for a 645-album library:** sort menu —
   Recently added (current default), Artist A–Z, Title A–Z, Release date.
   Plus a toggle filter "Hide pre-orders". Persist the choice.

## Phase 5 — Footer transport and now playing

1. Transport buttons ⏮ ▶/⏸ ⏭: identical size/style (Phase 2.1 class),
   centred in the footer.
2. **Play toggles to Pause while playing** (same button, icon + tooltip
   follow state). **Remove the Stop ■ button** — pause is sufficient for
   streamed playback; if the playback backend genuinely needs a stop to
   release the stream, map it to a long-press/right-click on pause, not a
   fourth button.
3. **Add a progress bar** under (or above) the transport row: elapsed /
   total time labels, click-to-seek and drag-to-seek if the backend reports
   position; if the backend cannot seek a stream, show a determinate
   progress bar anyway and note the limitation in V2-NOTES.md.
4. Now-playing text uses the two-line treatment: track title (wraps, max
   2 lines), then `Artist · Album` dimmed on line 2.
5. A failed stream shows a visible error notice in the footer
   ("Couldn't play <title> — skipped") and advances the queue. Silent
   substitution or silent failure are both regressions.

## Phase 6 — Waybar module

1. The module text is **always `BC`**. It never changes into a play/pause
   icon. Playback state is shown as a suffix: `BC ❚❚` while playing,
   `BC` (optionally `BC ▶`) while paused/stopped.
2. Clicks: left-click opens/closes the plugin window (as today);
   right-click toggles play/pause; middle-click next track (optional,
   document if implemented).
3. **Album art (separate Waybar `image` module, placed immediately left of
   the BC module):**
   - Source of art: Subsonic `getCoverArt` if Phase 0 = A/B, otherwise the
     album's Bandcamp art (`art_id` → Bandcamp image CDN).
   - On every track change, the plugin writes the current cover to
     `~/.cache/omatimeatbandcamp/current-art.jpg`, downscaled to ≤128px,
     and signals Waybar to refresh the image module
     (`pkill -RTMIN+<n> waybar` — pick an RTMIN number not already used by
     other Omarchy modules; check the existing config first).
   - Example config shape (adapt to the existing config/style, don't
     overwrite the user's Waybar setup wholesale):
     ```jsonc
     "image#omatime-art": {
       "path": "~/.cache/omatimeatbandcamp/current-art.jpg",
       "size": 24,
       "signal": <n>,
       "on-click": "<same command that opens the plugin>"
     }
     ```
   - When playback stops, replace `current-art.jpg` with a bundled
     placeholder (the BC mark on a transparent/dark background). The art
     module must never show a broken-image icon.
   - Keep `BC` as the click target of record; art is decoration + status,
     not a replacement for it.

## Phase 7 — External links row

Add one row of uniform buttons (Phase 2.1 style) beneath the search box —
or, if space is tight, as labelled items in the ⋯ overflow menu.
Each opens with `xdg-open` in the user's default browser:

- **Bandcamp** — https://bandcamp.com
- **Discover** — https://bandcamp.com/discover
- **Editorials (Daily)** — https://daily.bandcamp.com
- **Radio** — VERIFY the live URL at implementation time (start from the
  Radio link on bandcamp.com) and record the verified URL in V2-NOTES.md.
  Do not guess.
- **Your Feed** — build from the logged-in username the plugin already
  knows; verify the URL in a logged-in browser session before shipping.
  Do not hardcode a guessed path.
- **Your Collection** — same rule: build from the known username
  (profile/collection page), verify before shipping.

## Phase 8 — Keyboard and MPRIS

1. Keyboard: ↑/↓ move within the focused list, Enter plays the selection,
   Space toggles play/pause (when not typing in search), `/` focuses
   search, Esc clears search first, then closes the window.
2. Expose playback over **MPRIS** (playerctl-compatible) if the playback
   backend allows: metadata title/artist/album, art URL pointing at the
   cached cover file, play/pause/next/previous, position if available.
   This makes the laptop's media keys work. If the backend makes MPRIS
   disproportionate, stop, note why in V2-NOTES.md, and leave media-key
   support as a documented TODO rather than half-implementing it.

## Acceptance checklist (all must pass before calling v2 done)

- [ ] Phase 0 spike report written; user picked A / B / C; backend matches it.
- [ ] No `&amp;` (or other entity) visible anywhere in the library UI.
- [ ] First Impressions fixture: 0 of 7 playable until 27 Nov 2026, all
      greyed with `—` durations, PRE-ORDER tag + "0 of 7 available" shown,
      and clicking any track never plays anything (corrected 2026-10-23 —
      see the Phase 4 fixture note).
- [ ] A fully released album: every track clickable, queue starts at the
      clicked track and continues in order.
- [ ] No × button; Esc and click-outside close the window.
- [ ] Clear-session / remove-credentials lives only in the ⋯ menu, with a
      confirmation, and actually works.
- [ ] All buttons in header, toolbar, links row and footer share one style
      and height. Screenshot-reviewed.
- [ ] No `Play all` button. Shuffle is a single On/Off toggle, highlighted
      when on, and audibly shuffles the current context only.
- [ ] Long title fixture (e.g. "Croc­brain, or, Two Big Steps For Mankind"
      by Ismatic Guru): title wraps to 2 lines, artist fully readable on
      line 2, nothing cut mid-word.
- [ ] Waybar shows `BC` at all times; suffix changes with state; the bar
      never shows a bare pause icon in place of `BC`.
- [ ] Waybar art module shows the playing album's cover, updates on track
      change without a Waybar restart, and shows the placeholder (never a
      broken image) when stopped.
- [ ] Footer shows progress + elapsed/total; play button flips to pause
      while playing; a forced stream failure shows the error notice.
- [ ] All six external links open the correct pages (Feed/Collection on the
      user's own account), verified URLs noted in V2-NOTES.md.
- [ ] Full-library load/refresh at 645 albums / 33 playlists does not block
      the UI; playlist "Postpunky?" loads all 213 tracks.
- [ ] No credentials, tokens, or signed stream URLs in the repo, logs, or
      notes. Credentials file is `0600`.

## Out of scope

- Downloading/ripping tracks beyond what the Subsonic API itself offers to
  the account holder; no DRM or play-cap circumvention.
- Editing playlists from inside the plugin UI (Subsonic playlist *writes*
  are a later version, and need the user's explicit OK first).
- A settings UI for credentials — a documented config file is enough.
- Publishing the plugin anywhere.

## Starter prompt (paste into OpenCode on oma)

> Read `omatimeatbandcamp-v2-spec.md` in full. Start with Phase -1 only:
> set up git for this project and freeze the current working version —
> secrets sweep and `.gitignore` BEFORE the first commit (this plugin
> stores a Bandcamp session; no cookies/credentials/caches may ever be
> committed), tag it `v1-working`, create a PRIVATE GitHub repo with `gh`,
> verify the visibility is PRIVATE, push, and branch `v2`. I've never used
> git or GitHub for a project before, so explain what you did in plain
> language, and pause if you need me for the `gh` browser login or a sudo
> password. Then stop and give me the Phase -1 report, including your audit
> of the code and your recommendation: build v2 alongside v1 and port the
> working parts, or refactor in place on the `v2` branch. Do not start
> Phase 0 or edit any plugin code until I say go.


---

## Addendum 2026-10-23 — Phase -1R: cookie incident remediation (supersedes Phase -1 status)

Phase -1 executed, but the verification pass found the failure Phase -1 was
designed to prevent: `cookies.py` contains the real Bandcamp session cookies
hardcoded in source and was committed and pushed in the first commit, before
the `.gitignore` update. The repo is PRIVATE and sole-user and was only hours
old, and the session must be rotated, so remediation is delete-and-recreate,
NOT a history rewrite (filter-branch/BFG leave unreachable objects behind
and are error-prone; deletion + rotation is deterministic):

1. Delete the GitHub repo (`gh repo delete`), keeping the local tree.
2. Move the cookie VALUES out of source into
   `~/.config/omatimeatbandcamp/cookies.txt` (dir 0700, file 0600, OUTSIDE
   the repo). Rewrite `cookies.py` as a clean loader that reads that file
   and contains no secrets. Cookie values must never be printed in logs,
   chat, or reports. Verify the plugin still works locally with the
   external file before proceeding.
3. OWNER (manual): rotate the Bandcamp session — log out of Bandcamp and
   back in, and change the Bandcamp password for certainty. Then paste the
   FRESH cookies into the external file himself in a local editor (not into
   the agent chat). The agent may only verify success/failure of a test
   fetch afterwards, never read the values back.
4. Delete the local `.git`, re-initialise, secrets-sweep the full tree
   (including a content scan for cookie names/values patterns), THEN the
   clean v1 freeze commit, tag `v1-working`, recreate the PRIVATE repo,
   verify visibility, push `master` + `v2`.
5. Final verification: `git log --all --name-only` and a history content
   scan show no cookie/credential material anywhere; report filenames and
   counts only.

Architecture confirmed by the Phase -1 audit (use it in later phases):
Python backend — `fetch.py` (Bandcamp fetching), `mpvctl.py` (playback IS
mpv, so position/seek/MPRIS are in scope), `cookies.py` (session, see
above); QML UI — `Panel.qml`, `Service.qml`; `Model.js` — data model.
