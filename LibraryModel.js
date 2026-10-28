.pragma library

// Pure helpers for the library the UI shows: adapt backend/library.py's cache
// (library.json) into UI items, sort/filter albums, format dates and durations.
// Nothing here touches the network or the disk.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var SORT_MODES = [
  { id: "added", label: "Recently added" },
  { id: "artist", label: "Artist A–Z" },
  { id: "title", label: "Title A–Z" },
  { id: "release", label: "Release date" }
]

// v3.3.1 follow-up: the Playlists tab gets its own reduced sort. Playlists
// carry no purchased/release timestamp, so "added" is the library's source
// order (the order Subsonic returned, which the cache preserves). Verified
// against the real library: it is not alphabetical.
var PLAYLIST_SORT_MODES = [
  { id: "added", label: "Recently added" },
  { id: "title", label: "Title A–Z" }
]

function sortLabel(mode) {
  for (var i = 0; i < SORT_MODES.length; i++) if (SORT_MODES[i].id === mode) return SORT_MODES[i].label
  return SORT_MODES[0].label
}

function validSort(mode) {
  for (var i = 0; i < SORT_MODES.length; i++) if (SORT_MODES[i].id === mode) return true
  return false
}

function validPlaylistSort(mode) {
  for (var i = 0; i < PLAYLIST_SORT_MODES.length; i++) if (PLAYLIST_SORT_MODES[i].id === mode) return true
  return false
}

// "27 Nov 2026" (UTC, so the date does not shift with the local zone)
function fmtDate(ts) {
  if (!ts) return ""
  var d = new Date(ts * 1000)
  return d.getUTCDate() + " " + MONTHS[d.getUTCMonth()] + " " + d.getUTCFullYear()
}

// Clock format for the footer progress bar: m:ss, or h:mm:ss past an hour.
function fmtClock(sec) {
  var n = Number(sec)
  if (!isFinite(n) || n < 0) return "0:00"
  var t = Math.floor(n + 0.5)
  var h = Math.floor(t / 3600)
  var m = Math.floor((t % 3600) / 60)
  var r = t % 60
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
  return m + ":" + (r < 10 ? "0" : "") + r
}

function fmtDuration(sec) {
  if (!sec) return ""
  var s = Math.round(sec)
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}

// ---- adapters --------------------------------------------------------------------------

function adaptTrack(t, base, i) {
  return {
    uid: base + "#" + i,
    title: t.title || "",
    artist: t.artist || "",
    album: t.album || "",
    track_num: t.track_number || 0,
    duration: t.duration || 0,
    streamable: t.streamable === true,
    reason: t.streamable_reason || "",
    subsonicId: t.subsonic_id || "",
    subsonicAlbumId: t.subsonic_album_id || "",
    coverArtId: t.cover_art_id || "",
    bandcampId: t.bandcamp_id || ""
  }
}

function albumUid(a) {
  return a.subsonic_id || (a.bandcamp_id ? "bc:" + a.bandcamp_id : a.key)
}

function adaptAlbum(a) {
  var uid = albumUid(a)
  var tracks = []
  var src = a.tracks || []
  for (var i = 0; i < src.length; i++) tracks.push(adaptTrack(src[i], uid, i))
  var streamable = 0
  for (var j = 0; j < tracks.length; j++) if (tracks[j].streamable) streamable++
  return {
    uid: uid,
    id: uid,
    type: "album",
    kind: a.kind || "album",
    title: a.title || "",
    artist: a.artist || "",
    subsonicId: a.subsonic_id || "",
    coverArtId: a.cover_art_id || "",
    tracks: tracks,
    tracksLoaded: a.tracks_loaded === true,
    isPreorder: a.is_preorder === true,
    releaseDate: a.release_date || "",
    releaseTs: a.release_ts || 0,
    year: a.year || 0,
    purchasedTs: a.purchased_ts || 0,
    streamableCount: streamable,
    totalCount: tracks.length,
    declaredCount: a.declared_track_count === null || a.declared_track_count === undefined ? tracks.length : a.declared_track_count,
    completeness: a.completeness || "unloaded",
    sources: a.sources || [],
    bandcampUrl: a.bandcamp_url || ""
  }
}

function adaptPlaylist(p) {
  var tracks = []
  var src = p.tracks || []
  var base = "pl:" + p.id
  for (var i = 0; i < src.length; i++) tracks.push(adaptTrack(src[i], base, i))
  return {
    uid: p.id,
    id: p.id,
    type: "playlist",
    name: p.name || "",
    title: p.name || "",
    tracks: tracks,
    tracksLoaded: p.tracks_loaded === true,
    declaredCount: p.declared_track_count === null || p.declared_track_count === undefined ? tracks.length : p.declared_track_count,
    totalCount: tracks.length
  }
}

function adaptLibrary(json) {
  var albums = []
  var playlists = []
  var as = json.albums || []
  for (var i = 0; i < as.length; i++) albums.push(adaptAlbum(as[i]))
  var ps = json.playlists || []
  for (var j = 0; j < ps.length; j++) playlists.push(adaptPlaylist(ps[j]))
  return { albums: albums, playlists: playlists }
}

// ---- sorting / filtering ----------------------------------------------------------------

function sortKey(s) {
  var k = String(s || "").toLowerCase()
  try { k = k.normalize("NFD").replace(/[\u0300-\u036f]/g, "") } catch (e) {}
  return k
}

function cmpStr(a, b) {
  var x = sortKey(a), y = sortKey(b)
  return x < y ? -1 : (x > y ? 1 : 0)
}

// Best known release moment, epoch seconds, or 0 when unknown: the page's release
// date (pre-orders) first, else 1 Jan of the earliest track year Subsonic reported.
function releaseKey(a) {
  if (a.releaseTs) return a.releaseTs
  if (a.year) return Date.UTC(a.year, 0, 1) / 1000
  return 0
}

function sortAlbums(albums, mode, hidePreorders) {
  var out = []
  for (var i = 0; i < albums.length; i++) if (!(hidePreorders && albums[i].isPreorder)) out.push(albums[i])
  var byTitle = function(a, b) { return cmpStr(a.title, b.title) || cmpStr(a.artist, b.artist) || cmpStr(a.uid, b.uid) }
  var cmp
  if (mode === "artist") {
    cmp = function(a, b) { return cmpStr(a.artist, b.artist) || byTitle(a, b) }
  } else if (mode === "title") {
    cmp = byTitle
  } else if (mode === "release") {
    // newest first; albums with no known release moment go last
    cmp = function(a, b) {
      var x = releaseKey(a), y = releaseKey(b)
      if (!x !== !y) return x ? -1 : 1
      return (y - x) || cmpStr(a.artist, b.artist) || byTitle(a, b)
    }
  } else {
    // "added": most recently added first
    cmp = function(a, b) {
      var x = a.purchasedTs || 0, y = b.purchasedTs || 0
      return (y - x) || byTitle(a, b)
    }
  }
  out.sort(cmp)
  return out
}

// Playlist sorting. "added" returns a copy in the library's existing source
// order; "title" sorts by name, case- and accent-insensitively, with the uid
// as a stable tie-break.
function sortPlaylists(playlists, mode) {
  var out = []
  var list = playlists || []
  for (var i = 0; i < list.length; i++) out.push(list[i])
  if (mode === "title") {
    out.sort(function(a, b) {
      return cmpStr(a.name || a.title, b.name || b.title) || cmpStr(a.id, b.id)
    })
  }
  return out
}

// Every streamable album track (the "whole library" playback context).
function libraryTracks(albums) {
  var out = []
  for (var i = 0; i < albums.length; i++) {
    var ts = albums[i].tracks
    for (var j = 0; j < ts.length; j++) if (ts[j].streamable) out.push(ts[j])
  }
  return out
}

function findByUid(list, uid) {
  if (!uid) return null
  for (var i = 0; i < list.length; i++) if (list[i].uid === uid) return list[i]
  return null
}
