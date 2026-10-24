import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "LibraryModel.js" as LibraryModel

// Shared state for the OmaTimeAtBandCamp bar widget and panel.
//
// Settings live in the plugin's entry in ~/.config/omarchy/shell.json (written
// by the standard settings form), falling back to the manifest defaults.
// The library is the backend's cache (backend/library.py -> library.json): the union
// of the web collection and Subsonic. This service reads it, refreshes it in the
// background (`backend sync`), and drives mpv (mpvctl.py / `backend play`).
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
  // All albums / playlists, adapted by LibraryModel.adaptLibrary from library.json.
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
  // Short-lived message for the user ("Not yet released"); cleared by noticeTimer.
  property string notice: ""

  // Sorting and filtering of the Albums list. Persisted in stateDir/ui.json.
  property string sortMode: "added"
  property bool hidePreorders: false
  readonly property var albumsView: LibraryModel.sortAlbums(collection, sortMode, hidePreorders)

  // True from the moment Refresh starts (browser-session import, then backend sync)
  // until the sync exits; drives the toolbar Refresh button.
  readonly property bool refreshing: syncProc.running || cookiesProc.running

  readonly property string stateDir: home + "/.local/state/omatimeatbandcamp"

  function notify(msg) {
    notice = msg
    noticeTimer.restart()
  }

  Timer { id: noticeTimer; interval: 3500; onTriggered: root.notice = "" }

  FileView {
    id: libraryFile
    path: root.cacheDir + "/library/library.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.loadLibrary()
    onTextChanged: root.loadLibrary()
  }

  function loadLibrary() {
    try {
      var d = JSON.parse(libraryFile.text() || "{}")
      if (!d.albums) return
      var m = LibraryModel.adaptLibrary(d)
      collection = m.albums
      playlists = m.playlists
      if (d.meta) {
        if (d.meta.finished) lastUpdated = String(d.meta.finished)
        if (d.meta.user) detectedUser = String(d.meta.user)
      }
    } catch (e) {
    }
  }

  // ---- persisted UI choices -------------------------------------------------
  FileView {
    id: uiFile
    path: root.stateDir + "/ui.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
  }

  Process { id: mkStateDir; running: false; command: ["mkdir", "-p", root.stateDir] }

  function loadUi() {
    try {
      var d = JSON.parse(uiFile.text() || "{}")
      if (LibraryModel.validSort(d.sortMode)) sortMode = d.sortMode
      hidePreorders = d.hidePreorders === true
    } catch (e) {
    }
  }

  function saveUi() {
    mkStateDir.running = true
    uiFile.setText(JSON.stringify({ sortMode: sortMode, hidePreorders: hidePreorders }) + "\n")
  }

  function setSortMode(mode) {
    if (!LibraryModel.validSort(mode) || mode === sortMode) return
    sortMode = mode
    saveUi()
  }

  function setHidePreorders(on) {
    if (hidePreorders === !!on) return
    hidePreorders = !!on
    saveUi()
  }

  Component.onCompleted: {
    root.loadSettings()
    root.loadUi()
    root.loadLibrary()
  }

  // Effective cookie jar: an explicit settings.cookiePath wins; otherwise the
  // browser's Bandcamp session is exported into the cache before every sync.
  function refresh() {
    if (syncProc.running || cookiesProc.running) return
    var manual = String(root.settings.cookiePath || "")
    if (manual !== "") {
      root.cookiePath = manual
      startSync()
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

  function startSync() {
    if (syncProc.running) return
    status = "Syncing library…"
    syncProc.lastError = ""
    syncProc.stage = ""
    var cmd = ["python3", root.pluginDir + "/backend", "sync", "--workers", "4"]
    if (String(root.cookiePath || "") !== "") cmd = cmd.concat(["--cookies", String(root.cookiePath)])
    if (String(root.settings.userUrl || "") !== "") cmd = cmd.concat(["--user-url", String(root.settings.userUrl)])
    if (!root.settings.includePlaylists) cmd.push("--no-playlists")
    syncProc.command = cmd
    syncProc.running = true
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
      root.startSync()
    }
  }

  // The sync runs in its own process and prints one JSON progress line at a time. The
  // cached library stays on screen throughout and is reloaded when the matched library
  // is first saved and again when the sync finishes; the UI is never blocked.
  Process {
    id: syncProc
    running: false
    property string stage: ""
    property string lastError: ""
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var d = JSON.parse(line)
          if (d.error) { syncProc.lastError = String(d.error); return }
          if (d.stage === "playlists" && syncProc.stage !== "playlists") {
            libraryFile.reload()
            root.loadLibrary()
          }
          syncProc.stage = d.stage
          root.status = "Syncing library · " + d.stage + (d.total > 0 ? " " + d.done + "/" + d.total : "") + "…"
        } catch (e) {}
      }
    }
    stderr: StdioCollector { id: syncErr; waitForEnd: true }
    onExited: function(code) {
      // Reload explicitly: the shell may run with QS_DISABLE_FILE_WATCHER=1, in which
      // case FileView keeps serving the previously cached text.
      libraryFile.reload()
      root.loadLibrary()
      if (code === 0) {
        root.status = "Library updated · " + root.collection.length + " albums"
        statusClearTimer.restart()
      } else {
        root.status = "Sync failed: " + (syncProc.lastError || (syncErr.text || "").trim() || ("exit " + code))
      }
    }
  }

  Timer { id: statusClearTimer; interval: 8000; onTriggered: if (!root.refreshing) root.status = "" }

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
      var rest = tracks.filter(function(t) { return indexOfTrack([cur], t) < 0 })
      queue = cur ? [cur].concat(Model.fisherYates(rest)) : Model.fisherYates(tracks)
      queueIndex = queue.length > 0 ? 0 : -1
    } else {
      queue = tracks.slice()
      var idx = cur ? indexOfTrack(queue, cur) : -1
      queueIndex = idx >= 0 ? idx : (queue.length > 0 ? 0 : -1)
    }
  }

  function indexOfTrack(list, track) {
    if (!track) return -1
    for (var i = 0; i < list.length; i++) {
      if (list[i] === track || (track.uid && list[i].uid === track.uid)) return i
    }
    return -1
  }

  function unavailableMessage(track) {
    return track && track.reason === "unreleased" ? "Not yet released" : "Not available to stream"
  }

  // Start playing `tracks` as the context identified by `key`. `startIndex` is the
  // track the user clicked; leave it undefined to start from the beginning (or, with
  // shuffle On, from a random track). The queue only ever holds streamable tracks: a
  // clicked track that is not streamable plays nothing and only shows a notice. With
  // shuffle On the clicked track plays first and the rest of THIS context follows in
  // random order.
  function playContext(type, name, tracks, startIndex, key) {
    var ctxKey = key || ""
    var clicked = (startIndex !== undefined && startIndex >= 0 && startIndex < tracks.length) ? tracks[startIndex] : null
    if (clicked && clicked.streamable === false) {
      notify(unavailableMessage(clicked))
      return
    }
    var playable = tracks.filter(function(t) { return t.streamable !== false })
    if (playable.length === 0) {
      notify("Nothing available to play yet")
      return
    }
    var startAt = clicked ? indexOfTrack(playable, clicked) : -1
    context = { type: type, name: name, tracks: playable.slice(), key: ctxKey }
    playingContextKey = ctxKey
    if (isShuffled(ctxKey)) {
      if (startAt >= 0) {
        var first = playable[startAt]
        var rest = playable.filter(function(t, i) { return i !== startAt })
        queue = [first].concat(Model.fisherYates(rest))
      } else {
        queue = Model.fisherYates(playable)
      }
      queueIndex = 0
    } else {
      queue = playable.slice()
      queueIndex = startAt >= 0 ? startAt : 0
    }
    playCurrent()
  }

  function playAlbum(alb, startTrack) {
    var tracks = root.tracksFor(alb)
    if (tracks.length === 0) { notify("No tracks to play"); return }
    var idx = startTrack ? indexOfTrack(tracks, startTrack) : undefined
    playContext("album", alb.title || "", tracks, idx, "album:" + alb.id)
  }

  function playPlaylist(pl, startTrack) {
    var tracks = root.tracksFor(pl)
    if (tracks.length === 0) { notify("No tracks to play"); return }
    var idx = startTrack ? indexOfTrack(tracks, startTrack) : undefined
    playContext("playlist", pl.name || pl.title || "", tracks, idx, "playlist:" + pl.id)
  }

  // The whole library as one context (what the window shows when nothing is selected):
  // every streamable album track.
  function playLibrary() {
    var tracks = LibraryModel.libraryTracks(collection)
    if (tracks.length === 0) { notify("Nothing available to play yet"); return }
    playContext("library", "Library", tracks, undefined, "library")
  }

  function playTrack(track) {
    // Play a single track within its current context if it belongs to the queue.
    var idx = indexOfTrack(queue, track)
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
    if (t.streamable === false) {
      playbackError = unavailableMessage(t)
      isPlaying = false
      return
    }
    playbackError = ""
    if (t.streamUrl) {
      mpvProc.command = ["python3", root.pluginDir + "/mpvctl.py", "load", t.streamUrl, String(root.cookiePath || ""), t.title || ""]
    } else if (t.subsonicId) {
      // The backend builds the Subsonic stream URL (it embeds credentials) and hands it
      // to mpv itself, so the URL is never in argv, in output or in any log.
      mpvProc.command = ["python3", root.pluginDir + "/backend", "play", t.subsonicId, "--title", t.title || ""]
    } else {
      playbackError = "No stream source for: " + (t.title || "?")
      isPlaying = false
      return
    }
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

  // ---- tracklists -----------------------------------------------------------
  // Library items carry their tracks (the sync fetches them in the background).
  function tracksFor(item) {
    return item && item.tracks ? item.tracks : []
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
