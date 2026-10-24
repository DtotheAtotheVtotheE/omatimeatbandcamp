//@ pragma OmarchyLoadPatch
// QML interaction tests for the plugin window. Run via tests/qml/run.sh, which builds a throwaway
// copy of the Omarchy shell (KeyboardPanel stubbed, plugin symlinked as "plug", fake HOME) and runs
// this file with quickshell on the offscreen platform. Output: "HARNESS PASS|FAIL <name>" lines.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "plug" as Plug

ShellRoot {
  id: host

  Plug.Service { id: svc }

  QtObject {
    id: fakeBar
    property var shell: QtObject { function serviceFor(id) { return svc } }
    property color foreground: Color.foreground
    property color barForeground: Color.foreground
    property color urgent: Color.urgent
    property string fontFamily: Style.font.family
    property string position: "top"
    property int barSize: 30
    property bool vertical: false
    property var activePopout: null
    property var clickTargets: []
    function requestPopout(k) { activePopout = k }
    function releasePopout(k) { if (activePopout === k) activePopout = null }
    function targetBelongsToWindow() { return true }
    function showTooltip() {}
    function hideTooltip() {}
  }

  FloatingWindow {
    id: barWin
    implicitWidth: 1000; implicitHeight: 780
    color: Color.background
    Rectangle {
      id: stage
      anchors.fill: parent
      color: Color.background
      TestCase { id: tc; name: "h"; when: windowShown }
      Plug.Panel {
        id: panel
        bar: fakeBar
        anchors.top: parent.top
        width: 60; height: 30
      }
    }
  }

  function log(m) { console.log("HARNESS " + m) }
  property int fails: 0
  property var seen: null
  Connections { target: svc; function onRefreshingChanged() { if (svc.refreshing) { var b = host.button('Refresh'); host.seen = { enabled: b.enabled, spin: b.iconSpinning, op: b.opacity } } } }
  function check(name, cond) { if (!cond) fails++; log((cond ? "PASS " : "FAIL ") + name) }

  function find(item, pred) {
    if (!item) return null
    if (pred(item)) return item
    var kids = item.children
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], pred); if (r) return r }
    return null
  }
  function button(textOrIcon) {
    return find(stage, function(it) { return it.hasOwnProperty("iconText") && it.hasOwnProperty("bordered") && (it.text === textOrIcon || it.iconText === textOrIcon) && it.visible })
  }
  function allButtons(item, out) {
    if (!item) return out
    if (item.hasOwnProperty("iconText") && item.hasOwnProperty("bordered") && item.visible) out.push(item)
    var kids = item.children
    for (var i = 0; i < kids.length; i++) allButtons(kids[i], out)
    return out
  }
  function allStrings(item, out) {
    if (!item) return out
    if (typeof item.text === "string") out.push(item.text)
    if (typeof item.tooltipText === "string") out.push(item.tooltipText)
    if (typeof item.iconText === "string") out.push(item.iconText)
    var kids = item.children
    for (var i = 0; i < kids.length; i++) allStrings(kids[i], out)
    return out
  }
  function shuffleButtons() {
    var out = []
    var all = allButtons(stage, [])
    for (var i = 0; i < all.length; i++) if (/shuffle/i.test(all[i].text) || /shuffle/i.test(all[i].tooltipText)) out.push(all[i])
    return out
  }
  function mk(prefix, n) {
    var a = []
    for (var i = 0; i < n; i++) a.push({ title: prefix + i, artist: "x", album: prefix })  // no streamUrl: nothing can ever reach mpv
    return a
  }
  function sameOrder(a, b) {
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }
  function samePermutation(a, b) {
    if (a.length !== b.length) return false
    var seen = {}
    for (var i = 0; i < a.length; i++) seen[a[i].title] = (seen[a[i].title] || 0) + 1
    for (var j = 0; j < b.length; j++) { if (!seen[b[j].title]) return false; seen[b[j].title]-- }
    return true
  }
  function searchField() { return find(stage, function(it) { return it.hasOwnProperty("placeholderText") }) }
  function click(item) { tc.mouseClick(item) }
  function key(k, text) { tc.keyClick(k, Qt.NoModifier) }
  function typeText(t) { for (var i = 0; i < t.length; i++) tc.keyClick(t.charAt(i)) }

  property var steps: [
    function() { panel.open() },
    function() {
      check("panel opened", panel.opened)
      log("library as the plugin loaded it from the cache: " + button("Albums (" + svc.collection.length + ")").text + " / Playlists (" + svc.playlists.length + ")")
      check("search field has focus on open", searchField().activeFocus)
      check("no close (X) button anywhere", !find(stage, function(it) { return it.hasOwnProperty("iconText") && it.iconText === "\u2715" }))
      check("no clear-session icon in header", !find(stage, function(it) { return it.hasOwnProperty("iconText") && it.iconText === "\uF08B" && it.visible }))
      check("Refresh is a labelled toolbar button with icon", !!button("Refresh") && button("Refresh").iconText !== "")
    },
    function() {
      var bs = allButtons(stage, [])
      var hs = {}, ic = {}, bd = {}
      for (var i = 0; i < bs.length; i++) { hs[Math.round(bs[i].height)] = 1; ic[bs[i].iconSize] = 1; bd[bs[i].bordered] = 1 }
      log("buttons=" + bs.length + " heights=" + Object.keys(hs) + " iconSizes=" + Object.keys(ic) + " bordered=" + Object.keys(bd) + " controlHeight=" + Style.spacing.controlHeight + " space16=" + Style.space(16))
      check("9 buttons in the open window (Play all is gone)", bs.length === 9)
      check("all buttons share ONE height (controlHeight)", Object.keys(hs).length === 1 && Object.keys(hs)[0] == Style.spacing.controlHeight)
      check("all buttons share ONE icon size (16)", Object.keys(ic).length === 1 && Object.keys(ic)[0] == Style.space(16))
      check("all buttons bordered (one border style)", Object.keys(bd).length === 1 && Object.keys(bd)[0] === "true")
    },
    // Esc, nothing else open -> closes window
    function() { key(Qt.Key_Escape) },
    function() { check("Esc closes the window", !panel.opened); panel.open() },
    // Esc with search text -> clears first
    function() { typeText("zz") },
    function() { check("typing reaches search", svc.searchQuery === "zz") },
    function() { key(Qt.Key_Escape) },
    function() { check("first Esc clears search, window stays", svc.searchQuery === "" && panel.opened); key(Qt.Key_Escape) },
    function() { check("second Esc closes", !panel.opened); panel.open() },
    // overflow menu
    function() { click(button("\uf141")) },
    function() { check("menu opens", panel.menuOpen); key(Qt.Key_Escape) },
    function() { check("Esc closes ONLY the menu", !panel.menuOpen && panel.opened); check("focus returns to search", searchField().activeFocus) },
    function() { click(button("\uf141")) },
    function() { check("menu reopened", panel.menuOpen); click(button("\uf141")) },
    function() { check("clicking the menu button again closes it (toggle)", !panel.menuOpen && panel.opened); click(button("\uf141")) },
    function() { tc.mouseClick(stage, 150, 520) },
    function() { check("click outside the menu card closes it, window stays, nothing underneath was clicked", !panel.menuOpen && panel.opened && panel.selectedAlbum === null) },
    // ---- Phase 3: no Play all, one Shuffle toggle, per-context ----------------
    function() {
      var strings = allStrings(stage, [])
      var hit = strings.filter(function(t) { return /play\s*all/i.test(t) })
      check("no Play-all control anywhere in the item tree (text/tooltip, visible or not)", hit.length === 0)
      check("Service has no playAll()", typeof svc.playAll === "undefined")
      check("exactly one Shuffle control in the window", shuffleButtons().length === 1)
      check("no cycle-through-states left (panel.cycleShuffle, svc.shuffleMode, svc.shuffleLabel, old svc.setShuffle(mode) all gone)",
        typeof panel.cycleShuffle === "undefined" && typeof svc.shuffleMode === "undefined" && typeof svc.shuffleLabel === "undefined" && typeof svc.shuffleNames === "undefined")
    },
    function() {
      // press the SAME control 7 times: it must only ever show two distinct states, strictly alternating
      var labels = [], sel = []
      for (var i = 0; i < 7; i++) {
        var b = shuffleButtons()[0]
        labels.push(b.text); sel.push(b.selected)
        click(b)
      }
      var distinct = {}
      for (var j = 0; j < labels.length; j++) distinct[labels[j]] = 1
      log("shuffle labels over 7 presses: " + JSON.stringify(labels))
      check("Shuffle shows exactly two labels: Shuffle: Off / Shuffle: On", Object.keys(distinct).sort().join("|") === "Shuffle: Off|Shuffle: On")
      check("Shuffle strictly alternates Off,On,Off,On,... starting Off", labels.join(",") === "Shuffle: Off,Shuffle: On,Shuffle: Off,Shuffle: On,Shuffle: Off,Shuffle: On,Shuffle: Off")
      check("Shuffle is highlighted (selected) exactly when On", sel.join(",") === "false,true,false,true,false,true,false")
      check("after an odd number of presses the toggle is On and the service agrees", shuffleButtons()[0].text === "Shuffle: On" && svc.isShuffled("library"))
      click(shuffleButtons()[0])
      check("one more press returns to Off", shuffleButtons()[0].text === "Shuffle: Off" && !svc.isShuffled("library"))
    },
    // per-context independence through the real UI
    function() {
      var albA = svc.collection[0], albB = svc.collection[1], pl = svc.playlists[0]
      var kA = "album:" + albA.id, kB = "album:" + albB.id, kP = "playlist:" + pl.id
      panel.pickAlbum(albA)
      check("selecting an album switches the context to that album", panel.contextKey === kA)
      check("album context starts Off", shuffleButtons()[0].text === "Shuffle: Off")
      click(shuffleButtons()[0])
      check("toggling in the album context turns the album On", shuffleButtons()[0].text === "Shuffle: On" && svc.isShuffled(kA))
      panel.pickPlaylist(pl)
      check("selecting a playlist switches the context to that playlist", panel.contextKey === kP)
      check("playlist context still Off after toggling the album (button and service)", shuffleButtons()[0].text === "Shuffle: Off" && !svc.isShuffled(kP))
      check("whole-library context also untouched", !svc.isShuffled("library"))
      click(shuffleButtons()[0])
      check("playlist now On", svc.isShuffled(kP) && shuffleButtons()[0].text === "Shuffle: On")
      check("...and the album is still On (independent states)", svc.isShuffled(kA))
      panel.pickAlbum(albA)
      check("returning to the album shows its own remembered On", shuffleButtons()[0].text === "Shuffle: On")
      click(shuffleButtons()[0])
      check("turning the album Off leaves the playlist On", !svc.isShuffled(kA) && svc.isShuffled(kP))
      panel.pickAlbum(albB)
      check("a different album has its own state (Off)", panel.contextKey === kB && shuffleButtons()[0].text === "Shuffle: Off")
      svc.setShuffle(kP, false)
      check("state reset for the next checks", !svc.isShuffled(kA) && !svc.isShuffled(kP) && !svc.isShuffled(kB))
    },
    // real queue behaviour (synthetic tracks without stream URLs)
    function() {
      var A = mk("a", 12), P = mk("p", 12)
      var kA = "album:harness-a", kP = "playlist:harness-p"
      svc.setShuffle(kA, true); svc.setShuffle(kP, false)

      var differs = false, firstOk = true, permOk = true
      for (var r = 0; r < 5 && !differs; r++) {
        svc.playContext("album", "A", A, 5, kA)
        firstOk = firstOk && svc.queue[0] === A[5] && svc.queueIndex === 0
        permOk = permOk && samePermutation(svc.queue, A)
        differs = !sameOrder(svc.queue, A)
      }
      check("album shuffle On: clicked track plays first", firstOk)
      check("album shuffle On: queue holds exactly the album's tracks", permOk)
      check("album shuffle On: order actually differs from album order", differs)

      svc.playContext("playlist", "P", P, 5, kP)
      check("playlist Off (album is On): queue is the playlist in order, starting at the clicked track",
        sameOrder(svc.queue, P) && svc.queueIndex === 5)

      var snap = svc.queue.slice(), snapIdx = svc.queueIndex
      svc.toggleShuffle(kA)   // album context toggled while the PLAYLIST is playing
      check("toggling the album while the playlist plays leaves the playing queue untouched", sameOrder(svc.queue, snap) && svc.queueIndex === snapIdx)
      svc.toggleShuffle(kA)

      svc.toggleShuffle(kP)   // the playing context's own toggle reorders it, current track keeps playing
      check("toggling the PLAYING playlist On shuffles its queue and keeps the current track playing",
        svc.queue[svc.queueIndex] === P[5] && samePermutation(svc.queue, P))
      svc.toggleShuffle(kP)
      check("toggling it Off restores playlist order at the same track", sameOrder(svc.queue, P) && svc.queueIndex === 5)

      svc.playContext("album", "A", A, 5, kA)
      var snapA = svc.queue.slice(), idxA = svc.queueIndex
      svc.toggleShuffle(kP)   // playlist toggled while the ALBUM plays
      check("toggling the playlist while the album plays leaves the album queue untouched", sameOrder(svc.queue, snapA) && svc.queueIndex === idxA)
      svc.setShuffle(kA, false); svc.setShuffle(kP, false)
    },
    // whole-library context + footer Play with nothing loaded + Albums/Playlists live counts
    function() {
      svc.queue = []; svc.queueIndex = -1
      panel.selectedAlbum = null; panel.selectedPlaylist = null
      svc.playlists = []   // harness only: leaves no playlist tracks with real stream URLs, so nothing can reach mpv
      svc.collection = [{ id: "h1", type: "album", title: "H1", artist: "x", tracks: mk("h", 12) }, { id: "h2", type: "album", title: "H2", artist: "y", tracks: [] }]
      check("nothing selected: context is the whole library", panel.contextKey === "library")
      check("Albums (N) label is live: shows the new collection size", !!button("Albums (2)"))
      check("Playlists (N) label is live: shows the new playlist count", !!button("Playlists (0)"))
      var pb = button("\uf04b")
      click(pb)
      check("idle footer Play starts the CURRENT context (whole library) in order when Shuffle is Off",
        svc.context.type === "library" && svc.context.key === "library" && svc.queue.length === 12 && svc.queue[0].title === "h0" && svc.queueIndex === 0)
      svc.queue = []; svc.queueIndex = -1
      click(shuffleButtons()[0])
      check("library Shuffle On via the toolbar", svc.isShuffled("library") && shuffleButtons()[0].text === "Shuffle: On")
      var libDiffers = false
      for (var r = 0; r < 5 && !libDiffers; r++) { svc.queue = []; svc.queueIndex = -1; click(button("\uf04b")); libDiffers = !(svc.queue.map(function(t) { return t.title }).join() === mk("h", 12).map(function(t) { return t.title }).join()) }
      check("idle footer Play with library Shuffle On plays the library in a shuffled order", svc.queue.length === 12 && libDiffers)
      click(shuffleButtons()[0])
      svc.queue = []; svc.queueIndex = -1
      panel.selectedAlbum = svc.collection[0]
      check("with an album selected the context is that album", panel.contextKey === "album:h1")
      click(button("\uf04b"))
      check("idle footer Play with an album selected plays that album only", svc.context.type === "album" && svc.context.key === "album:h1" && svc.queue.length === 12)
      // Albums / Playlists view switch
      var ab = button("Albums (2)"), pbt = button("Playlists (0)")
      click(pbt)
      var leftList = find(stage, function(it) { return it.hasOwnProperty("count") && it.hasOwnProperty("delegate") })
      check("Playlists button switches the view and is highlighted", svc.activeTab === 1 && pbt.selected === true && ab.selected === false)
      check("...and the left list now shows the playlists (0 here), not the albums (2)", leftList.count === 0)
      click(ab)
      check("Albums button switches back and is highlighted", svc.activeTab === 0 && ab.selected === true && pbt.selected === false)
      check("...and the left list shows the 2 albums again", leftList.count === 2)
      check("both view-switch buttons are shared BcButton style (height, icon size, bordered)",
        ab.height === Style.spacing.controlHeight && pbt.height === Style.spacing.controlHeight && ab.bordered && pbt.bordered && ab.iconSize === Style.space(16))
      svc.collection = svc.collection.slice(0, 1)
      check("Albums (N) follows the data (live)", !!button("Albums (1)"))
      svc.queue = []; svc.queueIndex = -1
    },
    // logout flow: cancel paths
    function() { click(button("\uf141")) },
    function() { click(button("Log out / Clear Bandcamp session")) },
    function() { check("menu item opens confirmation (does not log out yet)", panel.logoutConfirmOpen && !panel.menuOpen && svc.status !== "Cleared imported session"); key(Qt.Key_Escape) },
    function() { check("Esc cancels confirmation, window stays, no logout", !panel.logoutConfirmOpen && panel.opened && svc.status !== "Cleared imported session"); click(button("\uf141")) },
    function() { key(Qt.Key_Return) },
    function() { check("Enter on open menu activates item", panel.logoutConfirmOpen); key(Qt.Key_Return) },
    function() { check("Enter on confirmation = preselected Cancel: no logout", !panel.logoutConfirmOpen && svc.status !== "Cleared imported session") },
    // logout flow: confirm
    function() { click(button("\uf141")) },
    function() { click(button("Log out / Clear Bandcamp session")) },
    function() { key(Qt.Key_Right) },
    function() { key(Qt.Key_Return) },
    function() { check("confirming runs clearCookies", !panel.logoutConfirmOpen && svc.status === "Cleared imported session"); check("window stays open after logout", panel.opened) },
    // refresh
    function() { click(button("Refresh")) },
    function() { },
    function() { },
    function() { },
    function() {
      check("refreshing became true after click", !!seen)
      check("at that moment: button disabled", seen && seen.enabled === false)
      check("at that moment: icon spinning", seen && seen.spin === true)
      check("at that moment: button dimmed", seen && seen.op < 1)
    },
    function() {
      var b = button("Refresh")
      check("refresh finished: not refreshing", !svc.refreshing)
      check("refresh button re-enabled and still", b && b.enabled === true && b.iconSpinning === false)
      log("status after refresh: " + JSON.stringify(svc.status))
    },
    function() { log("FAILS=" + fails); Qt.quit() }
  ]
  property int si: 0
  Timer {
    id: runner; interval: 500; repeat: true
    onTriggered: { if (host.si < host.steps.length) { var i = host.si; host.si++; try { host.steps[i]() } catch (e) { host.fails++; host.log('FAIL step ' + i + ' threw: ' + e) } } }
  }
  Timer { id: startDelay; interval: 1500; onTriggered: runner.start() }
  Component.onCompleted: { log("loaded"); startDelay.start() }
}
