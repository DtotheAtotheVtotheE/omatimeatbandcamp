import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Shared state for the OmaTimeAtBandCamp bar widget and panel.
//
// Settings live in the plugin's entry in ~/.config/omarchy/shell.json (written
// by the standard settings form), falling back to the manifest defaults.
// Library data is cached on disk by fetch.py; this service reads the cache,
// refreshes it on an interval, and drives mpv through mpvctl.py.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  // Resolve this file's own directory so the plugin works from any install
  // location (local or store-provided id/path) rather than a hardcoded path.
  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("Service.qml"))
    if (u.indexOf("file://") === 0) u = u.substring(7)
    return u.substring(0, u.lastIndexOf("/"))
  }
  readonly property string cacheDir: home + "/.cache/omatimeatbandcamp"
  readonly property string shellConfigPath: home + "/.config/omarchy/shell.json"

  // Path to the Netscape cookies.txt used for authenticated requests. When the
  // user has not set a manual cookiePath, refresh() exports it from the browser.
  property string cookiePath: cacheDir + "/cookies.txt"


  // ---- settings -----------------------------------------------------------
  property var settings: ({})

  function defaultSettings() {
    return {
      showIcon: true,
      userUrl: "",
      cookiePath: "",
      browser: "auto",
      includePlaylists: true,
      refreshIntervalMin: 15,
      autoPlayOnSelect: false,
      mpvFlags: ""
    }
  }

  function loadSettings() {
    var merged = defaultSettings()
    try {
      var parsed = JSON.parse(shellCfg.text() || "{}")
      var layout = parsed.bar && parsed.bar.layout ? parsed.bar.layout : ({})
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var arr = layout[sections[s]] || []
        for (var i = 0; i < arr.length; i++) {
          var entry = arr[i]
          if (entry && entry.id === "com.github.dtotheatothevtothee.omatimeatbandcamp") {
            for (var k in entry) {
              if (k === "id") continue
              merged[k] = entry[k]
            }
          }
        }
      }
    } catch (e) {
    }
    settings = merged
  }

  FileView {
    id: shellCfg
    path: root.shellConfigPath
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.loadSettings()
    onTextChanged: root.loadSettings()
  }

  // ---- library ------------------------------------------------------------
  property var collection: []
  property var playlists: []
  // Which list the window shows: 0 = Albums, 1 = Playlists. Must be declared here:
  // Panel reads and assigns it, and an undeclared property silently drops the
  // assignment (the Albums/Playlists switch did nothing before this).
  property int activeTab: 0
  property var searchResults: ({ albums: [], tracks: [] })
  property string searchQuery: ""
  property string detectedUser: ""
  property string status: ""
  property string lastUpdated: ""
  // True from the moment Refresh starts (browser-session import, then fetch)
  // until the fetch process exits; drives the toolbar Refresh button.
  readonly property bool refreshing: fetchProc.running || cookiesProc.running

  FileView {
    id: collectionFile
    path: root.cacheDir + "/collection.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.loadCollection()
    onTextChanged: root.loadCollection()
  }

  FileView {
    id: playlistsFile
    path: root.cacheDir + "/playlists.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.loadPlaylists()
    onTextChanged: root.loadPlaylists()
  }

  function loadCollection() {
    try {
      var d = JSON.parse(collectionFile.text() || "{}")
      collection = d.items || []
      lastUpdated = d.last_updated || lastUpdated
    } catch (e) {
      collection = []
    }
  }

  function loadPlaylists() {
    try {
      var d = JSON.parse(playlistsFile.text() || "{}")
      playlists = d.playlists || []
      if (d.last_updated) lastUpdated = d.last_updated
    } catch (e) {
      playlists = []
    }
  }

  Component.onCompleted: {
    root.loadSettings()
    root.loadCollection()
    root.loadPlaylists()
  }

  // Effective cookie jar: an explicit settings.cookiePath wins; otherwise the
  // browser's Bandcamp session is exported into the cache before every fetch.
  function refresh() {
    if (fetchProc.running || cookiesProc.running) return
    var manual = String(root.settings.cookiePath || "")
    if (manual !== "") {
      root.cookiePath = manual
      startFetch()
      return
    }
    status = "Importing browser session…"
    cookiesProc.command = [
      "python3", root.pluginDir + "/cookies.py",
      root.cacheDir + "/cookies.txt",
      String(root.settings.browser || "auto")
    ]
    cookiesProc.running = true
  }

  function startFetch() {
    if (fetchProc.running) return
    status = "Fetching library…"
    fetchProc.command = [
      "python3", root.pluginDir + "/fetch.py",
      String(root.settings.userUrl || ""),
      String(root.cookiePath || ""),
      root.settings.includePlaylists ? "1" : "0"
    ]
    fetchProc.running = true
  }

  Process {
    id: cookiesProc
    running: false
    stdout: StdioCollector { id: cookiesOut; waitForEnd: true }
    stderr: StdioCollector { id: cookiesErr; waitForEnd: true }
    onExited: function(code) {
      var ok = false
      try { ok = JSON.parse(cookiesOut.text || "{}").ok === true } catch (e) {}
      if (ok) {
        root.cookiePath = root.cacheDir + "/cookies.txt"
      } else {
        root.cookiePath = ""
        root.status = "No browser session found — sign in to Bandcamp to see private items."
      }
      root.startFetch()
    }
  }

  Process {
    id: fetchProc
    running: false
    stderr: StdioCollector { id: fetchErr; waitForEnd: true }
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        root.status = ""
        try {
          var d = JSON.parse(fetchOut.text || "{}")
          if (d.user) root.detectedUser = String(d.user)
        } catch (e) {}
        // Reload explicitly: the shell may run with QS_DISABLE_FILE_WATCHER=1,
        // in which case FileView keeps serving the previously cached text.
        collectionFile.reload()
        playlistsFile.reload()
        root.loadCollection()
        root.loadPlaylists()
      } else {
        var msg = (fetchErr.text || "").trim()
        try { msg = JSON.parse(fetchOut.text || "{}").error || msg } catch (e) {}
        root.status = "Fetch failed: " + msg
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: Math.max(5, Number(root.settings.refreshIntervalMin) || 15) * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // ---- playback state -----------------------------------------------------
  property var queue: []
  property int queueIndex: -1
  property var context: ({ type: "", name: "", tracks: [] })
  // Shuffle is a plain On/Off kept PER CONTEXT. A context is whatever the window is
  // showing: "album:<id>", "playlist:<id>", "search" or "library" (nothing selected).
  // Toggling one context never touches another, nor the queue of a different
  // context that happens to be playing.
  property var shuffleByContext: ({})
  property string playingContextKey: ""
  property bool isPlaying: false
  property bool isPaused: false
  property string playbackError: ""

  readonly property var currentTrack: (queueIndex >= 0 && queueIndex < queue.length) ? queue[queueIndex] : null

  readonly property string playIcon: isPlaying && !isPaused ? "\u23F8" : "\u25B6"

  function trackSignature(t) {
    if (!t) return ""
    return [t.artist || "", t.album || "", t.title || "", t.trackUrl || ""].join("|")
  }

  function isShuffled(key) { return key !== "" && shuffleByContext[key] === true }

  function toggleShuffle(key) { setShuffle(key, !isShuffled(key)) }

  function setShuffle(key, on) {
    var m = {}
    for (var k in shuffleByContext) m[k] = shuffleByContext[k]
    m[key] = !!on
    shuffleByContext = m
    // Only the context that is actually playing has a live queue to reorder.
    if (key === playingContextKey) reorderPlayingQueue(!!on)
  }

  // Re-order the live queue for the playing context, keeping the current track playing.
  function reorderPlayingQueue(on) {
    var tracks = (context && context.tracks) ? context.tracks : []
    if (tracks.length === 0) return
    var cur = currentTrack
    if (on) {
      var rest = tracks.filter(function(t) { return t !== cur })
      queue = cur ? [cur].concat(Model.fisherYates(rest)) : Model.fisherYates(tracks)
      queueIndex = queue.length > 0 ? 0 : -1
    } else {
      queue = tracks.slice()
      var idx = cur ? queue.indexOf(cur) : -1
      if (idx < 0 && cur) {
        for (var i = 0; i < queue.length; i++) {
          if (trackSignature(queue[i]) === trackSignature(cur)) { idx = i; break }
        }
      }
      queueIndex = idx >= 0 ? idx : (queue.length > 0 ? 0 : -1)
    }
  }

  // Start playing `tracks` as the context identified by `key`. `startIndex` is the
  // track the user clicked; leave it undefined to start from the beginning (or, with
  // shuffle On, from a random track). With shuffle On the clicked track plays first
  // and the rest of THIS context follows in random order.
  function playContext(type, name, tracks, startIndex, key) {
    var ctxKey = key || ""
    context = { type: type, name: name, tracks: tracks.slice(), key: ctxKey }
    playingContextKey = ctxKey
    var hasStart = startIndex !== undefined && startIndex >= 0 && startIndex < tracks.length
    if (isShuffled(ctxKey)) {
      if (hasStart) {
        var first = tracks[startIndex]
        var rest = tracks.filter(function(t, i) { return i !== startIndex })
        queue = [first].concat(Model.fisherYates(rest))
      } else {
        queue = Model.fisherYates(tracks)
      }
      queueIndex = queue.length > 0 ? 0 : -1
    } else {
      queue = tracks.slice()
      queueIndex = hasStart ? startIndex : 0
    }
    playCurrent()
  }

  function playAlbum(alb, startTrack) {
    var tracks = root.tracksFor(alb)
    if (tracks.length === 0) {
      root.requestTracks(alb, function() { root.playAlbum(alb, startTrack) })
      return
    }
    var idx = startTrack ? tracks.indexOf(startTrack) : undefined
    playContext("album", alb.title || "", tracks, idx, "album:" + alb.id)
  }

  function playPlaylist(pl, startTrack) {
    var tracks = root.tracksFor(pl)
    if (tracks.length === 0) {
      root.requestTracks(pl, function() { root.playPlaylist(pl, startTrack) })
      return
    }
    var idx = startTrack ? tracks.indexOf(startTrack) : undefined
    playContext("playlist", pl.name || pl.title || "", tracks, idx, "playlist:" + pl.id)
  }

  // The whole library as one context (what the window shows when nothing is selected).
  // Tracks come from what has been loaded so far; collection items only carry tracks
  // once their album has been opened.
  function playLibrary() {
    var tracks = Model.flattenTracks(collection, playlists)
    if (tracks.length === 0) return
    playContext("library", "Library", tracks, undefined, "library")
  }

  function playTrack(track) {
    // Play a single track within its current context if it belongs to the queue.
    var idx = queue.indexOf(track)
    if (idx >= 0) {
      queueIndex = idx
      playCurrent()
      return
    }
    queue = [track]
    queueIndex = 0
    context = { type: "single", name: track.album || "", tracks: [track], key: "" }
    playingContextKey = ""
    playCurrent()
  }

  function playCurrent() {
    var t = currentTrack
    if (!t) return
    if (!t.streamUrl) {
      playbackError = "No stream URL for: " + (t.title || "?")
      isPlaying = false
      return
    }
    playbackError = ""
    mpvProc.command = [
      "python3", root.pluginDir + "/mpvctl.py", "load",
      t.streamUrl, String(root.cookiePath || "")
    ]
    mpvProc.running = true
    isPlaying = true
    isPaused = false
  }

  function togglePlay() {
    if (!currentTrack) return
    if (!isPlaying) {
      playCurrent()
      return
    }
    ctlProc.command = ["python3", root.pluginDir + "/mpvctl.py", "toggle"]
    ctlProc.running = true
    isPaused = !isPaused
  }

  function pause() {
    if (!isPlaying || isPaused) return
    ctlProc.command = ["python3", root.pluginDir + "/mpvctl.py", "pause"]
    ctlProc.running = true
    isPaused = true
  }

  function stop() {
    ctlProc.command = ["python3", root.pluginDir + "/mpvctl.py", "stop"]
    ctlProc.running = true
    isPlaying = false
    isPaused = false
  }

  function next() {
    if (queue.length === 0) return
    if (queueIndex < queue.length - 1) {
      queueIndex += 1
    } else {
      queueIndex = 0
    }
    playCurrent()
  }

  function prev() {
    if (queue.length === 0) return
    if (queueIndex > 0) {
      queueIndex -= 1
    } else {
      queueIndex = queue.length - 1
    }
    playCurrent()
  }

  function search(q) {
    searchQuery = q
    searchResults = Model.searchIndex(collection, playlists, q)
  }

  function itemById(id) {
    for (var i = 0; i < collection.length; i++) {
      if (String(collection[i].id) === String(id)) return collection[i]
    }
    for (var j = 0; j < playlists.length; j++) {
      var pl = playlists[j]
      if (String(pl.id) === String(id)) return pl
    }
    return null
  }

  function playById(id) {
    var item = root.itemById(id)
    if (!item) return "unknown"
    var isPlaylist = false
    for (var i = 0; i < playlists.length; i++) {
      if (String(playlists[i].id) === String(id)) { isPlaylist = true; break }
    }
    if (isPlaylist) root.playPlaylist(item)
    else root.playAlbum(item)
    return "ok"
  }

  Process {
    id: mpvProc
    running: false
    environment: ({ OMATIME_MPV_FLAGS: String(root.settings.mpvFlags || "") })
    stdout: StdioCollector { id: mpvOut; waitForEnd: true }
    stderr: StdioCollector { id: mpvErr; waitForEnd: true }
    onExited: function(code) {
      var ok = false
      try { ok = JSON.parse(mpvOut.text || "{}").ok === true } catch (e) {}
      if (ok) {
        root.playbackError = ""
        root.isPlaying = true
        root.isPaused = false
      } else {
        var msg = ""
        try { msg = JSON.parse(mpvOut.text || "{}").error || "" } catch (e) {}
        if (msg === "") msg = (mpvErr.text || "").trim()
        root.playbackError = "Playback failed: " + (msg || ("exit " + code))
        root.isPlaying = false
        root.isPaused = false
      }
    }
  }
  Process { id: ctlProc; running: false }

  // ---- lazy tracklists ----------------------------------------------------
  // Collection items carry no tracks; album tracklists are fetched on demand
  // and memoized here (and on the item itself) to keep refreshes fast.
  property var trackCache: ({})
  property var pendingTracks: ({})

  function tracksFor(item) {
    if (!item) return []
    if (item.tracks && item.tracks.length > 0) return item.tracks
    var cached = trackCache[String(item.id)]
    return cached || []
  }

  function requestTracks(item, cb) {
    if (!item || !item.id) return
    var have = tracksFor(item)
    if (have.length > 0) { if (cb) cb(have); return }
    var key = String(item.id)
    if (pendingTracks[key]) { if (cb) pendingTracks[key].push(cb); return }
    pendingTracks[key] = cb ? [cb] : []
    tracksProc.itemKey = key
    tracksProc.itemRef = item
    tracksProc.command = [
      "python3", root.pluginDir + "/fetch.py", "--tracks",
      item.type || "album", key, String(root.cookiePath || "")
    ]
    tracksProc.running = true
    status = "Loading " + (item.title || "album") + "…"
  }

  Process {
    id: tracksProc
    running: false
    property string itemKey: ""
    property var itemRef: null
    stdout: StdioCollector { id: tracksOut; waitForEnd: true }
    stderr: StdioCollector { id: tracksErr; waitForEnd: true }
    onExited: function(code) {
      root.status = ""
      var tracks = []
      if (code === 0) {
        try { var d = JSON.parse(tracksOut.text || "{}"); tracks = d.tracks || [] } catch (e) {}
      } else {
        root.playbackError = "Track list failed: " + (tracksErr.text || "").trim()
      }
      if (tracksProc.itemRef) tracksProc.itemRef.tracks = tracks
      var tc = {}
      for (var k in root.trackCache) tc[k] = root.trackCache[k]
      tc[tracksProc.itemKey] = tracks
      root.trackCache = tc
      var cbs = root.pendingTracks[tracksProc.itemKey] || []
      var np = {}
      for (var k2 in root.pendingTracks) if (k2 !== tracksProc.itemKey) np[k2] = root.pendingTracks[k2]
      root.pendingTracks = np
      for (var i = 0; i < cbs.length; i++) if (cbs[i]) cbs[i](tracks)
    }
  }

  // ---- shell IPC ----------------------------------------------------------
  function statusJson() {
    var t = currentTrack
    return JSON.stringify({
      playing: root.isPlaying,
      paused: root.isPaused,
      shuffle: root.isShuffled(root.playingContextKey) ? 1 : 0,
      title: t ? (t.title || "") : "",
      artist: t ? (t.artist || "") : "",
      album: t ? (t.album || "") : "",
      items: root.collection.length,
      playlists: root.playlists.length,
      user: root.detectedUser,
      status: root.status,
      updated: root.lastUpdated
    })
  }

  // Delete the imported cookie jar. The next refresh re-exports it from the
  // browser (auto mode) or leaves it absent so a manual cookiePath is used.
  function clearCookies() {
    root.cookiePath = ""
    root.detectedUser = ""
    root.status = "Cleared imported session"
    clearProc.command = ["rm", "-f", root.cacheDir + "/cookies.txt"]
    clearProc.running = true
    return "ok"
  }

  Process { id: clearProc; running: false }

  IpcHandler {
    target: "omatimeatbandcamp"

    function status(): string { return root.statusJson() }
    function playPause(): string { root.togglePlay(); return "ok" }
    function next(): string { root.next(); return "ok" }
    function previous(): string { root.prev(); return "ok" }
    function stop(): string { root.stop(); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
    function play(id: string): string { return root.playById(id) }
    function clearCookies(): string { return root.clearCookies() }
    function ping(): string { return "ok" }
  }
}
