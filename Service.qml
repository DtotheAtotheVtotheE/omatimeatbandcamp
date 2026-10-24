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
  // Directory holding the python helpers (backend/, mpvctl.py, cookies.py).
  //
  // Qt.resolvedUrl gives a real file:// URL in the shell, but Quickshell can also
  // resolve imported files to its internal `qs:` URL scheme, which python cannot open.
  // Fall back to the shell's documented third-party plugin location, and allow an
  // explicit override for test harnesses and out-of-tree installs.
  readonly property string pluginDir: {
    var override = Quickshell.env("OMATIME_PLUGIN_DIR")
    if (override) return String(override)
    var u = String(Qt.resolvedUrl("Service.qml"))
    if (u.indexOf("file://") === 0) {
      u = decodeURIComponent(u.substring(7))
      return u.substring(0, u.lastIndexOf("/"))
    }
    return home + "/.config/omarchy/plugins/com.github.dtotheatothevtothee.omatimeatbandcamp"
  }
  readonly property string cacheDir: home + "/.cache/omatimeatbandcamp"
  readonly property string shellConfigPath: home + "/.config/omarchy/shell.json"

  // ---- bar album art ------------------------------------------------------
  // The bar's art widget only reads this one small local JPEG. The backend
  // fetches/downscales it (cover URLs embed credentials, so they never leave
  // the backend process) and writes the bundled placeholder when stopped.
  readonly property string artPath: cacheDir + "/current-art.jpg"
  readonly property string placeholderArt: pluginDir + "/assets/current-art-placeholder.jpg"
  // Harness/offline override: cover ids map to <dir>/<id>.jpg instead of the network.
  readonly property string artFixtureDir: Quickshell.env("OMATIME_ART_FIXTURE_DIR") || ""
  readonly property string waybarArtSignal: "RTMIN+8"
  property int artRevision: 0
  property bool barArtIsPlaceholder: true
  property var artJob: null
  property int artJobSeq: 0

  // ---- external links -----------------------------------------------------
  // Phase 7: the links row opens public Bandcamp pages in the default browser.
  // The executable is overridable so the QML harness records calls instead of
  // launching a browser. Only https URLs are ever handed to it.
  readonly property string openCommand: Quickshell.env("OMATIME_OPEN_CMD") || "xdg-open"
  property string lastOpenedUrl: ""
  property var openedUrls: []

  function openExternal(url) {
    var u = String(url || "")
    if (u.indexOf("https://") !== 0) return false
    lastOpenedUrl = u
    openedUrls = openedUrls.concat([u])
    openProc.command = [openCommand, u]
    openProc.running = false
    openProc.running = true
    return true
  }

  Process { id: openProc; running: false }

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
    root.scheduleBarArt()   // no track yet: write the bundled placeholder
    root.startMpris()
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
  // Progress + seek. `duration` starts from the library's own track duration, so the bar
  // is determinate before mpv reports anything; mpv's value replaces it when it arrives.
  property real position: 0
  property real duration: 0
  readonly property real progress: duration > 0 ? Math.max(0, Math.min(1, position / duration)) : 0
  // Target of a seek mpv has not confirmed yet. Polled positions are ignored while it is
  // set, otherwise the bar would jump back to the old spot for a tick or two.
  property real pendingSeek: -1
  property double pendingSeekAt: 0
  // Consecutive automatic skips, so a dead server cannot spin through the whole queue.
  property int failureStreak: 0
  // Which load request mpvProc is currently serving (stale exits must be ignored).
  property int playRequest: 0
  // When the current load was requested. mpv stays idle until the load lands, so an
  // "idle" status during this window is not the end of the track.
  property double playbackStartedAt: 0

  readonly property var currentTrack: (queueIndex >= 0 && queueIndex < queue.length) ? queue[queueIndex] : null

  readonly property string playIcon: isPlaying && !isPaused ? "\u23F8" : "\u25B6"

  // ---- bar art ------------------------------------------------------------
  // Resolve a track to an album cover id. Tracks carry the Subsonic album id;
  // the cover id lives on the album (and on newer cached tracks directly).
  function coverArtIdFor(track) {
    if (!track) return ""
    if (track.coverArtId) return String(track.coverArtId)
    var aid = String(track.subsonicAlbumId || "")
    var i
    if (aid !== "") {
      for (i = 0; i < collection.length; i++) {
        if (String(collection[i].subsonicId || "") === aid) return String(collection[i].coverArtId || "")
      }
    }
    for (i = 0; i < collection.length; i++) {
      var a = collection[i]
      if (a.title === track.album && a.artist === track.artist && a.coverArtId) return String(a.coverArtId)
    }
    return ""
  }

  // Coalesce the several property changes one track load makes into one job.
  function scheduleBarArt() { artDebounce.restart() }

  function updateBarArt() {
    var t = currentTrack
    var active = !!t && (isPlaying || isPaused)
    if (!active) { queueArtJob({ placeholder: true }); return }
    var cover = coverArtIdFor(t)
    if (cover === "") { queueArtJob({ placeholder: true }); return }
    if (artFixtureDir !== "") { queueArtJob({ fromFile: artFixtureDir + "/" + cover + ".jpg" }); return }
    queueArtJob({ cover: cover })
  }

  function queueArtJob(job) {
    artJob = job
    if (!artProc.running) runArtJob()
  }

  function runArtJob() {
    var job = artJob
    if (!job) return
    artJob = null
    artJobSeq += 1
    var cmd = ["python3", root.pluginDir + "/backend", "art", "--out", root.artPath]
    if (job.placeholder) cmd.push("--placeholder")
    else if (job.fromFile) { cmd.push("--from-file", String(job.fromFile)) }
    else cmd.push(String(job.cover))
    artProc.job = job
    artProc.req = artJobSeq
    artProc.command = cmd
    artProc.running = true
  }

  function signalBarArt() {
    // Omarchy's Quickshell bar watches the file; this RTMIN signal keeps a
    // legacy Waybar image module in sync too. No Waybar config is assumed.
    artSignalProc.running = false
    artSignalProc.running = true
  }

  onCurrentTrackChanged: scheduleBarArt()
  onIsPlayingChanged: scheduleBarArt()
  onIsPausedChanged: scheduleBarArt()

  Timer { id: artDebounce; interval: 80; onTriggered: root.updateBarArt() }

  Process {
    id: artProc
    running: false
    property var job: null
    property int req: 0
    stdout: StdioCollector { id: artOut; waitForEnd: true }
    stderr: StdioCollector { id: artErr; waitForEnd: true }
    onExited: function(code) {
      if (artProc.req !== root.artJobSeq) return
      var d = {}
      try { d = JSON.parse(artOut.text || "{}") } catch (e) {}
      root.barArtIsPlaceholder = d.placeholder === true || (artProc.job && artProc.job.placeholder === true)
      root.artRevision += 1
      root.signalBarArt()
      if (root.artJob) root.runArtJob()
    }
  }

  Process { id: artSignalProc; running: false; command: ["pkill", "-" + root.waybarArtSignal, "waybar"] }

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
    position = 0
    duration = Number(t.duration) || 0
    pendingSeek = -1
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
    playRequest += 1
    mpvProc.req = playRequest
    playbackStartedAt = Date.now()
    mpvProc.running = true
    isPlaying = true
    isPaused = false
  }

  function fmtTime(sec) { return LibraryModel.fmtClock(sec) }

  function pollPosition() {
    if (posProc.running) return
    posProc.command = ["python3", root.pluginDir + "/mpvctl.py", "status"]
    posProc.running = true
  }

  // Parses one `mpvctl.py status` result. Kept as a function (not inline in the Process)
  // so the QML harness can feed measured positions and end-of-stream states through the
  // same path the player uses.
  function applyPlaybackStatus(s) {
    if (!s || s.running !== true) return
    var p = (typeof s.position === "number" && isFinite(s.position)) ? s.position : -1
    var d = (typeof s.duration === "number" && isFinite(s.duration) && s.duration > 0) ? s.duration : 0
    if (d > 0) duration = d
    if (p >= 0) {
      if (pendingSeek >= 0) {
        if (Math.abs(p - pendingSeek) < 1.5 || (Date.now() - pendingSeekAt) > 2500) {
          pendingSeek = -1
          position = p
        }
      } else {
        position = p
      }
    }
    // End of track (or a dead stream). Ignore mpv's idle state while the load is still
    // landing: mpv reports idle until it has actually opened the stream. A stream that
    // never produces a position at all is treated as failed after a longer grace period.
    var elapsed = Date.now() - playbackStartedAt
    if (isPlaying && (s.eof === true || s.idle === true) && elapsed > 2500) {
      if (position > 0 || elapsed > 8000) onStreamEnded()
    }
  }

  // Absolute seek. mpv seeks inside its network cache, so this works on a stream without
  // downloading it first (verified against the real Subsonic stream; see V2-NOTES.md).
  function seekTo(seconds) {
    if (!currentTrack || duration <= 0) return
    var target = Math.max(0, Math.min(duration, Number(seconds) || 0))
    position = target
    pendingSeek = target
    pendingSeekAt = Date.now()
    seekProc.command = ["python3", root.pluginDir + "/mpvctl.py", "seek", String(target)]
    seekProc.running = true
  }

  // mpv reached idle while we thought we were playing: either the track ended, or the
  // stream died early. A track that stopped well short of its duration is a failure.
  function onStreamEnded() {
    if (!isPlaying) return
    isPlaying = false
    isPaused = false
    if (duration > 0 && position < duration - 2) {
      skipCurrent()
      return
    }
    pendingSeek = -1
    if (queueIndex >= 0 && queueIndex < queue.length - 1) {
      queueIndex += 1
      playCurrent()
    } else {
      position = duration
      playbackError = ""
    }
  }

  // The visible failure path: name the track and move on. playCurrent() clears
  // playbackError, so the message is set after any advance.
  function skipCurrent() {
    var title = currentTrack ? (currentTrack.title || "this track") : "this track"
    position = 0
    pendingSeek = -1
    failureStreak += 1
    var canAdvance = failureStreak <= 3 && queue.length > 1 && queueIndex >= 0 && queueIndex < queue.length - 1
    if (canAdvance) {
      queueIndex += 1
      playCurrent()
    }
    playbackError = canAdvance ? "Couldn't play " + title + " — skipped" : "Couldn't play " + title
  }

  function togglePlay() {
    if (!currentTrack) return
    if (!isPlaying) {
      if (duration > 0 && position >= duration - 1) position = 0   // after the end: replay
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
    position = 0
    pendingSeek = -1
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
    property int req: 0
    environment: ({ OMATIME_MPV_FLAGS: String(root.settings.mpvFlags || "") })
    stdout: StdioCollector { id: mpvOut; waitForEnd: true }
    stderr: StdioCollector { id: mpvErr; waitForEnd: true }
    onExited: function(code) {
      if (mpvProc.req !== root.playRequest) return   // a newer track was requested meanwhile
      var d = {}
      try { d = JSON.parse(mpvOut.text || "{}") } catch (e) {}
      if (d.ok === true) {
        root.playbackError = ""
        root.isPlaying = true
        root.isPaused = false
        root.failureStreak = 0
        return
      }
      var msg = String(d.error || "").trim()
      if (msg === "") msg = (mpvErr.text || "").trim()
      if (msg === "") msg = "exit " + code
      root.isPlaying = false
      root.isPaused = false
      if (d.fatal === true) {
        // Credentials/server/player setup: every track would fail the same way, so
        // show it and do not burn through the queue.
        root.playbackError = "Playback unavailable: " + msg
      } else {
        root.skipCurrent()
      }
    }
  }
  Process { id: ctlProc; running: false }

  // Position polling: one lightweight mpvctl call per second while playing. Paused means
  // the position cannot change on its own, so polling stops.
  Timer {
    id: positionTimer
    interval: 1000
    repeat: true
    running: root.isPlaying && !root.isPaused
    onTriggered: root.pollPosition()
  }

  Process {
    id: posProc
    running: false
    stdout: StdioCollector { id: posOut; waitForEnd: true }
    stderr: StdioCollector { id: posErr; waitForEnd: true }
    onExited: function(code) {
      var d = {}
      try { d = JSON.parse(posOut.text || "{}") } catch (e) {}
      root.applyPlaybackStatus(d)
    }
  }

  Process {
    id: seekProc
    running: false
    stdout: StdioCollector { id: seekOut; waitForEnd: true }
    stderr: StdioCollector { id: seekErr; waitForEnd: true }
    onExited: function(code) { root.pollPosition() }
  }

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

  // ---- MPRIS ---------------------------------------------------------------
  // The QML shell has no D-Bus server API, so backend/mpris.py publishes this
  // playback state. The file is an explicit whitelist: title/artist/album come
  // from the library, never from mpv, so mpv's credential-bearing `path` (the
  // signed stream URL) cannot reach D-Bus. The daemon builds mpris:artUrl from
  // the local cached cover only. `OMATIME_MPRIS=0` disables it (test harness).
  readonly property string mprisStatePath: cacheDir + "/mpris-state.json"
  readonly property bool mprisEnabled: Quickshell.env("OMATIME_MPRIS") !== "0"
  property bool mprisStarted: false

  function mprisPlaybackStatus() {
    if (!isPlaying) return "Stopped"
    return isPaused ? "Paused" : "Playing"
  }

  function writeMprisState() {
    var t = currentTrack
    var state = {
      title: t ? String(t.title || "") : "",
      artist: t ? String(t.artist || "") : "",
      album: t ? String(t.album || "") : "",
      status: mprisPlaybackStatus(),
      position: Number(position) || 0,
      duration: Number(duration) || 0,
      updatedAt: Date.now(),
      canSeek: !!t && duration > 0,
      canPlay: !!t,
      canPause: !!t,
      // The plugin's Next/Prev wrap at the ends, so MPRIS keeps them enabled
      // whenever there is a queue (media keys then behave like the footer).
      canNext: queue.length > 0,
      canPrevious: queue.length > 0
    }
    mprisFile.setText(JSON.stringify(state) + "\n")
  }

  function startMpris() {
    if (!mprisEnabled || mprisStarted) return
    mprisStarted = true
    Quickshell.execDetached(["mkdir", "-p", root.cacheDir])
    writeMprisState()
    mprisProc.command = ["python3", root.pluginDir + "/backend/mpris.py",
      "--state", root.mprisStatePath, "--art", root.artPath]
    mprisProc.running = true
    mprisTimer.start()
  }

  Timer {
    id: mprisTimer
    interval: 1000
    repeat: true
    running: false
    onTriggered: root.writeMprisState()
  }
  FileView { id: mprisFile; path: root.mprisStatePath }
  Process { id: mprisProc; running: false }
  Process { id: quitPlayerProc; running: false }

  // One-time migration helper for players spawned before --load-scripts=no.
  // Resets the UI to stopped and asks mpv to quit; the next Play spawns a new
  // player with the MPRIS script disabled. The queue is kept.
  function restartPlayer() {
    isPlaying = false
    isPaused = false
    position = 0
    pendingSeek = -1
    quitPlayerProc.command = ["python3", root.pluginDir + "/mpvctl.py", "quit"]
    quitPlayerProc.running = true
    return "ok"
  }

  IpcHandler {
    target: "omatimeatbandcamp"

    function status(): string { return root.statusJson() }
    function playPause(): string { root.togglePlay(); return "ok" }
    function resume(): string { if (!root.isPlaying || root.isPaused) root.togglePlay(); return "ok" }
    function pause(): string { root.pause(); return "ok" }
    function seek(seconds: string): string { root.seekTo(Number(seconds)); return "ok" }
    function next(): string { root.next(); return "ok" }
    function previous(): string { root.prev(); return "ok" }
    function stop(): string { root.stop(); return "ok" }
    function restartPlayer(): string { return root.restartPlayer() }
    function refresh(): string { root.refresh(); return "ok" }
    function play(id: string): string { return root.playById(id) }
    function clearCookies(): string { return root.clearCookies() }
    function ping(): string { return "ok" }
  }
}
