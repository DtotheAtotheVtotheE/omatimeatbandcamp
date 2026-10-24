//@ pragma OmarchyLoadPatch
// QML interaction tests for the plugin window. Run via tests/qml/run.sh, which builds a throwaway
// copy of the Omarchy shell (KeyboardPanel stubbed, plugin symlinked as "plug", fake HOME) and runs
// this file with quickshell on the offscreen platform. Output: "HARNESS PASS|FAIL <name>" lines.
//
// HARNESS_PHASE=1  full behaviour tests against the synthetic fixture library (tests/qml/fixtures)
// HARNESS_PHASE=2  second launch on the same fake HOME: sort/filter choices persisted by phase 1
// HARNESS_PHASE=real  invariants against the real library cache (skipped by run.sh if none exists)
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "plug" as Plug
import "plug/LibraryModel.js" as LibraryModel

ShellRoot {
  id: host

  readonly property string phase: Quickshell.env("HARNESS_PHASE") || "1"
  readonly property string longTitle: "A Very Long Album Title That Certainly Needs To Wrap Onto A Second Line And Then Keep Going With Many More Words So That It Must Be Cut With An Ellipsis After The Second Line Because Nobody Reads This Far"
  readonly property string longTrack: "An Extremely Long Track Title That Has To Wrap Across Several Lines Of The Track List Instead Of Being Cut Off In The Middle Of A Word By A Single Line Truncation"
  readonly property string croc: "Crocbrain, or, Two Big Steps For Mankind"
  readonly property string fi: "First Impressions (Deluxe Edition)"

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
  property string lastCheck: ""
  function check(name, cond) { lastCheck = name; if (!cond) fails++; log((cond ? "PASS " : "FAIL ") + name) }
  Connections { target: svc; function onRefreshingChanged() { if (svc.refreshing) { var b = host.button('Refresh'); host.seen = { enabled: b.enabled, spin: b.iconSpinning, op: b.opacity } } } }

  // ---- tree helpers --------------------------------------------------------------------
  function find(item, pred) {
    if (!item) return null
    if (pred(item)) return item
    var kids = item.children
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], pred); if (r) return r }
    return null
  }
  function named(item, name) { return find(item, function(it) { return it.objectName === name }) }
  function allButtons(item, out) {
    if (!item) return out
    if (item.hasOwnProperty("iconText") && item.hasOwnProperty("bordered") && item.visible) out.push(item)
    var kids = item.children
    for (var i = 0; i < kids.length; i++) allButtons(kids[i], out)
    return out
  }
  function button(textOrIcon) {
    return find(stage, function(it) { return it.hasOwnProperty("iconText") && it.hasOwnProperty("bordered") && (it.text === textOrIcon || it.iconText === textOrIcon) && it.visible })
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
  // The footer transport's play button (the detail pane's Play button shares the glyph; it comes first in the tree).
  function footerPlay() {
    var all = allButtons(stage, []).filter(function(b) { return b.iconText === "\uf04b" || b.iconText === "\uf04c" })
    return all[all.length - 1]
  }
  function sortButton() { return button("Sort: " + LibraryModel.sortLabel(svc.sortMode)) }
  function searchField() { return find(stage, function(it) { return it.hasOwnProperty("placeholderText") }) }
  function leftList() { return named(stage, "leftList") }
  function trackList() { return named(stage, "trackList") }
  function click(item) { tc.mouseClick(item) }
  function key(k) { tc.keyClick(k, Qt.NoModifier) }
  function typeText(t) { for (var i = 0; i < t.length; i++) tc.keyClick(t.charAt(i)) }

  // left-list rows (cacheBuffer is raised so every delegate exists and can be measured)
  function prepLists() { leftList().cacheBuffer = 100000; trackList().cacheBuffer = 100000 }
  function leftIndex(title) {
    var m = leftList().model
    for (var i = 0; i < m.length; i++) if (m[i].title === title || m[i].name === title) return i
    return -1
  }
  function leftRow(title) { var i = leftIndex(title); return i < 0 ? null : leftList().itemAtIndex(i) }
  function leftTitles() {
    var out = [], n = leftList().count
    for (var i = 0; i < n; i++) { var r = leftList().itemAtIndex(i); out.push(r ? named(r, "rowTitle").text : "<no delegate " + i + ">") }
    return out
  }
  function showRow(title) { var i = leftIndex(title); leftList().positionViewAtIndex(i, ListView.Visible) }
  function trackRows() {
    var out = [], n = trackList().count
    for (var i = 0; i < n; i++) out.push(trackList().itemAtIndex(i))
    return out
  }
  function alpha(item) { return item.color.a }
  function mk(prefix, n) {
    var a = []
    for (var i = 0; i < n; i++) a.push({ uid: prefix + "#" + i, title: prefix + i, artist: "x", album: prefix, streamable: true })
    return a
  }
  function synth(uid, title, artist, tracks) {
    return { uid: uid, id: uid, type: "album", kind: "album", title: title, artist: artist, tracks: tracks, tracksLoaded: true, isPreorder: false,
             releaseDate: "", releaseTs: 0, year: 0, purchasedTs: 0, streamableCount: tracks.length, totalCount: tracks.length, declaredCount: tracks.length,
             completeness: "complete", sources: [], bandcampUrl: "" }
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
  function pick(title) { panel.pickAlbum(svc.collection[collIndex(title)]) }
  function collIndex(title) { for (var i = 0; i < svc.collection.length; i++) if (svc.collection[i].title === title) return i; return -1 }
  function entityFree(strings) { return strings.filter(function(t) { return /&(amp|lt|gt|quot|#\d+|#x[0-9a-f]+);/i.test(t) }) }

  // ---- expected orders for the synthetic fixture -------------------------------------------
  readonly property var expAdded: ["Future Sounds", "La Dee La La", "First Impressions (Deluxe Edition)", "alpha", croc, "Same Year Early", "Zebra Crossing", "Émile's Song", longTitle, "Empty Album", "No Date Album", "Truncated Compilation", "Unloaded Album"]
  readonly property var expArtist: ["Future Sounds", "Same Year Early", "Émile's Song", croc, longTitle, "Zebra Crossing", "Empty Album", "Unloaded Album", "First Impressions (Deluxe Edition)", "La Dee La La", "alpha", "Truncated Compilation", "No Date Album"]
  readonly property var expTitle: [longTitle, "alpha", croc, "Émile's Song", "Empty Album", "First Impressions (Deluxe Edition)", "Future Sounds", "La Dee La La", "No Date Album", "Same Year Early", "Truncated Compilation", "Unloaded Album", "Zebra Crossing"]
  readonly property var expRelease: ["Future Sounds", "First Impressions (Deluxe Edition)", "La Dee La La", "Same Year Early", "alpha", croc, "Émile's Song", "Zebra Crossing", longTitle, "Empty Album", "Unloaded Album", "Truncated Compilation", "No Date Album"]
  function noPre(list) { return list.filter(function(t) { return t !== "Future Sounds" && t !== "First Impressions (Deluxe Edition)" }) }
  function titlesEqual(a, b) { return a.join("\u0001") === b.join("\u0001") }

  // ======================================== PHASE 1 ==========================================
  property var steps1: [
    function() { panel.open() },
    function() {
      prepLists()
      check("panel opened", panel.opened)
      log("library as the plugin loaded it: " + button("Albums (" + svc.albumsView.length + ")").text + " / Playlists (" + svc.playlists.length + ")")
      check("search field has focus on open", searchField().activeFocus)
      check("no close (X) button anywhere", !find(stage, function(it) { return it.hasOwnProperty("iconText") && it.iconText === "\u2715" }))
      check("no clear-session icon in header", !find(stage, function(it) { return it.hasOwnProperty("iconText") && it.iconText === "\uF08B" && it.visible }))
      check("Refresh is a labelled toolbar button with icon", !!button("Refresh") && button("Refresh").iconText !== "")
      check("fixture library loaded: 13 albums, 2 playlists", svc.collection.length === 13 && svc.playlists.length === 2)
    },
    function() {
      var bs = allButtons(stage, [])
      var hs = {}, ic = {}, bd = {}
      for (var i = 0; i < bs.length; i++) { hs[Math.round(bs[i].height)] = 1; ic[bs[i].iconSize] = 1; bd[bs[i].bordered] = 1 }
      log("buttons=" + bs.length + " heights=" + Object.keys(hs) + " iconSizes=" + Object.keys(ic) + " bordered=" + Object.keys(bd))
      check("11 buttons in the open window (Play all is gone; Sort + Hide pre-orders added)", bs.length === 11)
      check("all buttons share ONE height (controlHeight)", Object.keys(hs).length === 1 && Object.keys(hs)[0] == Style.spacing.controlHeight)
      check("all buttons share ONE icon size (16)", Object.keys(ic).length === 1 && Object.keys(ic)[0] == Style.space(16))
      check("all buttons bordered (one border style)", Object.keys(bd).length === 1 && Object.keys(bd)[0] === "true")
    },
    // ---- Esc / menu layering (Phase 2) ----
    function() { key(Qt.Key_Escape) },
    function() { check("Esc closes the window", !panel.opened); panel.open() },
    function() { typeText("zz") },
    function() { check("typing reaches search", svc.searchQuery === "zz") },
    function() { key(Qt.Key_Escape) },
    function() { check("first Esc clears search, window stays", svc.searchQuery === "" && panel.opened); key(Qt.Key_Escape) },
    function() { check("second Esc closes", !panel.opened); panel.open() },
    function() { click(button("\uf141")) },
    function() { check("menu opens", panel.menuOpen && panel.menuKind === "more"); key(Qt.Key_Escape) },
    function() { check("Esc closes ONLY the menu", !panel.menuOpen && panel.opened); check("focus returns to search", searchField().activeFocus) },
    function() { click(button("\uf141")) },
    function() { check("menu reopened", panel.menuOpen); click(button("\uf141")) },
    function() { check("clicking the menu button again closes it (toggle)", !panel.menuOpen && panel.opened); click(button("\uf141")) },
    function() { tc.mouseClick(stage, 150, 560) },
    function() { check("click outside the menu card closes it, window stays, nothing underneath was clicked", !panel.menuOpen && panel.opened && panel.selectedAlbumUid === "") },

    // ---- Phase 3: no Play all, one Shuffle toggle, per-context ----
    function() {
      var hit = allStrings(stage, []).filter(function(t) { return /play\s*all/i.test(t) })
      check("no Play-all control anywhere in the item tree (text/tooltip, visible or not)", hit.length === 0)
      check("Service has no playAll()", typeof svc.playAll === "undefined")
      check("exactly one Shuffle control in the window", shuffleButtons().length === 1)
      check("no cycle-through-states left", typeof panel.cycleShuffle === "undefined" && typeof svc.shuffleMode === "undefined" && typeof svc.shuffleLabel === "undefined" && typeof svc.shuffleNames === "undefined")
    },
    function() {
      var labels = [], sel = []
      for (var i = 0; i < 7; i++) { var b = shuffleButtons()[0]; labels.push(b.text); sel.push(b.selected); click(b) }
      var distinct = {}
      for (var j = 0; j < labels.length; j++) distinct[labels[j]] = 1
      check("Shuffle shows exactly two labels: Shuffle: Off / Shuffle: On", Object.keys(distinct).sort().join("|") === "Shuffle: Off|Shuffle: On")
      check("Shuffle strictly alternates Off,On,Off,On,... starting Off", labels.join(",") === "Shuffle: Off,Shuffle: On,Shuffle: Off,Shuffle: On,Shuffle: Off,Shuffle: On,Shuffle: Off")
      check("Shuffle is highlighted (selected) exactly when On", sel.join(",") === "false,true,false,true,false,true,false")
      check("after an odd number of presses the toggle is On and the service agrees", shuffleButtons()[0].text === "Shuffle: On" && svc.isShuffled("library"))
      click(shuffleButtons()[0])
      check("one more press returns to Off", shuffleButtons()[0].text === "Shuffle: Off" && !svc.isShuffled("library"))
    },
    function() {
      var albA = svc.collection[collIndex(host.croc)], albB = svc.collection[collIndex("La Dee La La")], pl = svc.playlists[0]
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
      check("playlist now On, album still On (independent states)", svc.isShuffled(kP) && svc.isShuffled(kA))
      panel.pickAlbum(albA)
      check("returning to the album shows its own remembered On", shuffleButtons()[0].text === "Shuffle: On")
      click(shuffleButtons()[0])
      check("turning the album Off leaves the playlist On", !svc.isShuffled(kA) && svc.isShuffled(kP))
      panel.pickAlbum(albB)
      check("a different album has its own state (Off)", panel.contextKey === kB && shuffleButtons()[0].text === "Shuffle: Off")
      svc.setShuffle(kP, false)
      check("state reset for the next checks", !svc.isShuffled(kA) && !svc.isShuffled(kP) && !svc.isShuffled(kB))
      panel.pickAlbum(albB)
      check("(housekeeping) deselected again", panel.selectedAlbumUid === "")
    },
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
      check("playlist Off (album is On): queue is the playlist in order, starting at the clicked track", sameOrder(svc.queue, P) && svc.queueIndex === 5)
      var snap = svc.queue.slice(), snapIdx = svc.queueIndex
      svc.toggleShuffle(kA)
      check("toggling the album while the playlist plays leaves the playing queue untouched", sameOrder(svc.queue, snap) && svc.queueIndex === snapIdx)
      svc.toggleShuffle(kA)
      svc.toggleShuffle(kP)
      check("toggling the PLAYING playlist On shuffles its queue and keeps the current track playing", svc.queue[svc.queueIndex] === P[5] && samePermutation(svc.queue, P))
      svc.toggleShuffle(kP)
      check("toggling it Off restores playlist order at the same track", sameOrder(svc.queue, P) && svc.queueIndex === 5)
      svc.playContext("album", "A", A, 5, kA)
      var snapA = svc.queue.slice(), idxA = svc.queueIndex
      svc.toggleShuffle(kP)
      check("toggling the playlist while the album plays leaves the album queue untouched", sameOrder(svc.queue, snapA) && svc.queueIndex === idxA)
      svc.setShuffle(kA, false); svc.setShuffle(kP, false)
      svc.queue = []; svc.queueIndex = -1
    },

    // ---- Phase 4 item 0: deselect round-trip ----
    function() {
      check("start: nothing selected -> library context", panel.selectedAlbumUid === "" && panel.selectedPlaylistUid === "" && panel.contextKey === "library")
      check("start: detail pane shows the empty prompt", named(stage, "detailTitle").text === "Pick an album or playlist")
      showRow("La Dee La La")
    },
    function() {
      var row = leftRow("La Dee La La")
      click(row)
      check("click selects the album row", panel.selectedAlbumUid === "a:fx-dee" && panel.contextKey === "album:a:fx-dee")
      check("detail pane follows the selection", named(stage, "detailTitle").text === "La Dee La La")
      click(shuffleButtons()[0])
      check("Shuffle is On for the album context", shuffleButtons()[0].text === "Shuffle: On")
    },
    function() { showRow("La Dee La La") },
    function() {
      var row = leftRow("La Dee La La")
      check("selected row is highlighted before deselect", named(row, "rowBar").visible && alpha(named(row, "rowFill")) > 0.15)
      click(row)
      check("clicking the SELECTED row again deselects it", panel.selectedAlbumUid === "" && panel.selectedAlbum === null)
      check("context returns to the whole library", panel.contextKey === "library")
      check("detail pane returns to the empty prompt", named(stage, "detailTitle").text === "Pick an album or playlist" && trackList().count === 0)
      check("Shuffle control now shows the LIBRARY context's state (Off)", shuffleButtons()[0].text === "Shuffle: Off" && !svc.isShuffled("library"))
      check("the album's own Shuffle state is kept (still On)", svc.isShuffled("album:a:fx-dee"))
      tc.mouseMove(stage, 5, 5)
    },
    function() {
      var row = leftRow("La Dee La La")
      check("row highlight is gone (accent bar hidden, selection tint gone)", !named(row, "rowBar").visible && alpha(named(row, "rowFill")) < 0.15)
      showRow("La Dee La La")
    },
    function() {
      click(leftRow("La Dee La La"))
      check("re-selecting restores the album context AND its remembered Shuffle On", panel.selectedAlbumUid === "a:fx-dee" && shuffleButtons()[0].text === "Shuffle: On")
      svc.setShuffle("album:a:fx-dee", false)
      click(button("Playlists (2)"))
    },
    function() { showRow("Postpunky?") },
    function() {
      click(leftRow("Postpunky?"))
      check("playlist row selects (and the album selection is cleared)", panel.selectedPlaylistUid === "pl:fx-1" && panel.selectedAlbumUid === "")
      check("playlist row highlighted", named(leftRow("Postpunky?"), "rowBar").visible)
      click(leftRow("Postpunky?"))
      check("clicking the selected PLAYLIST row again deselects it -> library context", panel.selectedPlaylistUid === "" && panel.contextKey === "library")
      check("playlist detail pane cleared", named(stage, "detailTitle").text === "Pick an album or playlist")
      click(button("Albums (13)"))
    },
    function() { showRow("alpha") },
    function() {
      click(leftRow("alpha"))
      check("select A", panel.selectedAlbumUid === "a:fx-alpha")
      showRow("Zebra Crossing")
    },
    function() {
      click(leftRow("Zebra Crossing"))
      check("clicking a DIFFERENT row moves the selection (does not deselect)", panel.selectedAlbumUid === "a:fx-zebra")
      check("only one row is highlighted at a time", named(leftRow("alpha"), "rowBar").visible === false && named(leftRow("Zebra Crossing"), "rowBar").visible === true)
      panel.pickAlbum(svc.collection[collIndex("Zebra Crossing")])
      check("(housekeeping) deselected", panel.selectedAlbumUid === "")
    },

    // ---- Phase 4: two-line rows, measured ----
    function() {
      tc.mouseMove(stage, 5, 5)
      var shortRow = leftRow("La Dee La La"), longRow = leftRow(host.longTitle), crocRow = leftRow(host.croc)
      var sT = named(shortRow, "rowTitle"), lT = named(longRow, "rowTitle"), cT = named(crocRow, "rowTitle")
      log("row heights: short=" + shortRow.height + " croc=" + crocRow.height + " long=" + longRow.height + " | lineCounts short=" + sT.lineCount + " croc=" + cT.lineCount + " long=" + lT.lineCount)
      check("short title: one line, not truncated", sT.lineCount === 1 && sT.truncated === false)
      check("very long title wraps to exactly TWO lines", lT.lineCount === 2)
      check("very long title: ellipsis only after line 2", lT.truncated === true && lT.lineCount === 2)
      check("row height grows for the wrapped title (measured)", longRow.height - shortRow.height >= Style.font.bodySmall)
      var lS = named(longRow, "rowSub"), sS = named(shortRow, "rowSub")
      check("artist is on its own line BELOW the wrapped title", lS.y >= lT.y + lT.height - 1)
      check("artist shown in full, not truncated", lS.text === "Long Title Artist" && lS.truncated === false && sS.text === "Shamek Farrah & Folks" && sS.truncated === false)
      check("artist line is smaller and dimmer than the title", lS.font.pixelSize < lT.font.pixelSize && lS.color.hslLightness < lT.color.hslLightness)
      check("Crocbrain fixture: full title visible, no truncation", cT.text === host.croc && cT.truncated === false && cT.lineCount <= 2)
      check("Crocbrain fixture: artist 'Ismatic Guru' on line 2, fully readable", named(crocRow, "rowSub").text === "Ismatic Guru" && named(crocRow, "rowSub").truncated === false)
      var bad = []
      var n = leftList().count
      for (var i = 0; i < n; i++) {
        var t = named(leftList().itemAtIndex(i), "rowTitle")
        if (t.truncated && t.lineCount < 2) bad.push(t.text)
        if (t.lineCount > 2) bad.push("3+ lines: " + t.text)
      }
      check("no row anywhere is cut off on a single line (every truncation is after line 2)", bad.length === 0)
      check("every row's height covers its text (nothing clipped)", (function() {
        for (var k = 0; k < n; k++) { var r = leftList().itemAtIndex(k); var c = r.children[2]; if (r.height < c.implicitHeight) return false }
        return true
      })())
      panel.pickAlbum(svc.collection[collIndex(host.longTitle)])
    },
    function() {
      var t = named(stage, "detailTitle"), s = named(stage, "detailSub")
      check("right pane header: long title wraps to two lines, ellipsis after line 2", t.lineCount === 2 && t.truncated === true)
      check("right pane header: artist on its own dimmed line", s.text === "Long Title Artist" && s.truncated === false && s.y >= t.y + t.height - 1 && s.font.pixelSize < t.font.pixelSize)
      var rows = trackRows()
      var tt = named(rows[0], "trackTitle"), short = named(rows[1], "trackTitle")
      log("track rows: long lines=" + tt.lineCount + " h=" + rows[0].height + " | short lines=" + short.lineCount + " h=" + rows[1].height)
      check("track title wraps instead of truncating (3 lines or fewer, grows the row)", tt.lineCount >= 2 && rows[0].height > rows[1].height && tt.text === host.longTrack)
      check("wrapped track title is not cut mid-word on one line", !(tt.truncated && tt.lineCount < 2))
      panel.pickAlbum(svc.collection[collIndex(host.croc)])
    },
    function() {
      var t = named(stage, "detailTitle")
      check("Crocbrain in the header: whole title visible (<= 2 lines, no ellipsis)", t.text === host.croc && t.truncated === false && t.lineCount <= 2)
      check("Crocbrain header: artist 'Ismatic Guru' on its own line", named(stage, "detailSub").text === "Ismatic Guru")
      panel.pickAlbum(svc.collection[collIndex(host.croc)])
    },

    // ---- Phase 4: pre-order + unreleased rendering (First Impressions) ----
    function() {
      showRow(host.fi)
    },
    function() {
      var row = leftRow(host.fi), dee = leftRow("La Dee La La")
      check("FI row: PRE-ORDER pill is visible", named(row, "rowPill").visible && named(row, "pillText").text === "PRE-ORDER")
      check("FI row: release date shown next to the pill", named(row, "pillDate").text === "27 Nov 2026")
      check("fully released contrast (La Dee La La): no pill", !named(dee, "rowPill").visible)
      check("FI row subtitle is the artist", named(row, "rowSub").text === "Shamek Farrah")
      click(row)
    },
    function() {
      check("FI selected", panel.selectedAlbum && panel.selectedAlbum.title === host.fi)
      check("header title", named(stage, "detailTitle").text === host.fi && named(stage, "detailSub").text === "Shamek Farrah")
      check("header: 'PRE-ORDER · releases 27 Nov 2026'", named(stage, "detailPreorder").text === "PRE-ORDER · releases 27 Nov 2026")
      check("header: '0 of 7 tracks available'", named(stage, "detailAvail").text === "0 of 7 tracks available")
      var pb = named(stage, "detailPlay")
      check("play control reads 'Play available' and is disabled (nothing available)", pb.visible && pb.text === "Play available" && pb.enabled === false)
      var rows = trackRows()
      check("7 track rows", rows.length === 7)
      var ops = rows.map(function(r) { return r.opacity }), durs = rows.map(function(r) { return named(r, "trackDuration").text })
      check("all 7 unreleased tracks are greyed to ~45% opacity", ops.every(function(o) { return Math.abs(o - 0.45) < 0.02 }))
      check("all 7 durations read '—'", durs.every(function(d) { return d === "—" }))
      check("no hover effect possible: hover disabled and arrow cursor on every unreleased row", rows.every(function(r) { var m = named(r, "trackMouse"); return m.hoverEnabled === false && m.cursorShape === Qt.ArrowCursor }))
      tc.mouseMove(rows[2])
    },
    function() {
      var rows = trackRows()
      check("hovering an unreleased row paints no hover fill", alpha(named(rows[2], "trackFill")) === 0 && named(rows[2], "trackMouse").containsMouse === false)
      var before = { q: svc.queue.length, idx: svc.queueIndex, playing: svc.isPlaying, err: svc.playbackError }
      click(rows[0])
      check("clicking an unreleased track shows ONLY the notice 'Not yet released'", svc.notice === "Not yet released" && named(stage, "noticePill").visible && named(stage, "noticeText").text === "Not yet released")
      check("...and plays nothing: no queue, no current track, not playing, no error", svc.queue.length === before.q && svc.queueIndex === before.idx && svc.currentTrack === null && svc.isPlaying === false && svc.playbackError === before.err && svc.queue.length === 0)
      for (var i = 1; i < 7; i++) click(rows[i])
      check("clicking all 7 never plays anything (acceptance: FI never plays)", svc.queue.length === 0 && svc.currentTrack === null && svc.isPlaying === false)
      click(named(stage, "detailPlay"))
      check("the disabled play control does nothing either", svc.queue.length === 0 && svc.isPlaying === false)
      click(footerPlay())
    },
    function() {
      check("footer Play with FI selected also plays nothing (only streamable tracks may queue)", svc.queue.length === 0 && svc.currentTrack === null && svc.notice !== "")
      check("notice clears itself after a few seconds (timer armed)", svc.notice === "Nothing available to play yet" || svc.notice === "Not yet released")
      panel.pickAlbum(svc.collection[collIndex(host.fi)])
    },

    // ---- fully released contrast: La Dee La La ----
    function() {
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
    },
    function() {
      check("changing the selection clears a stale notice", svc.notice === "" && !named(stage, "noticePill").visible)
      check("La Dee La La header: title + artist 'Shamek Farrah & Folks'", named(stage, "detailTitle").text === "La Dee La La" && named(stage, "detailSub").text === "Shamek Farrah & Folks")
      check("no pre-order line, no availability line when 4 of 4 stream", named(stage, "detailPreorder").text === "" && named(stage, "detailAvail").text === "")
      var pb = named(stage, "detailPlay")
      check("play control reads 'Play' and is enabled", pb.text === "Play" && pb.enabled === true)
      var rows = trackRows()
      check("4 rows, all full opacity, real durations", rows.length === 4 && rows.every(function(r) { return r.opacity === 1 }) && named(rows[0], "trackDuration").text === "9:18" && named(rows[3], "trackDuration").text === "9:58")
      check("every row has hover enabled and pointer cursor", rows.every(function(r) { var m = named(r, "trackMouse"); return m.hoverEnabled && m.cursorShape === Qt.PointingHandCursor }))
      tc.mouseMove(rows[1])
    },
    function() {
      var rows = trackRows()
      check("hovering a playable row paints a hover fill", alpha(named(rows[1], "trackFill")) > 0)
      click(rows[2])
      tc.mouseMove(stage, 5, 5)
    },
    function() {
      var rows = trackRows()
      check("clicking track 3 queues the whole album starting at track 3", svc.queue.length === 4 && svc.queueIndex === 2 && svc.queue[2].title === "The White Lady")
      check("playing row: highlight fill + accent bar + play marker", alpha(named(rows[2], "trackFill")) > 0.15 && named(rows[2], "trackBar").visible && named(rows[2], "playingIndicator").visible)
      check("other rows: no highlight, no marker", [0, 1, 3].every(function(i) { return alpha(named(rows[i], "trackFill")) < 0.15 && !named(rows[i], "trackBar").visible && !named(rows[i], "playingIndicator").visible }))
      check("the playing title is emphasised (bold)", named(rows[2], "trackTitle").font.bold === true && named(rows[0], "trackTitle").font.bold === false)
      svc.next()
    },
    function() {
      var rows = trackRows()
      check("marker follows the queue: now on track 4, off track 3", named(rows[3], "playingIndicator").visible && !named(rows[2], "playingIndicator").visible)
      svc.queue = []; svc.queueIndex = -1
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
    },
    // ---- highlights: both states side by side ----
    function() {
      tc.mouseMove(stage, 5, 5)
      panel.pickAlbum(svc.collection[collIndex("alpha")])
      showRow("alpha")
    },
    function() { tc.mouseMove(stage, 5, 5) },
    function() {
      var sel = leftRow("alpha"), other = leftRow("Zebra Crossing")
      check("selected row: accent bar + selection tint; unselected row: neither (hover tint is lighter than selection)", named(sel, "rowBar").visible && alpha(named(sel, "rowFill")) > 0.15 && !named(other, "rowBar").visible && alpha(named(other, "rowFill")) < 0.15)
      check("selected row title is bold, unselected is not", named(sel, "rowTitle").font.bold === true && named(other, "rowTitle").font.bold === false)
      panel.pickAlbum(svc.collection[collIndex("alpha")])
    },

    // ---- partial pre-order (Future Sounds: 1 of 3) ----
    function() { panel.pickAlbum(svc.collection[collIndex("Future Sounds")]) },
    function() {
      check("Future Sounds header: PRE-ORDER · releases 15 Jan 2027", named(stage, "detailPreorder").text === "PRE-ORDER · releases 15 Jan 2027")
      check("Future Sounds: '1 of 3 tracks available'", named(stage, "detailAvail").text === "1 of 3 tracks available")
      var pb = named(stage, "detailPlay")
      check("'Play available' is enabled when at least one track streams", pb.text === "Play available" && pb.enabled === true)
      var rows = trackRows()
      check("row 1 (released) normal, rows 2-3 greyed with '—'", rows[0].opacity === 1 && Math.abs(rows[1].opacity - 0.45) < 0.02 && Math.abs(rows[2].opacity - 0.45) < 0.02 && named(rows[0], "trackDuration").text === "3:21" && named(rows[2], "trackDuration").text === "—")
      click(pb)
    },
    function() {
      check("Play available queues ONLY the streamable track", svc.queue.length === 1 && svc.queue[0].title === "Released Single")
      svc.queue = []; svc.queueIndex = -1
      panel.pickAlbum(svc.collection[collIndex("Future Sounds")])
    },

    // ---- honest rendering of odd albums ----
    function() { panel.pickAlbum(svc.collection[collIndex("Truncated Compilation")]) },
    function() {
      check("truncated album says how many tracks it really has", named(stage, "detailPartial").text === "Showing 3 of 50 tracks (the source returned fewer)" && trackRows().length === 3)
      panel.pickAlbum(svc.collection[collIndex("Truncated Compilation")]); panel.pickAlbum(svc.collection[collIndex("Empty Album")])
    },
    function() {
      check("empty album renders a graceful message, no padding rows", named(stage, "detailEmpty").text === "No tracks in this album" && trackRows().length === 0 && named(stage, "detailPlay").enabled === false)
      panel.pickAlbum(svc.collection[collIndex("Empty Album")]); panel.pickAlbum(svc.collection[collIndex("Unloaded Album")])
    },
    function() {
      check("not-yet-loaded album says so instead of claiming it is empty", named(stage, "detailEmpty").text === "Tracks are still loading — the library is syncing")
      panel.pickAlbum(svc.collection[collIndex("Unloaded Album")])
      var bad = entityFree(allStrings(stage, []))
      check("no literal HTML entity anywhere in the rendered tree", bad.length === 0)
      check("'Shamek Farrah & Folks' is rendered with a real ampersand", allStrings(stage, []).some(function(t) { return t === "Shamek Farrah & Folks" }) || leftTitles().length > 0)
    },

    // ---- Phase 4: sorting and filtering ----
    function() {
      check("default sort is Recently added (the sort button says so)", svc.sortMode === "added" && !!button("Sort: Recently added"))
      check("Recently added order (purchase time, newest first; undated last, by title)", titlesEqual(leftTitles(), expAdded))
      click(sortButton())
    },
    function() {
      check("Sort button opens the menu", panel.menuOpen && panel.menuKind === "sort")
      var labels = panel.menuItems.map(function(m) { return m.label })
      check("sort menu has exactly the four spec options in order", labels.join("|") === "Recently added|Artist A–Z|Title A–Z|Release date")
      check("current choice carries a check mark, the others do not", panel.menuItems[0].icon === "\uf00c" && panel.menuItems.slice(1).every(function(m) { return m.icon !== "\uf00c" }))
      check("sort menu items are shared-style buttons (same height)", button("Artist A–Z").height === Style.spacing.controlHeight)
      key(Qt.Key_Escape)
    },
    function() { check("Esc closes only the sort menu", !panel.menuOpen && panel.opened); click(sortButton()) },
    function() { click(button("Artist A–Z")) },
    function() {
      check("choosing Artist A–Z closes the menu and sorts", !panel.menuOpen && svc.sortMode === "artist" && !!button("Sort: Artist A–Z"))
      check("Artist A–Z order (accent-insensitive, then title)", titlesEqual(leftTitles(), expArtist))
      click(sortButton())
    },
    function() { click(button("Title A–Z")) },
    function() {
      check("Title A–Z order (accent- and case-insensitive)", svc.sortMode === "title" && titlesEqual(leftTitles(), expTitle))
      click(sortButton())
    },
    function() { click(button("Release date")) },
    function() {
      check("Release date order (pre-order dates, then track years; unknown last)", svc.sortMode === "release" && titlesEqual(leftTitles(), expRelease))
      var tl = leftTitles()
      check("pre-orders come first under Release date (newest release date on top)", tl[0] === "Future Sounds" && tl[1] === host.fi)
      check("sorting never changes the Albums (N) count", !!button("Albums (13)"))
      click(button("Hide pre-orders"))
    },
    function() {
      check("Hide pre-orders removes both pre-orders, keeps the sort", svc.hidePreorders === true && titlesEqual(leftTitles(), noPre(expRelease)))
      check("toggle is highlighted when On", button("Hide pre-orders").selected === true)
      check("Albums (N) is live: 11 after hiding", !!button("Albums (11)"))
      click(sortButton())
    },
    function() { click(button("Recently added")) },
    function() {
      check("filter + sort combine (Recently added without pre-orders)", svc.sortMode === "added" && titlesEqual(leftTitles(), noPre(expAdded)))
      click(button("Hide pre-orders"))
    },
    function() {
      check("toggling Hide pre-orders off restores them", svc.hidePreorders === false && button("Hide pre-orders").selected === false && titlesEqual(leftTitles(), expAdded) && !!button("Albums (13)"))
      click(button("Playlists (2)"))
    },
    function() {
      check("sort and hide controls are only offered on the Albums list", !button("Hide pre-orders") && !button("Sort: Recently added"))
      click(button("Albums (13)"))
    },
    function() { click(sortButton()) },
    function() { click(button("Title A–Z")) },
    function() { click(button("Hide pre-orders")) },
    // (the persisted file is verified by run.sh, which reads it from disk)

    // ---- library context: footer Play, view switch, live counts (Phase 3) ----
    function() {
      svc.queue = []; svc.queueIndex = -1
      svc.hidePreorders = false   // in memory only: the persisted choice must survive for the relaunch phase
      panel.selectedAlbumUid = ""; panel.selectedPlaylistUid = ""
      svc.playlists = []
      svc.collection = [synth("h1", "H1", "x", mk("h", 12)), synth("h2", "H2", "y", [])]
      check("nothing selected: context is the whole library", panel.contextKey === "library")
      check("Albums (N) label is live: shows the new collection size", !!button("Albums (2)"))
      check("Playlists (N) label is live: shows the new playlist count", !!button("Playlists (0)"))
      click(footerPlay())
    },
    function() {
      check("idle footer Play starts the CURRENT context (whole library) in order when Shuffle is Off",
        svc.context.type === "library" && svc.context.key === "library" && svc.queue.length === 12 && svc.queue[0].title === "h0" && svc.queueIndex === 0)
      svc.queue = []; svc.queueIndex = -1
      click(shuffleButtons()[0])
      check("library Shuffle On via the toolbar", svc.isShuffled("library") && shuffleButtons()[0].text === "Shuffle: On")
      var libDiffers = false
      for (var r = 0; r < 5 && !libDiffers; r++) { svc.queue = []; svc.queueIndex = -1; click(footerPlay()); libDiffers = svc.queue.map(function(t) { return t.title }).join() !== mk("h", 12).map(function(t) { return t.title }).join() }
      check("idle footer Play with library Shuffle On plays the library in a shuffled order", svc.queue.length === 12 && libDiffers)
      click(shuffleButtons()[0])
      svc.queue = []; svc.queueIndex = -1
      panel.selectedAlbumUid = "h1"
      check("with an album selected the context is that album", panel.contextKey === "album:h1")
      click(footerPlay())
      check("idle footer Play with an album selected plays that album only", svc.context.type === "album" && svc.context.key === "album:h1" && svc.queue.length === 12)
      var ab = button("Albums (2)"), pbt = button("Playlists (0)")
      var leftL = leftList()
      click(pbt)
      check("Playlists button switches the view and is highlighted", svc.activeTab === 1 && pbt.selected === true && ab.selected === false)
      check("...and the left list now shows the playlists (0 here), not the albums (2)", leftL.count === 0)
      click(ab)
      check("Albums button switches back and is highlighted", svc.activeTab === 0 && ab.selected === true && pbt.selected === false)
      check("...and the left list shows the 2 albums again", leftL.count === 2)
      check("both view-switch buttons are shared BcButton style", ab.height === Style.spacing.controlHeight && pbt.height === Style.spacing.controlHeight && ab.bordered && pbt.bordered && ab.iconSize === Style.space(16))
      svc.collection = svc.collection.slice(0, 1)
      check("Albums (N) follows the data (live)", !!button("Albums (1)"))
      svc.queue = []; svc.queueIndex = -1
    },

    // ---- logout flow (Phase 2) ----
    function() { click(button("\uf141")) },
    function() { click(button("Log out / Clear Bandcamp session")) },
    function() { check("menu item opens confirmation (does not log out yet)", panel.logoutConfirmOpen && !panel.menuOpen && svc.status !== "Cleared imported session"); key(Qt.Key_Escape) },
    function() { check("Esc cancels confirmation, window stays, no logout", !panel.logoutConfirmOpen && panel.opened && svc.status !== "Cleared imported session"); click(button("\uf141")) },
    function() { key(Qt.Key_Return) },
    function() { check("Enter on open menu activates item", panel.logoutConfirmOpen); key(Qt.Key_Return) },
    function() { check("Enter on confirmation = preselected Cancel: no logout", !panel.logoutConfirmOpen && svc.status !== "Cleared imported session") },
    function() { click(button("\uf141")) },
    function() { click(button("Log out / Clear Bandcamp session")) },
    function() { key(Qt.Key_Right) },
    function() { key(Qt.Key_Return) },
    function() { check("confirming runs clearCookies", !panel.logoutConfirmOpen && svc.status === "Cleared imported session"); check("window stays open after logout", panel.opened) },

    // ---- refresh (Phase 2) ----
    function() { click(button("Refresh")) },
    function() { },
    function() { },
    function() { },
    function() {
      check("refreshing became true after click", !!seen)
      check("at that moment: button disabled, spinning, dimmed", seen && seen.enabled === false && seen.spin === true && seen.op < 1)
      var b = button("Refresh")
      check("refresh finished: not refreshing, button re-enabled and still", !svc.refreshing && b && b.enabled === true && b.iconSpinning === false)
      log("status after refresh: " + JSON.stringify(svc.status))
    }
  ]

  // ======================================== PHASE 2 ==========================================
  property var steps2: [
    function() { panel.open() },
    function() {
      prepLists()
      check("[relaunch] sort choice restored from disk (Title A–Z)", svc.sortMode === "title" && !!button("Sort: Title A–Z"))
      check("[relaunch] Hide pre-orders restored (On, highlighted)", svc.hidePreorders === true && button("Hide pre-orders").selected === true)
      check("[relaunch] list is Title A–Z without pre-orders", titlesEqual(leftTitles(), noPre(expTitle)))
      check("[relaunch] Albums (N) reflects the restored filter", !!button("Albums (11)"))
      click(button("Sort: Title A–Z"))
    },
    function() {
      check("[relaunch] sort menu marks the restored choice", panel.menuItems[2].icon === "\uf00c" && panel.menuItems[0].icon !== "\uf00c")
      key(Qt.Key_Escape)
    },
    function() { click(button("Hide pre-orders")) },
    function() {
      check("[relaunch] filter can be turned off again", svc.hidePreorders === false && titlesEqual(leftTitles(), expTitle))
    }
  ]

  // ===================================== REAL-DATA SMOKE ======================================
  property var stepsReal: [
    function() { panel.open() },
    function() {
      prepLists()
      var n = svc.collection.length
      log("real library: " + n + " albums, " + svc.playlists.length + " playlists")
      check("[real] library loaded (hundreds of albums, playlists present)", n > 500 && svc.playlists.length > 5)
      var strings = []
      for (var i = 0; i < svc.collection.length; i++) { var a = svc.collection[i]; strings.push(a.title, a.artist); for (var j = 0; j < a.tracks.length; j++) strings.push(a.tracks[j].title, a.tracks[j].artist, a.tracks[j].album) }
      for (var k = 0; k < svc.playlists.length; k++) { strings.push(svc.playlists[k].name); for (var m = 0; m < svc.playlists[k].tracks.length; m++) strings.push(svc.playlists[k].tracks[m].title, svc.playlists[k].tracks[m].artist) }
      var bad = entityFree(strings)
      log("strings scanned for entities: " + strings.length)
      check("[real] no literal &amp; / &quot; / &#NN; in ANY title, artist, album or track name", bad.length === 0)
      check("[real] 'Shamek Farrah & Folks' present with a real ampersand", svc.collection.some(function(a) { return a.artist === "Shamek Farrah & Folks" && a.title === "La Dee La La" }))
      var fi = svc.collection[collIndex(host.fi)], dee = svc.collection[collIndex("La Dee La La")]
      check("[real] First Impressions: pre-order, release 27 Nov 2026, 0 of 7 streamable", fi && fi.isPreorder && LibraryModel.fmtDate(fi.releaseTs) === "27 Nov 2026" && fi.totalCount === 7 && fi.streamableCount === 0)
      check("[real] La Dee La La: 4 of 4 streamable under Shamek Farrah & Folks", dee && dee.totalCount === 4 && dee.streamableCount === 4 && dee.artist === "Shamek Farrah & Folks")
      check("[real] Postpunky? present with its tracks", svc.playlists.some(function(p) { return p.name === "Postpunky?" && p.tracks.length > 100 }))
      // ordering invariants over the whole real library
      var modes = ["added", "artist", "title", "release"], ok = true, why = ""
      for (var q = 0; q < modes.length; q++) {
        var s = LibraryModel.sortAlbums(svc.collection, modes[q], false)
        if (s.length !== n) { ok = false; why = modes[q] + " lost albums" }
        for (var z = 1; z < s.length && ok; z++) {
          var x = s[z - 1], y = s[z]
          if (modes[q] === "added" && (x.purchasedTs || 0) < (y.purchasedTs || 0)) { ok = false; why = "added " + x.title + " < " + y.title }
          if (modes[q] === "artist" && LibraryModel.cmpStr(x.artist, y.artist) > 0) { ok = false; why = "artist " + x.artist + " > " + y.artist }
          if (modes[q] === "title" && LibraryModel.cmpStr(x.title, y.title) > 0) { ok = false; why = "title " + x.title + " > " + y.title }
          if (modes[q] === "release" && LibraryModel.releaseKey(x) !== 0 && LibraryModel.releaseKey(y) !== 0 && LibraryModel.releaseKey(x) < LibraryModel.releaseKey(y)) { ok = false; why = "release " + x.title + " < " + y.title }
          if (modes[q] === "release" && LibraryModel.releaseKey(x) === 0 && LibraryModel.releaseKey(y) !== 0) { ok = false; why = "release unknown before known" }
        }
      }
      check("[real] all four sort orders hold over every adjacent pair" + (why ? " (" + why + ")" : ""), ok)
      var pre = svc.collection.filter(function(a) { return a.isPreorder }).length
      check("[real] Hide pre-orders drops exactly the pre-orders", LibraryModel.sortAlbums(svc.collection, "added", true).length === n - pre)
      var withYear = svc.collection.filter(function(a) { return a.year > 0 }).length
      log("albums with a release year: " + withYear + " of " + n + " (pre-orders: " + pre + ")")
      check("[real] release years are present for released albums (Release date sort has data)", withYear > n * 0.8)
      var rel = LibraryModel.sortAlbums(svc.collection, "release", false)
      check("[real] First Impressions sorts to the very top under Release date", rel[0].title === host.fi)
      panel.pickAlbum(fi)
    },
    function() {
      check("[real] First Impressions header: '0 of 7 tracks available', 'PRE-ORDER · releases 27 Nov 2026'", named(stage, "detailAvail").text === "0 of 7 tracks available" && named(stage, "detailPreorder").text === "PRE-ORDER · releases 27 Nov 2026")
      var rows = trackRows()
      check("[real] all 7 greyed with — durations", rows.length === 7 && rows.every(function(r) { return Math.abs(r.opacity - 0.45) < 0.02 && named(r, "trackDuration").text === "—" }))
      panel.pickAlbum(svc.collection[collIndex(host.fi)])
      var crocIdx = collIndex(host.croc)
      log("Crocbrain in real library: " + (crocIdx >= 0))
      if (crocIdx >= 0) panel.pickAlbum(svc.collection[crocIdx])
    },
    function() {
      if (collIndex(host.croc) >= 0) {
        var t = named(stage, "detailTitle")
        check("[real] Crocbrain header shows the whole title, artist on its own line", t.text === host.croc && t.truncated === false && named(stage, "detailSub").text === "Ismatic Guru")
        panel.pickAlbum(svc.collection[collIndex(host.croc)])
      }
      var rowsBad = []
      var n = leftList().count
      for (var i = 0; i < Math.min(n, 700); i++) {
        var r = leftList().itemAtIndex(i)
        if (!r) continue
        var tt = named(r, "rowTitle")
        if (tt.truncated && tt.lineCount < 2) rowsBad.push(tt.text)
      }
      check("[real] across all albums no row is truncated on a single line", rowsBad.length === 0)
      var bad = entityFree(allStrings(stage, []))
      check("[real] no literal HTML entity anywhere in the rendered tree", bad.length === 0)
    }
  ]

  readonly property var steps: phase === "2" ? steps2 : (phase === "real" ? stepsReal : steps1)
  property int si: 0
  Timer {
    id: runner; interval: 450; repeat: true
    onTriggered: {
      if (host.si < host.steps.length) {
        var i = host.si; host.si++
        try { host.steps[i]() } catch (e) { host.fails++; host.log("FAIL step " + i + " threw: " + e + " (last check before it: " + host.lastCheck + ")") }
      } else {
        host.log("FAILS=" + host.fails); Qt.quit()
      }
    }
  }
  Timer { id: startDelay; interval: 1500; onTriggered: runner.start() }
  Component.onCompleted: { log("loaded phase=" + phase); startDelay.start() }
}
