# OmaTimeAtBandcamp v1.0.0-beta.1

**Your Bandcamp collection, in an Omarchy bar panel.**

This is the first public beta. It is feature-complete for everyday listening and
is now looking for testing across real desktops, screens and libraries.

## What it does

- Shows your **real Bandcamp collection and playlists** in an Omarchy bar panel,
  including purchases that no longer appear on the public web listing.
- Streams through **Bandcamp's official Subsonic API** and plays through mpv.
  No browser tab, no separate music app, no downloads.
- Imports your existing Bandcamp browser session automatically (Chromium family
  and Firefox), or uses a manual Netscape `cookies.txt`.
- Lists **pre-orders** with their release date and marks unreleased tracks
  clearly; only released, streamable tracks play.
- Global search across albums, playlists and tracks; sort by recently added,
  artist, title or release date; optional hide-pre-orders filter.
- Persistent Up Next queue with **Play Next** and **Add to Queue**, plus a full
  keyboard workflow and an in-panel shortcuts reference.
- MPRIS support for media keys through the plugin's own bridge — it publishes
  only playback state and track title/artist, does not use mpv-mpris, and never
  puts stream URLs on the bus — plus an optional pair of user-installed global
  binds (not shipped).
- Local-first credentials and cookies: nothing is sent anywhere except Bandcamp
  hosts, and no credential or cookie value is shown in the UI or logs.

## Beta: what we are looking for

This beta is specifically for **environment testing**. Please try it and report
what does not fit:

- **Resolutions and display scaling** — small laptop panels, 1440p/4K, fractional
  scale factors, multi-monitor setups, vertical bars.
- **Themes and fonts** — light and dark themes, different font families and
  sizes, unusual accent colours, high-contrast setups.
- **Library sizes** — very small collections, collections in the thousands, many
  playlists, and large pre-order sets.
- **Install and setup edge cases** — Flatpak/Snap browsers, locked keyrings,
  manual cookie files, revoked Subsonic pairs.

Include your Omarchy version, monitor resolution and scale, theme name, and
roughly how many albums are in your collection when reporting a layout issue.

## Install

```bash
omarchy plugin add https://github.com/gy9cd2bvr7-svg/omatimeatbandcamp.git --enable
```

Then follow the README's setup walkthrough: import the browser session, generate
a Subsonic pair under **Bandcamp → Fan Settings → Subsonic**, and save it in
`~/.config/omatimeatbandcamp/credentials.toml` (`0600`).

## Known limitations

- **Streaming only.** There is no download or offline mode. A working network
  connection and a valid Subsonic pair are required to play.
- **No downloads or library export.** The plugin plays from Bandcamp; it does not
  save audio files or copy your collection elsewhere.
- **Pre-orders list but do not play until release day.** Unreleased tracks are
  shown greyed out and cannot be queued or started. A partially released
  pre-order plays only the tracks Bandcamp has released.
- Playlist editing, downloads and a credentials-entry UI are not part of this
  beta.
- Very large collections are usable but the first sync can take a while;
  subsequent syncs are incremental.

## Where to file issues

Please use the GitHub issue tracker:

**https://github.com/gy9cd2bvr7-svg/omatimeatbandcamp/issues**

For setup failures, say which step failed (browser import, Subsonic pair, first
sync) and what the panel showed. **Never paste cookie values, Subsonic
credentials, stream URLs or screenshots containing them.** Redact first.

## Thanks

Built for Omarchy, and for buying music directly from the people who make it.
