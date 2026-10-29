//@ pragma OmarchyLoadPatch
// v3.5.6.1 live-path font check (100% label clip incident).
//
// Run by tests/qml/run.sh on the real Wayland session, with the real $HOME, so
// qs.Commons loads the owner's actual theme tokens and font. Unlike shell.qml
// this uses the real Bar.qml and the real qs.Ui.KeyboardPanel (no fake bar and
// no plain-Item stub). The service is a deterministic stub only so the label
// can be driven straight to 100% without racing a real sync.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/bar"
import "plug" as Plug

ShellRoot {
  id: host

  readonly property string syncHeadline: "Syncing library…"
  readonly property int fixtureAlbums: 688
  readonly property int fixturePlaylists: 33
  property int fails: 0
  property int checks: 0

  QtObject {
    id: svc
    property var albumsView: []
    property var playlists: []
    property string searchQuery: ""
    property var searchResults: ({ tracks: [], albums: [], playlists: [] })
    property var currentTrack: null
    property bool isPlaying: false
    property bool isPaused: false
    property bool refreshing: false
    property real position: 0
    property real duration: 0
    property string playbackError: ""
    property var userQueue: []
    property string status: ""
    property int activeTab: 0
    // The owner's persisted choice: Recently added, descending. The wider
    // label than "Title A–Z" is what exposed the live gap clip.
    property string sortMode: "added"
    property string playlistSortMode: "title"
    property string sortDirection: "desc"
    property string playlistSortDirection: "asc"
    property bool hidePreorders: false
    property var collection: []
    property int syncPercent: 0
    function isShuffled(key) { return false }
    function search(text) {}
    function syncStatusText(percent) {
      var pct = Math.max(0, Math.min(100, Math.floor(Number(percent) || 0)))
      return "Syncing library… " + pct + "%"
    }
  }

  QtObject {
    id: fakeShell
    function serviceFor(id) { return svc }
  }

  // Real bar host: same class and theme bindings as the live shell. Hidden and
  // empty so this probe borrows its real font/colours without drawing a bar.
  Bar {
    id: realBar
    shell: fakeShell
    barHidden: true
    barConfig: ({ position: "top", layout: { left: [], centerBegin: [], center: [], centerEnd: [], right: [] } })
  }

  FloatingWindow {
    id: hostWin
    implicitWidth: 900
    implicitHeight: 720
    color: Color.background
    Item {
      anchors.fill: parent
      Plug.Panel {
        id: panel
        bar: realBar
        anchors.top: parent.top
        width: 160
        height: 30
      }
    }
  }

  // Same text/font/width as the real label, laid out but transparent. This is
  // how the check can assert truncated === false for every one of the 102
  // strings without changing svc.status 102 times.
  Text {
    id: probe
    visible: true
    opacity: 0
    width: 1
    textFormat: Text.PlainText
    elide: Text.ElideRight
    font.family: realBar.fontFamily
    font.pixelSize: Math.max(1, Style.font.caption - 1)
  }

  function log(m) { console.log("HARNESS " + m) }
  function check(name, cond) {
    checks++
    if (!cond) fails++
    log((cond ? "PASS " : "FAIL ") + name)
  }
  function find(item, pred) {
    if (!item) return null
    if (pred(item)) return item
    var kids = item.data ? item.data : item.children
    if (!kids) return null
    for (var i = 0; i < kids.length; i++) {
      var r = find(kids[i], pred)
      if (r) return r
    }
    return null
  }
  function named(item, name) { return find(item, function(it) { return it.objectName === name }) }
  function labelItem() { return find(panel, function(it) { return it.objectName === "syncStatusLabel" }) }
  function keyboardPanel() { return find(panel, function(it) { return typeof it.fittedContentHeight === "function" }) }
  function contentRoot() { var kp = keyboardPanel(); return kp && kp.contentItem ? kp.contentItem[1] : null }
  function cardItem() { var c = contentRoot(); return c ? c.parent.parent : null }

  function fillLibrary() {
    var albums = []
    for (var i = 0; i < fixtureAlbums; i++) {
      albums.push({
        title: "Album " + i, artist: "Artist " + i, kind: "album",
        subsonic_id: null, cover_art_id: null, bandcamp_id: String(100000 + i),
        bandcamp_url: "", web_item_ids: [], purchased: "",
        declared_track_count: 1, returned_track_count: 1, tracks_loaded: true,
        tracks: [{ title: "Track", artist: "Artist " + i, album: "Album " + i,
          track_number: 1, duration: 0.0, year: null, streamable: false,
          streamable_reason: "unreleased", subsonic_id: null,
          bandcamp_id: String(200000 + i), subsonic_album_id: null }]
      })
    }
    var lists = []
    for (var j = 0; j < fixturePlaylists; j++) {
      lists.push({ id: "pl:" + j, name: "Playlist " + j, declared_track_count: 1,
        tracks: [], tracks_loaded: true, public: null, changed: null, returned_track_count: 1 })
    }
    svc.collection = albums
    svc.albumsView = albums
    svc.playlists = lists
  }

  function runStatusCheck() {
    var label = labelItem()
    if (!label) { check("v3.5.6.1: every enumerated sync status fits the live-path label with the real theme font (100% clip incident)", false); return }
    var statuses = [syncHeadline]
    for (var p = 0; p <= 100; p++) statuses.push(svc.syncStatusText(p))
    probe.font.family = label.font.family
    probe.font.pixelSize = label.font.pixelSize
    probe.width = label.width
    log("live theme: family=" + JSON.stringify(realBar.fontFamily) +
      " labelFamily=" + JSON.stringify(label.font.family) +
      " resolved=" + JSON.stringify(Style.font.resolvedFamily) +
      " caption=" + Style.font.caption + " labelPx=" + label.font.pixelSize +
      " accent=" + Color.accent)
    var badWidth = [], badTrunc = [], maxWidth = 0, worst = ""
    for (var i = 0; i < statuses.length; i++) {
      probe.text = statuses[i]
      if (probe.implicitWidth > label.width + 0.5) badWidth.push(statuses[i])
      if (probe.truncated) badTrunc.push(statuses[i])
      if (probe.implicitWidth > maxWidth) { maxWidth = probe.implicitWidth; worst = statuses[i] }
    }
    probe.width = 1
    log("v3.5.6.1 live status widths: count=" + statuses.length +
      " labelWidth=" + label.width.toFixed(2) + " fontPx=" + label.font.pixelSize +
      " max=" + maxWidth.toFixed(2) + " worst=" + JSON.stringify(worst) +
      " margin=" + (label.width - maxWidth).toFixed(2) +
      " truncated=" + (badTrunc.length > 0) + " overWidth=" + badWidth.length)
    check("v3.5.6.1: every enumerated sync status fits the live-path label with the real theme font (100% clip incident)",
      label.visible && badWidth.length === 0 && badTrunc.length === 0)
  }

  Component.onCompleted: fillLibrary()
  Timer { interval: 1200; running: true; repeat: false; onTriggered: { panel.open(); log("opened=" + panel.opened) } }
  Timer { interval: 1900; running: true; repeat: false; onTriggered: { svc.status = svc.syncStatusText(100); log("status=" + JSON.stringify(svc.status)) } }
  Timer { interval: 2600; running: true; repeat: false; onTriggered: runStatusCheck() }
  Timer {
    interval: 3200; running: true; repeat: false
    onTriggered: {
      var label = labelItem(), card = cardItem()
      if (!card || typeof card.grabToImage !== "function") {
        check("v3.5.6.1: the live-path 100% capture shows the full string, not truncated", false)
        summary(); return
      }
      card.grabToImage(function(result) {
        var ok = result.saveToFile("/tmp/omatime-v3561-live-100.png")
        log("capture saved=" + ok + " " + result.width + "x" + result.height +
          " text=" + JSON.stringify(label ? label.text : "") +
          " implicitWidth=" + (label ? label.implicitWidth.toFixed(2) : "?") +
          " width=" + (label ? label.width.toFixed(2) : "?") +
          " truncated=" + (label ? label.truncated : "?"))
        check("v3.5.6.1: the live-path 100% capture shows the full string, not truncated",
          ok && !!label && label.visible && label.text === svc.syncStatusText(100) &&
          !label.truncated && label.implicitWidth <= label.width + 0.5)
        summary()
      })
    }
  }
  function summary() {
    log("v3.5.6.1 live checks=" + checks)
    log("FAILS=" + fails)
    Qt.quit()
  }
}
