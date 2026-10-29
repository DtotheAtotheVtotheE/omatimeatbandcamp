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
import "plug/UserQueue.js" as UserQueue

ShellRoot {
  id: host

  readonly property string phase: Quickshell.env("HARNESS_PHASE") || "1"
  readonly property string longTitle: "A Very Long Album Title That Certainly Needs To Wrap Onto A Second Line And Then Keep Going With Many More Words So That It Must Be Cut With An Ellipsis After The Second Line Because Nobody Reads This Far"
  readonly property string longTrack: "An Extremely Long Track Title That Has To Wrap Across Several Lines Of The Track List Instead Of Being Cut Off In The Middle Of A Word By A Single Line Truncation"
  readonly property string croc: "Crocbrain, or, Two Big Steps For Mankind"
  readonly property string fi: "First Impressions (Deluxe Edition)"
  // Measured in this harness on the v3 build (commit 68b90f8) with the long
  // now-playing fixture: footer 84 px, popup content height 612 px. v3.1 must
  // stay under this and under the 660 px cap.
  readonly property real v3PopupHeight: 612
  // v3.2 measurements shared between steps.
  property real playingFooterHeight: 0
  property real capPopupHeight: 0
  property real capRowHeight: 0
  // v3.4 user-queue probes.
  property var queueProbe: null
  property var probe: null
  property real upHeightBefore: 0
  // v3.3.1 focus-chain and gear-menu probes.
  property var chain: null
  property var chainFocus: null
  property var menuShot: null
  property bool menuSave: false
  property var headerShot: null
  property bool headerSave: false
  property var syncShot: null
  property bool syncSave: false
  property var headerGeom: null
  property real frameNoQueueHeadY: 0
  // v3.5.4 retry: the live-path regression changes only the stub's surface
  // width and restores it before the screenshot checks.
  property real livePathSavedSurfaceWidth: 0

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
        width: 160; height: 30
      }
    }
  }

  function log(m) { console.log("HARNESS " + m) }
  property int fails: 0
  property var seen: null
  property string lastCheck: ""
  property int artRev1: 0

  Image {
    id: artProbe
    visible: false
    cache: false
    asynchronous: true
    source: "file://" + svc.artPath + "?v=" + svc.artRevision
  }

  // v3.5.5: write a deliberately corrupt queue.json so the restore path reads a
  // real file off disk (the service watches its own queue file).
  FileView {
    id: rawQueueFile
    path: svc.stateDir + "/queue.json"
    atomicWrites: true
    printErrors: false
  }

  // Load the gear-menu screenshot back from disk so the check measures a real
  // rendered bitmap (the grab result's QImage is opaque to JS in QML).
  Image {
    id: menuShotProbe
    visible: false
    cache: false
    asynchronous: true
    source: ""
  }

  // v3.5.4.1: measure every possible status string with the label's exact font
  // without needing a paint/frame between each one. The label width itself is
  // read from the real panel instance in the check below.
  TextMetrics {
    id: statusMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  // Load the full-popup header screenshot back from disk, so its dimensions are
  // the real panel size rather than a scaled or mocked preview.
  Image {
    id: headerShotProbe
    visible: false
    cache: false
    asynchronous: true
    source: ""
  }

  // v3.5.4: the syncing-state screenshot, loaded back the same way.
  Image {
    id: syncShotProbe
    visible: false
    cache: false
    asynchronous: true
    source: ""
  }

  Process {
    id: cmpArt
    property bool same: false
    command: ["cmp", "-s", svc.artPath, svc.placeholderArt]
    onExited: function(code) { cmpArt.same = code === 0 }
  }

  // First-track regression: pause the harness's isolated mpv (as a previous
  // session leaves it) before the Service loads a track. Never touches the
  // user's player: run.sh gives this launch its own OMATIME_MPV_SOCK.
  property int mpvPauseExit: -1
  Process {
    id: mpvPause
    running: false
    command: ["python3", svc.pluginDir + "/mpvctl.py", "pause"]
    onExited: function(code) { host.mpvPauseExit = code }
  }

  // Phase 8 metadata fence: read back exactly what Service.qml publishes to the
  // MPRIS daemon. The state file is the only thing the daemon reads; mpv's
  // credential-bearing `path` is never in it.
  Process {
    id: mprisProbe
    property string text: ""
    command: ["cat", svc.mprisStatePath]
    stdout: StdioCollector { id: mprisOut; waitForEnd: true }
    onExited: function(code) { mprisProbe.text = mprisOut.text }
  }
  function check(name, cond) { lastCheck = name; if (!cond) fails++; log((cond ? "PASS " : "FAIL ") + name) }
  Connections {
    target: svc
    function onRefreshingChanged() {
      if (!svc.refreshing) return
      var b = host.menuItemByText("Refresh")
      host.seen = { enabled: b ? b.enabled : panel.moreItems[0].enabled, spin: b ? b.iconSpinning : panel.moreItems[0].spinning, op: b ? b.opacity : 1 }
    }
  }

  // ---- tree helpers --------------------------------------------------------------------
  function find(item, pred) {
    if (!item) return null
    if (pred(item)) return item
    var kids = item.children
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], pred); if (r) return r }
    return null
  }
  function named(item, name) { return find(item, function(it) { return it.objectName === name }) }
  function allNamed(item, name, out) {
    if (!item) return out
    if (item.objectName === name) out.push(item)
    var kids = item.children
    for (var i = 0; i < kids.length; i++) allNamed(kids[i], name, out)
    return out
  }
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
  function shuffleButton() { return shuffleButtons()[0] }
  function shuffleDot() { return named(named(stage, "footerShuffle"), "shuffleDot") }
  function settingsButton() { return named(stage, "settingsButton") }
  function searchAction() { return named(stage, "searchAction") }
  // The shell Button keeps its glyph Text internal; find it by the icon text so
  // font/size/position checks still measure the rendered glyph, not the button.
  function iconGlyphOf(btn) {
    if (!btn || !btn.iconText) return null
    return find(btn, function(it) { return it !== btn && it.hasOwnProperty("font") && typeof it.text === "string" && it.text === btn.iconText })
  }
  // v3.5.1 addendum: menu rows carry a dedicated leading icon Text, separate
  // from the shell Button's check slot. Measure that Text, not the placeholder.
  function leadingGlyphOf(btn) {
    if (!btn || !btn.leadingIconText) return null
    return find(btn, function(it) { return it !== btn && it.objectName === "leadingIcon" && it.text === btn.leadingIconText })
  }
  function searchMagnifier() { return iconGlyphOf(searchAction()) }
  function keyboardPanel() { return find(stage, function(it) { return typeof it.fittedContentHeight === "function" }) }
  // v3.5.4 retry: on 531b8f7 the field was computed from the full-screen
  // KeyboardPanel.width, so widening only the surface (as the real shell does)
  // pushed the field past the card and collapsed the cat column to zero. The
  // fixed code derives both from contentWidth, so only surfaceWidth changes.
  function livePathHeaderOk(surfaceWidth) {
    var kp = keyboardPanel(), sf = searchField()
    var cc = named(stage, "headerCatColumn"), art = named(stage, "catStencil")
    var f = sf.mapToItem(stage, 0, 0), z = cc.mapToItem(stage, 0, 0)
    var expectedField = Math.round(kp.contentWidth * 0.72) - panel.headerTopInset
    var contentRight = z.x + cc.width
    var ok = Math.abs(sf.width - expectedField) <= 1 &&
      (f.x + sf.width) <= contentRight + 0.5 &&
      Math.abs((f.x + sf.width) - z.x) <= 1 &&
      cc.width > 0 && art.width > 0 && art.height > 0
    log("v3.5.4 retry surface=" + surfaceWidth + " contentWidth=" + kp.contentWidth +
      " expectedField=" + expectedField + " actualField=" + sf.width +
      " fieldRight=" + (f.x + sf.width).toFixed(2) + " contentRight=" + contentRight.toFixed(2) +
      " column=" + cc.width.toFixed(2) + " cat=" + art.width.toFixed(2) + "x" + art.height.toFixed(2) +
      " ok=" + ok)
    return ok
  }
  function isInside(item, ancestor) {
    if (!item || !ancestor) return false
    for (var p = item; p; p = p.parent) if (p === ancestor) return true
    return false
  }
  // v3.5.4: capture/compare geometric rectangles in stage coordinates so the
  // normal and syncing states can be proven pixel-identical.
  function geomOf(item) {
    if (!item) return null
    var p = item.mapToItem(stage, 0, 0)
    return { x: p.x, y: p.y, w: item.width, h: item.height }
  }
  function sameGeom(a, b, tol) {
    if (!a || !b) return false
    var d = tol === undefined ? 0.01 : tol
    return Math.abs(a.x - b.x) <= d && Math.abs(a.y - b.y) <= d &&
      Math.abs(a.w - b.w) <= d && Math.abs(a.h - b.h) <= d
  }
  function clickMagnifier() {
    var m = searchMagnifier()
    var pt = m.mapToItem(stage, m.width / 2, m.height / 2)
    tc.mouseClick(stage, pt.x, pt.y)
  }
  function doubleClick(item) { tc.mouseDoubleClickSequence(item, item.width / 2, item.height / 2, Qt.LeftButton) }
  // v3: Refresh and Hide pre-orders live in the gear menu. Open it, then click the entry.
  // Open the gear menu. The offscreen harness sometimes swallows the first click
  // after a link/tooltip/dialog; a second click only happens if the menu did not open.
  function menuItemByText(t) {
    return find(stage, function(it) { return it.hasOwnProperty("iconText") && it.hasOwnProperty("bordered") && it.text === t })
  }
  function openSettings() {
    if (panel.menuOpen) return
    click(settingsButton())
    if (!panel.menuOpen) click(settingsButton())
  }
  function toggleHidePreorders() { openSettings(); click(button("Hide pre-orders")) }
  function refreshLibrary() { openSettings(); click(button("Refresh")) }
  function shuffleLabel() { return shuffleButton() ? shuffleButton().tooltipText : "" }
  // The footer transport's play button.
  function footerPlay() {
    var all = allButtons(stage, []).filter(function(b) { return b.iconText === "\uf04b" || b.iconText === "\uf04c" })
    return all[all.length - 1]
  }
  function sortButton() {
    var mode = svc.activeTab === 1 ? svc.playlistSortMode : svc.sortMode
    return button("Sort: " + LibraryModel.sortLabel(mode))
  }
  function searchField() { return find(stage, function(it) { return it.hasOwnProperty("placeholderText") }) }
  function leftList() { return named(stage, "leftList") }
  function trackList() { return named(stage, "trackList") }
  function click(item) { tc.mouseClick(item) }
  function rightClick(item) { tc.mouseClick(item, item.width / 2, item.height / 2, Qt.RightButton) }
  function middleClick(item) { tc.mouseClick(item, item.width / 2, item.height / 2, Qt.MiddleButton) }
  function barButton() { return named(panel, "barButton") }
  function comparePlaceholder() { cmpArt.same = false; cmpArt.running = true }

  function key(k) { tc.keyClick(k, Qt.NoModifier) }
  function shiftKey(k) { tc.keyClick(k, Qt.ShiftModifier) }
  function ctrlKey(k) { tc.keyClick(k, Qt.ControlModifier) }
  function altKey(k) { tc.keyClick(k, Qt.AltModifier) }
  function menuKey() { tc.keyClick(Qt.Key_Menu, Qt.NoModifier) }
  function shiftF10() { tc.keyClick(Qt.Key_F10, Qt.ShiftModifier) }
  function typeText(t) { for (var i = 0; i < t.length; i++) tc.keyClick(t.charAt(i)) }
  // Raw query-text evidence: length plus the actual code points.
  function rawText(t) {
    var cps = []
    for (var i = 0; i < t.length; i++) {
      var h = t.charCodeAt(i).toString(16).toUpperCase()
      while (h.length < 4) h = "0" + h
      cps.push("U+" + h)
    }
    return "len=" + t.length + " cps=[" + cps.join(",") + "]"
  }

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
  // v3.3 grouped-search helpers: model rows carry rowKind ("header", "album",
  // "playlist", "track") when the query is non-empty.
  function searchKinds() {
    var m = leftList().model, out = []
    for (var i = 0; i < m.length; i++) out.push(m[i] && m[i].rowKind ? m[i].rowKind : "")
    return out
  }
  function searchHeaders() {
    var m = leftList().model, out = []
    for (var i = 0; i < m.length; i++) if (m[i] && m[i].rowKind === "header") out.push(m[i].title)
    return out
  }
  // Contain (not Visible) so a row whose edge is barely on screen is scrolled
  // fully into the viewport before the harness clicks its centre. v3.2's
  // content-driven row heights changed the scroll offsets enough to expose this.
  function showRow(title) { var i = leftIndex(title); leftList().positionViewAtIndex(i, ListView.Contain) }
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

  // v3.4: clean slate for the user-queue checks (no playback, no pending rows).
  function resetUserQueueChecks() {
    svc.userQueueState = { pending: [], current: null, resumeIndex: -1, history: [] }
    svc.queue = []
    svc.queueIndex = -1
    svc.context = { type: "", name: "", tracks: [] }
    svc.playingContextKey = ""
    svc.isPlaying = false
    svc.isPaused = false
    svc.position = 0
    svc.duration = 0
    svc.pendingSeek = -1
    svc.playbackError = ""
    svc.notice = ""
    // v3.5.5: tests mutate the model directly here, so keep the persisted copy
    // in step with the clean slate too.
    svc.saveQueue()
  }
  function clearQueueMemory() {
    svc.userQueueState = { pending: [], current: null, resumeIndex: -1, history: [] }
  }
  function queueTitles() {
    return svc.userQueue.map(function(t) { return t.title })
  }

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
      check("header row contains ONLY the title (the gear is no longer in it)", !!named(stage, "headerTitle") && named(stage, "headerTitle").text === "OmaTimeAtBandcamp" && allButtons(named(stage, "headerRow"), []).length === 0)
      check("v3.1: title font is one step larger (+2 pt over the v3 subtitle size)", named(stage, "headerTitle").font.pixelSize === Style.font.subtitle + 2)
      check("v3.5.4: the settings control is the cat-and-flute mark with its menu",
        !!settingsButton() && settingsButton().iconText === "" && settingsButton().tooltipText === "Settings" &&
        isInside(settingsButton(), named(stage, "headerCatColumn")) && !button("\uf141"))
      var cat = named(stage, "catStencil")
      check("v3.5.4.1: the cat mark is the slim smoothed shipped SVG trace, not a raster stencil",
        !!cat && !named(stage, "catMaskCanvas") && !named(stage, "catMaskImage") &&
        !named(stage, "catMarkShape") &&
        String(cat.svgFile).indexOf("cat-flute.svg") >= 0 &&
        cat.implicitWidth === 508 && cat.implicitHeight === 345 &&
        cat.pathCount === 3 && cat.isVector === true &&
        !!named(stage, "catPath0") && !!named(stage, "catPath2"))
      check("v3.5.4.1: every slim cat path is filled from the theme accent binding (no baked colour)",
        !!cat && cat.pathData.length === 3 &&
        String(cat.tintColor) === String(Color.accent) &&
        String(cat.fillColor) === String(Color.accent) &&
        String(cat.renderedColor) === String(Color.accent) &&
        Math.abs(cat.artAspect - 508 / 345) < 0.0001)
      check("fixture library loaded: 13 albums, 2 playlists", svc.collection.length === 13 && svc.playlists.length === 2)
      check("v3.1: the old left-hand search icon is gone", !named(stage, "searchIcon"))
      check("search field is shortened (narrower than its row)", searchField().width < searchField().parent.width)
      check("v3.5.1: Collection is no longer a header button and the old links row stays gone",
        !named(stage, "link-collection") &&
        ["Bandcamp", "Discover", "Editorials (Daily)", "Radio", "Your Feed", "Your Collection"].every(function(l) { return !button(l) }) &&
        !named(stage, "linksRow"))
    },
    function() {
      var sf = searchField(), gear = settingsButton(), row = named(stage, "searchRow")
      var cc = named(stage, "headerCatColumn"), sb = named(stage, "searchBand")
      var s = sf.mapToItem(stage, 0, 0), g = gear.mapToItem(stage, 0, 0)
      var z = cc.mapToItem(stage, 0, 0), p = keyboardPanel().mapToItem(stage, 0, 0)
      var band = sb.mapToItem(stage, 0, 0)
      var panes = named(stage, "libraryRow").mapToItem(stage, 0, 0)
      var panelW = keyboardPanel().width
      var fieldRightFraction = ((s.x + sf.width) - p.x) / panelW
      log("v3.5.4 popup width=" + panelW + " row=" + row.width + " field=" + sf.width +
        " column=" + cc.width + "x" + cc.height + " fieldRight=" + fieldRightFraction.toFixed(4))
      check("v3.2: popup content width is the new ~835 px value (820-840 accepted)", keyboardPanel().contentWidth === Style.space(835) && keyboardPanel().contentWidth >= 820 && keyboardPanel().contentWidth <= 840)
      check("v3.5.4: the header is title + search only, with no status row in it",
        !named(stage, "headerStatusRow") && !named(stage, "headerStatus") &&
        named(stage, "headerStack").height === panel.controlHeight * 2 + Style.spacing.sm)
      check("v3.5.4: the search row holds only the field; the cat column sits beside it",
        allButtons(row, []).filter(function(b) { return b.objectName !== "searchAction" }).length === 0 &&
        isInside(sf, row) && !isInside(gear, row) && isInside(gear, cc))
      check("v3.5.4: the search field's right edge sits at ~72% of the panel width (68-75% accepted)",
        fieldRightFraction >= 0.68 && fieldRightFraction <= 0.75)
      check("v3.5.4: the cat column starts at the field's right edge and ends at the panel's right inner edge",
        Math.abs((s.x + sf.width) - z.x) <= 1 &&
        Math.abs((z.x + cc.width) - (p.x + panelW - panel.headerTopInset)) <= 1)
      check("v3.5.4: the cat column runs from the panel top border to the top of the panes",
        Math.abs(z.y - p.y) <= 1 && Math.abs((z.y + cc.height) - panes.y) <= 1 &&
        cc.height === panel.headerCatColumnHeight && cc.height > sf.height)
      check("v3.5.4: the whole cat column is the settings button",
        Math.abs(g.x - z.x) <= 0.5 && Math.abs(g.y - z.y) <= 0.5 &&
        Math.abs((g.x + gear.width) - (z.x + cc.width)) <= 0.5 &&
        Math.abs((g.y + gear.height) - (z.y + cc.height)) <= 0.5)
      var title = named(stage, "headerTitle"), t = title.mapToItem(stage, 0, 0)
      log("v3.5.4 geometry: panelY=" + p.y + " columnY=" + z.y + " columnBottom=" + (z.y + cc.height) +
        " panesY=" + panes.y + " bandY=" + band.y + " titleCenter=" + (t.y + title.height / 2) +
        " inset=" + panel.headerTopInset)
      check("v3.5.4: the title is still centred in the band above the search row",
        Math.abs((t.y + title.height / 2) - (p.y + (band.y - p.y) / 2)) <= 1)
      var art = named(stage, "catStencil")
      var ap = art.mapToItem(stage, 0, 0)
      var cx = ap.x + art.inkCentroidX * art.width
      var cy = ap.y + art.inkCentroidY * art.height
      var colCx = z.x + cc.width / 2, colCy = z.y + cc.height / 2
      var targetCy = colCy + panel.catCentreNudgeY
      log("v3.5.4.1 normal geometry: art=" + art.width.toFixed(2) + "x" + art.height.toFixed(2) +
        " bbox=" + ap.x.toFixed(2) + "," + ap.y.toFixed(2) +
        " centroid=" + cx.toFixed(2) + "," + cy.toFixed(2) +
        " columnCentre=" + colCx.toFixed(2) + "," + colCy.toFixed(2) +
        " nudge=" + panel.catCentreNudgeY + " target=" + colCx.toFixed(2) + "," + targetCy.toFixed(2) +
        " heightRatio=" + (art.height / cc.height).toFixed(3) +
        " topMargin=" + (ap.y - z.y).toFixed(2))
      // Pixel probe bounds, relative to the panel that the screenshot captures.
      // The script-side checks crop exactly these rects from the saved PNG.
      var po = keyboardPanel().mapToItem(stage, 0, 0)
      log("v3.5.4 pixels: accent=" + String(Color.accent) +
        " art=" + Math.floor(ap.x - po.x) + "," + Math.floor(ap.y - po.y) + "," +
        (Math.ceil(art.width) + 1) + "," + (Math.ceil(art.height) + 1) +
        " column=" + Math.floor(z.x - po.x) + "," + Math.floor(z.y - po.y) + "," +
        (Math.ceil(cc.width) + 1) + "," + (Math.ceil(cc.height) + 1))
      check("v3.5.4.1: the slim mark is fitted inside the column on both axes, aspect preserved",
        art.width <= cc.width + 0.5 && art.height <= cc.height + 0.5 &&
        Math.abs((art.width / art.height) - (508 / 345)) <= 0.01)
      check("v3.5.4.1: the mark's ink centroid matches the column centre plus the 3 px down-nudge",
        Math.abs(cx - colCx) <= 2 && Math.abs(cy - targetCy) <= 2)
      check("v3.5.4.1: the mark's bbox sits fully inside the column with all ink clear of the edges",
        ap.x >= z.x - 0.5 && ap.y >= z.y + 0.5 &&
        ap.x + art.width <= z.x + cc.width + 0.5 &&
        ap.y + art.height <= z.y + cc.height + 0.5)
      check("v3.5.4.1: the rendered ink's top edge sits at least 6 px below the panel top border",
        ap.y - z.y >= Style.space(6) - 0.5)
      var previousFitWidth = Math.min(cc.width - 2 * Style.space(4),
        (cc.height - 2 * Style.space(4)) * (508 / 345))
      check("v3.5.4.1: the slim mark renders at 95% of the previous fit (~145 x 99)",
        Math.abs(art.width - previousFitWidth * 0.95) <= 1 &&
        Math.abs((art.width / art.height) - (508 / 345)) <= 0.01)
      check("v3.5.4.1: the ink centroid is measured from the slim asset, not the bbox",
        Math.abs(art.inkCentroidX - 0.3889005865) < 0.0001 &&
        Math.abs(art.inkCentroidY - 0.5202530254) < 0.0001)
      check("v3.1: search text still fits at the shared height (no vertical clipping)", sf.implicitHeight <= sf.height + 0.5)
      var lp = named(stage, "leftPane").mapToItem(stage, 0, 0), tb = button("Albums (" + svc.albumsView.length + ")").mapToItem(stage, 0, 0)
      check("v3.1: the search field's left edge aligns with the album list and toolbar below (no indent)",
        Math.abs(s.x - lp.x) <= 1 && Math.abs(s.x - tb.x) <= 1)
      var m = searchMagnifier(), ms = m.mapToItem(stage, 0, 0)
      check("v3.1: magnifier is INSIDE the field at its right end",
        isInside(m, sf) && ms.x > s.x + sf.width * 0.5 && ms.x + m.width <= s.x + sf.width && ms.x >= s.x + sf.width - 40)
      check("v3.1: magnifier glyph is the footer transport glyph size", m.font.pixelSize === named(stage, "footerPrev").iconSize && m.font.pixelSize === Style.space(16))
      check("v3.3.1: an empty field shows a focusable magnifier control (not a disabled glyph)",
        searchField().text === "" && !!searchAction() && searchAction().iconText === "\uf002" &&
        searchAction().tooltipText === "" && searchAction().focusable === true &&
        isInside(searchAction(), sf) && !!m && m.text === "\uf002")
      var controls = [sf, button("Albums (" + svc.albumsView.length + ")"), button("Playlists (" + svc.playlists.length + ")"), sortButton(),
        named(stage, "footerShuffle"), named(stage, "footerPrev"), named(stage, "footerPlay"), named(stage, "footerNext")]
      var ch = {}
      for (var i = 0; i < controls.length; i++) ch[Math.round(controls[i].height)] = 1
      log("v3.1 named control heights=" + Object.keys(ch))
      check("v3.1: search field, Albums (N), Playlists (N), Sort and the four footer transport buttons share ONE measured height",
        controls.every(function(x) { return !!x }) && Object.keys(ch).length === 1 && Object.keys(ch)[0] == Style.spacing.controlHeight)
      check("v3.5.4: only the cat settings control is deliberately taller (it is the whole column)",
        gear.height === cc.height && gear.height > Style.spacing.controlHeight)
      host.headerGeom = {
        field: geomOf(sf), column: geomOf(cc), gear: geomOf(gear), art: geomOf(art),
        albums: geomOf(button("Albums (" + svc.albumsView.length + ")")),
        playlists: geomOf(button("Playlists (" + svc.playlists.length + ")")),
        sort: geomOf(sortButton()), sortDir: geomOf(named(stage, "sortDirectionButton")),
        toolbar: geomOf(named(stage, "toolbar")), panes: geomOf(named(stage, "libraryRow"))
      }
    },
    // v3.5.4 retry: reproduce the real shell's parent chain. KeyboardPanel is
    // a full-screen layer surface, so its width is the monitor width while the
    // card is contentWidth. On 531b8f7 these steps fail: the field grows with
    // the surface and the cat column collapses to zero.
    function() {
      host.livePathSavedSurfaceWidth = keyboardPanel().surfaceWidth
      keyboardPanel().surfaceWidth = 1280
    },
    function() {
      check("v3.5.4 retry: at a 1280 px live surface the field stays inside the card and the cat keeps nonzero width (531b8f7 regression)",
        livePathHeaderOk(1280))
      keyboardPanel().surfaceWidth = 1920
    },
    function() {
      check("v3.5.4 retry: at a 1920 px live surface the field stays inside the card and the cat keeps nonzero width (531b8f7 regression)",
        livePathHeaderOk(1920))
      keyboardPanel().surfaceWidth = 2560
    },
    function() {
      check("v3.5.4 retry: at a 2560 px live surface the field stays inside the card and the cat keeps nonzero width (531b8f7 regression)",
        livePathHeaderOk(2560))
      keyboardPanel().surfaceWidth = host.livePathSavedSurfaceWidth
    },
    // v3.5.4: real-size screenshots of the normal and syncing states. The
    // layout must be identical in both; only the toolbar status label changes.
    function() {
      host.headerShot = null
      host.headerSave = false
      headerShotProbe.source = ""
      keyboardPanel().grabToImage(function(result) {
        host.headerSave = result.saveToFile("/tmp/omatime-v3541-header.png")
        host.headerShot = result
        if (host.headerSave) headerShotProbe.source = "file:///tmp/omatime-v3541-header.png?" + Date.now()
      })
    },
    function() { },
    function() { },
    function() {
      log("v3.5.4 normal shot: saved=" + host.headerSave + " status=" + headerShotProbe.status +
        " " + headerShotProbe.implicitWidth + "x" + headerShotProbe.implicitHeight +
        " panel=" + keyboardPanel().width + "x" + keyboardPanel().height)
      check("v3.5.4: the normal header rendered at the real panel size (full popup, no scaling)",
        !!host.headerShot && host.headerSave === true && headerShotProbe.status === Image.Ready &&
        headerShotProbe.implicitWidth === keyboardPanel().width &&
        headerShotProbe.implicitHeight === keyboardPanel().height)
    },
    function() { svc.status = "Syncing library…" },
    function() { },
    function() {
      // v3.5.6: every string the label can actually show, generated by the
      // service (the headline plus every composed percentage, 0-100) must fit
      // the full label width without eliding at the real panel size.
      var label = named(stage, "syncStatusLabel")
      var statuses = ["Syncing library…"]
      for (var p = 0; p <= 100; p++) statuses.push(svc.syncStatusText(p))
      var allFit = true
      var minWidth = 1e9, maxWidth = 0, worst = "", worstText = 0
      for (var i = 0; i < statuses.length; i++) {
        statusMetrics.text = statuses[i]
        var measured = statusMetrics.advanceWidth
        if (measured > label.width + 0.5) allFit = false
        if (measured > maxWidth) { maxWidth = measured; worst = statuses[i]; worstText = measured }
        minWidth = Math.min(minWidth, measured)
      }
      log("v3.5.4.1 status widths: count=" + statuses.length + " labelWidth=" + label.width.toFixed(2) +
        " min=" + minWidth.toFixed(2) + " max=" + maxWidth.toFixed(2) +
        " worst=" + JSON.stringify(worst) + " worstWidth=" + worstText.toFixed(2))
      check("v3.5.4.1: every enumerated sync status fits the full label width at the real panel size",
        allFit && label.visible && label.implicitWidth <= label.width + 0.5 && !label.truncated)
      svc.status = "Syncing library… 100%"
    },
    function() { },
    function() {
      var label = named(stage, "syncStatusLabel"), sf = searchField()
      var sd = named(stage, "sortDirectionButton"), tb = named(stage, "toolbar")
      var cc = named(stage, "headerCatColumn"), art = named(stage, "catStencil")
      var lr = label.mapToItem(stage, 0, 0), sr = sd.mapToItem(stage, 0, 0)
      var tr = tb.mapToItem(stage, 0, 0), sfRight = sf.mapToItem(stage, 0, 0).x + sf.width
      var clearance = lr.x - (sr.x + sd.width)
      var neighbours = [button("Albums (" + svc.albumsView.length + ")"),
        button("Playlists (" + svc.playlists.length + ")"), sortButton(), sd, cc]
      var noOverlap = neighbours.every(function(x) {
        if (!x) return false
        var r = x.mapToItem(stage, 0, 0)
        return (lr.x + label.width <= r.x + 0.5) || (lr.x >= r.x + x.width - 0.5) ||
          (lr.y + label.height <= r.y + 0.5) || (lr.y >= r.y + x.height - 0.5)
      })
      var cur = {
        field: geomOf(sf), column: geomOf(cc), gear: geomOf(settingsButton()), art: geomOf(art),
        albums: geomOf(button("Albums (" + svc.albumsView.length + ")")),
        playlists: geomOf(button("Playlists (" + svc.playlists.length + ")")),
        sort: geomOf(sortButton()), sortDir: geomOf(sd),
        toolbar: geomOf(tb), panes: geomOf(named(stage, "libraryRow"))
      }
      var unchanged = Object.keys(host.headerGeom).every(function(k) {
        return sameGeom(host.headerGeom[k], cur[k])
      })
      log("v3.5.4 syncing label: text=" + JSON.stringify(label.text) + " visible=" + label.visible +
        " rect=" + lr.x.toFixed(2) + "," + lr.y.toFixed(2) + "," + label.width.toFixed(2) + "x" + label.height.toFixed(2) +
        " fieldRight=" + sfRight.toFixed(2) + " sortDirRight=" + (sr.x + sd.width).toFixed(2) +
        " clearance=" + clearance.toFixed(2) + " toolbarY=" + tr.y.toFixed(2))
      check("v3.5.4: the syncing label appears in the Albums/Playlists/Sort row only while syncing",
        !!label && label.visible && label.text.indexOf("Syncing library") === 0 &&
        lr.y >= tr.y - 0.5 && lr.y + label.height <= tr.y + tb.height + 0.5)
      check("v3.5.4: the syncing label's right edge is flush with the search field's right edge",
        Math.abs((lr.x + label.width) - sfRight) <= 1)
      check("v3.5.4.1: the label spans the full gap from Sort direction + 8 px to the field's right edge",
        Math.abs(lr.x - (sr.x + sd.width + Style.space(8))) <= 0.5 &&
        Math.abs(label.width - (sfRight - lr.x)) <= 0.5)
      check("v3.5.4: the syncing label clears Sort direction by at least 8 px and overlaps nothing",
        clearance >= Style.space(8) - 0.5 && noOverlap)
      check("v3.5.4: showing the syncing label shifts no header, field, column or control geometry",
        unchanged)
      check("v3.5.4: the cat column and art geometry are identical in normal and syncing states",
        sameGeom(host.headerGeom.column, cur.column) && sameGeom(host.headerGeom.gear, cur.gear) &&
        sameGeom(host.headerGeom.art, cur.art))
      host.syncShot = null
      host.syncSave = false
      syncShotProbe.source = ""
      keyboardPanel().grabToImage(function(result) {
        host.syncSave = result.saveToFile("/tmp/omatime-v3541-syncing.png")
        host.syncShot = result
        if (host.syncSave) syncShotProbe.source = "file:///tmp/omatime-v3541-syncing.png?" + Date.now()
      })
    },
    function() { },
    function() { },
    function() {
      log("v3.5.4 syncing shot: saved=" + host.syncSave + " status=" + syncShotProbe.status +
        " " + syncShotProbe.implicitWidth + "x" + syncShotProbe.implicitHeight +
        " panel=" + keyboardPanel().width + "x" + keyboardPanel().height)
      check("v3.5.4: the syncing-state panel rendered at the real panel size (full popup, no scaling)",
        !!host.syncShot && host.syncSave === true && syncShotProbe.status === Image.Ready &&
        syncShotProbe.implicitWidth === keyboardPanel().width &&
        syncShotProbe.implicitHeight === keyboardPanel().height)
      svc.status = ""
    },
    function() { },
    function() {
      var label = named(stage, "syncStatusLabel")
      check("v3.5.4: the syncing label hides again and the cat column stays put",
        (!label || !label.visible) && sameGeom(host.headerGeom.column, geomOf(named(stage, "headerCatColumn"))))
      svc.status = "Library updated · 13 albums"
      check("v3.5.4: the label stays hidden for non-sync status text", !!label && !label.visible)
      svc.status = ""
    },
    // v3.5.6: the front phases have no per-item denominator, but the overall
    // percentage must still be visible there.
    function() { svc.beginSyncProgress(); svc.advanceSyncProgress("album lists", 0, 0) },
    function() {
      var label = named(stage, "syncStatusLabel")
      check("v3.5.6: the label shows a percentage during the front album-list phase",
        !!label && label.visible && label.text === "Syncing library… 0%")
    },
    // v3.5.6: scripted sequence of the phase events the backend emits, in
    // order (plus one revised denominator), proving one monotonic overall
    // percentage from 0 to done. The backend's last playlist/page event is
    // (N-1)/N, and tracklists reports every 100 albums, so those are the
    // shapes used here.
    function() {
      svc.beginSyncProgress()
      var events = [
        ["album lists", 0, 0],
        ["album lists", 666, 1332],
        ["album lists", 1332, 1332],
        ["matching", 0, 0],
        ["playlists", 0, 0],
        ["playlists", 16, 33],
        ["playlists", 32, 33],
        ["album pages", 0, 1],
        ["tracklists", 0, 608],
        ["tracklists", 100, 608],
        ["tracklists", 304, 608],
        ["tracklists", 200, 800],
        ["tracklists", 600, 608],
        ["done", 688, 688]
      ]
      var seq = [], monotonic = true, onlyDoneIs100 = true, matchingHeld = false, revisedHeld = false
      for (var i = 0; i < events.length; i++) {
        var e = events[i], before = svc.syncPercent
        var text = svc.advanceSyncProgress(e[0], e[1], e[2])
        var pct = svc.syncPercent
        if (pct < before) monotonic = false
        if (e[0] !== "done" && pct === 100) onlyDoneIs100 = false
        if (e[0] === "matching") matchingHeld = pct === 36
        if (e[0] === "tracklists" && e[1] === 200 && e[2] === 800) revisedHeld = pct === 83
        seq.push(e[0] + ":" + e[1] + "/" + e[2] + "=" + pct + " " + text)
      }
      log("v3.5.6 percent sequence: " + seq.join(" | "))
      check("v3.5.6: the whole scripted phase sequence never moves the overall percent backwards", monotonic)
      check("v3.5.6: a revised denominator never moves the percent backwards (304/608 = 83%, then 200/800 stays 83%)", revisedHeld)
      check("v3.5.6: an uncounted phase holds at its band floor (matching stays at 36%)", matchingHeld)
      check("v3.5.6: a counted phase interpolates inside its band (album lists 666/1332 = 18%, tracklists 100/608 = 72%, 304/608 = 83%)",
        svc.syncPercentFor("album lists", 666, 1332) === 18 &&
        svc.syncPercentFor("tracklists", 100, 608) === 72 &&
        svc.syncPercentFor("tracklists", 304, 608) === 83)
      check("v3.5.6: 100% appears only at the backend's done event", onlyDoneIs100 && svc.syncPercent === 100)
      svc.status = "Library updated · 688 albums"
    },
    function() {
      check("v3.5.6: the label hides at completion per the existing rule",
        !named(stage, "syncStatusLabel").visible)
      svc.status = ""
    },
    function() {
      // Prove the in-field glyph cannot take input: click it while the list owns
      // focus, then type. The field must focus and receive the character.
      searchField().text = ""; svc.search("")
      named(stage, "listKeyCatcher").forceActiveFocus()
      clickMagnifier()
    },
    function() {
      check("v3.1: clicking the magnifier focuses the field (it does not block clicks)", searchField().activeFocus)
      typeText("q")
    },
    function() {
      check("v3.1: typing after a magnifier click reaches the field (it does not block text entry)", svc.searchQuery === "q")
      searchField().text = ""; svc.search("")
      panel.focusPane = ""
      searchField().forceActiveFocus()
    },
    function() {
      var bs = allButtons(stage, [])
      var ordinary = bs.filter(function(x) { return x.objectName !== "settingsButton" })
      var hs = {}, ic = {}, bd = {}
      for (var i = 0; i < ordinary.length; i++) { hs[Math.round(ordinary[i].height)] = 1; ic[ordinary[i].iconSize] = 1; bd[ordinary[i].bordered] = 1 }
      log("buttons=" + bs.length + " ordinary heights=" + Object.keys(hs) + " iconSizes=" + Object.keys(ic) + " bordered=" + Object.keys(bd))
      check("10 buttons in the open window (cat settings, 3 toolbar, direction, 4 footer, plus the v3.3.1 in-field clear/magnifier; Collection moved into the gear menu)", bs.length === 10)
      check("all ordinary buttons share ONE height (controlHeight)", Object.keys(hs).length === 1 && Object.keys(hs)[0] == Style.spacing.controlHeight)
      check("all buttons share ONE icon size (16)", Object.keys(ic).length === 1 && Object.keys(ic)[0] == Style.space(16))
      check("toolbar/footer buttons stay bordered; the in-field action and the borderless cat mark are the intended exceptions",
        ordinary.filter(function(x) { return x.objectName !== "searchAction" }).every(function(x) { return x.bordered === true }) &&
        named(stage, "searchAction").bordered === false && settingsButton().bordered === false)
      var lp = named(stage, "leftPane"), dp = named(stage, "detailPane"), ft = named(stage, "footer")
      log("border colours: left=" + lp.border.color + " detail=" + dp.border.color + " footer=" + ft.border.color)
      check("album list, detail pane and footer share ONE border colour (the detail pane's theme accent)",
        !!lp && !!dp && !!ft && String(lp.border.color) === String(dp.border.color) && String(dp.border.color) === String(ft.border.color) &&
        String(dp.border.color) === String(Util.alpha(Color.accent, 0.75)) && lp.border.width === dp.border.width && dp.border.width === ft.border.width)
    },
    // ---- Esc / menu layering (Phase 2) ----
    function() { key(Qt.Key_Escape) },
    function() { check("Esc closes the window", !panel.opened); panel.open() },
    function() { typeText("zz") },
    function() { check("typing reaches search", svc.searchQuery === "zz") },
    function() { key(Qt.Key_Escape) },
    function() { check("first Esc clears search, window stays", svc.searchQuery === "" && panel.opened); key(Qt.Key_Escape) },
    function() { check("second Esc closes", !panel.opened); panel.open() },
    function() { click(settingsButton()) },
    function() {
      check("gear menu opens from the cat control's header position", panel.menuOpen && panel.menuKind === "more" && isInside(settingsButton(), named(stage, "headerCatColumn")))
      check("gear menu has exactly Refresh / Hide pre-orders / Keyboard shortcuts / Collection / Log out, in order",
        panel.menuItems.map(function(m) { return m.label }).join("|") === "Refresh|Hide pre-orders|Keyboard shortcuts|Collection|Log out")
      check("gear-menu Collection carries the username URL, enabled when known",
        panel.moreItems[3].enabled === true && button("Collection") && button("Collection").tooltipText === "https://bandcamp.com/fixture-user" &&
        button("Collection").height === Style.spacing.controlHeight && button("Collection").bordered === true)
      check("Hide pre-orders is checkable and reflects the persisted state",
        panel.moreItems[1].checked === svc.hidePreorders && !!button("Hide pre-orders") && button("Hide pre-orders").selected === svc.hidePreorders)
      key(Qt.Key_Escape)
    },
    function() { check("Esc closes ONLY the menu", !panel.menuOpen && panel.opened); check("focus returns to search", searchField().activeFocus) },
    function() { click(settingsButton()) },
    function() { check("menu reopened", panel.menuOpen); click(settingsButton()) },
    function() { check("clicking the menu button again closes it (toggle)", !panel.menuOpen && panel.opened); click(settingsButton()) },
    function() { tc.mouseClick(stage, 150, 560) },
    function() { check("click outside the menu card closes it, window stays, nothing underneath was clicked", !panel.menuOpen && panel.opened && panel.selectedAlbumUid === "") },

    // ---- Phase 3: no Play all, one Shuffle toggle, per-context ----
    function() {
      var hit = allStrings(stage, []).filter(function(t) { return /play\s*all/i.test(t) })
      check("no Play-all control anywhere in the item tree (text/tooltip, visible or not)", hit.length === 0)
      check("Service has no playAll()", typeof svc.playAll === "undefined")
      check("exactly one Shuffle control in the window", shuffleButtons().length === 1)
      check("the Shuffle control is in the footer transport", !!shuffleButton() && shuffleButton().objectName === "footerShuffle" && shuffleButton().iconText === "\uf074" && shuffleButton().text === "")
      check("no cycle-through-states left", typeof panel.cycleShuffle === "undefined" && typeof svc.shuffleMode === "undefined" && typeof svc.shuffleLabel === "undefined" && typeof svc.shuffleNames === "undefined")
    },
    function() {
      var labels = [], sel = []
      for (var i = 0; i < 7; i++) { var b = shuffleButton(); labels.push(b.tooltipText); sel.push(b.selected); click(b) }
      var distinct = {}
      for (var j = 0; j < labels.length; j++) distinct[labels[j]] = 1
      check("footer Shuffle shows exactly two states: Shuffle: Off / Shuffle: On", Object.keys(distinct).sort().join("|") === "Shuffle: Off|Shuffle: On")
      check("footer Shuffle strictly alternates Off,On,Off,On,... starting Off", labels.join(",") === "Shuffle: Off,Shuffle: On,Shuffle: Off,Shuffle: On,Shuffle: Off,Shuffle: On,Shuffle: Off")
      check("footer Shuffle is highlighted (selected/tinted) exactly when On", sel.join(",") === "false,true,false,true,false,true,false")
      check("after an odd number of presses the toggle is On and the service agrees", shuffleButton().selected === true && svc.isShuffled("library"))
      click(shuffleButton())
      check("one more press returns to Off", shuffleButton().selected === false && !svc.isShuffled("library"))
    },
    function() {
      var albA = svc.collection[collIndex(host.croc)], albB = svc.collection[collIndex("La Dee La La")], pl = svc.playlists[0]
      var kA = "album:" + albA.id, kB = "album:" + albB.id, kP = "playlist:" + pl.id
      panel.pickAlbum(albA)
      check("selecting an album switches the context to that album", panel.contextKey === kA)
      check("album context starts Off", shuffleButton().selected === false)
      click(shuffleButton())
      check("toggling in the album context turns the album On", shuffleButton().selected === true && svc.isShuffled(kA))
      check("v3.1: shuffle dot appears when the current album context is On", shuffleDot() && shuffleDot().visible === true)
      var sb = shuffleButton(), sd = shuffleDot(), dp = sd.mapToItem(sb, 0, 0)
      check("v3.1: shuffle dot is 3-4 px, centred under the glyph, inside the button (height unchanged)",
        sd.width >= 3 && sd.width <= 4 && sd.height === sd.width && Math.abs((dp.x + sd.width / 2) - sb.width / 2) <= 0.5 &&
        dp.y >= sb.height / 2 && dp.y + sd.height <= sb.height && sb.height === Style.spacing.controlHeight && sb.selected === true)
      panel.pickPlaylist(pl)
      check("selecting a playlist switches the context to that playlist", panel.contextKey === kP)
      check("playlist context still Off after toggling the album (button and service)", shuffleButton().selected === false && !svc.isShuffled(kP))
      check("v3.1: shuffle dot is hidden for the Off playlist even though the album context is On", shuffleDot().visible === false)
      check("whole-library context also untouched", !svc.isShuffled("library"))
      click(shuffleButton())
      check("playlist now On, album still On (independent states)", svc.isShuffled(kP) && svc.isShuffled(kA))
      check("v3.1: shuffle dot appears for the On playlist context", shuffleDot().visible === true && shuffleButton().selected === true)
      panel.pickAlbum(albA)
      check("returning to the album shows its own remembered On", shuffleButton().selected === true)
      check("v3.1: returning to the On album shows the dot again", shuffleDot().visible === true)
      click(shuffleButton())
      check("turning the album Off leaves the playlist On", !svc.isShuffled(kA) && svc.isShuffled(kP))
      check("v3.1: dot follows the album context Off while the playlist remains On", shuffleDot().visible === false && shuffleButton().selected === false)
      panel.pickAlbum(albB)
      check("a different album has its own state (Off)", panel.contextKey === kB && shuffleButton().selected === false)
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
      click(shuffleButton())
      check("Shuffle is On for the album context", shuffleButton().selected === true)
    },
    function() { showRow("La Dee La La") },
    function() {
      var row = leftRow("La Dee La La")
      check("selected row is highlighted before deselect", named(row, "rowBar").visible && alpha(named(row, "rowFill")) > 0.15)
      click(row)
      check("clicking the SELECTED row again deselects it", panel.selectedAlbumUid === "" && panel.selectedAlbum === null)
      check("context returns to the whole library", panel.contextKey === "library")
      check("detail pane returns to the empty prompt", named(stage, "detailTitle").text === "Pick an album or playlist" && trackList().count === 0)
      check("Shuffle control now shows the LIBRARY context's state (Off)", shuffleLabel() === "Shuffle: Off" && !svc.isShuffled("library"))
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
      check("re-selecting restores the album context AND its remembered Shuffle On", panel.selectedAlbumUid === "a:fx-dee" && shuffleLabel() === "Shuffle: On")
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
      check("v3: no Play control in the detail pane header", named(stage, "detailPlay") === null)
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
      check("single-clicking all 7 never plays anything (acceptance: FI never plays)", svc.queue.length === 0 && svc.currentTrack === null && svc.isPlaying === false)
      for (var j = 0; j < 7; j++) doubleClick(rows[j])
      check("double-clicking every unreleased track still plays nothing (no gesture starts audio)", svc.queue.length === 0 && svc.currentTrack === null && svc.isPlaying === false)
      check("unreleased double-click keeps showing only 'Not yet released'", svc.notice === "Not yet released")
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
      check("v3: a fully released album has no Play button in the header either", named(stage, "detailPlay") === null)
      var rows = trackRows()
      check("4 rows, all full opacity, real durations", rows.length === 4 && rows.every(function(r) { return r.opacity === 1 }) && named(rows[0], "trackDuration").text === "9:18" && named(rows[3], "trackDuration").text === "9:58")
      check("every row has hover enabled and pointer cursor", rows.every(function(r) { var m = named(r, "trackMouse"); return m.hoverEnabled && m.cursorShape === Qt.PointingHandCursor }))
      tc.mouseMove(rows[1])
    },
    function() {
      var rows = trackRows()
      check("hovering a playable row paints a hover fill", alpha(named(rows[1], "trackFill")) > 0)
      var qBefore = svc.queue.length
      click(rows[2])
      check("v3: single-click selects a track but never starts audio", panel.trackCursor === 2 && svc.queue.length === qBefore && svc.isPlaying === false)
      doubleClick(rows[2])
      tc.mouseMove(stage, 5, 5)
    },
    function() {
      var rows = trackRows()
      check("double-clicking track 3 queues the whole album starting at track 3", svc.queue.length === 4 && svc.queueIndex === 2 && svc.queue[2].title === "The White Lady")
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
      check("Future Sounds: availability carries the old Play-available information", named(stage, "detailAvail").text === "1 of 3 tracks available · Play available")
      check("v3: no separate Play button when at least one track streams", named(stage, "detailPlay") === null)
      var rows = trackRows()
      check("row 1 (released) normal, rows 2-3 greyed with '—'", rows[0].opacity === 1 && Math.abs(rows[1].opacity - 0.45) < 0.02 && Math.abs(rows[2].opacity - 0.45) < 0.02 && named(rows[0], "trackDuration").text === "3:21" && named(rows[2], "trackDuration").text === "—")
      click(footerPlay())
    },
    function() {
      check("footer Play queues ONLY the streamable track", svc.queue.length === 1 && svc.queue[0].title === "Released Single")
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
      check("empty album renders a graceful message, no padding rows", named(stage, "detailEmpty").text === "No tracks in this album" && trackRows().length === 0 && named(stage, "detailPlay") === null)
      panel.pickAlbum(svc.collection[collIndex("Empty Album")]); panel.pickAlbum(svc.collection[collIndex("Unloaded Album")])
    },
    function() {
      check("not-yet-loaded album says so instead of claiming it is empty", named(stage, "detailEmpty").text === "Tracks are still loading — the library is syncing")
      panel.pickAlbum(svc.collection[collIndex("Unloaded Album")])
      var bad = entityFree(allStrings(stage, []))
      check("no literal HTML entity anywhere in the rendered tree", bad.length === 0)
      check("'Shamek Farrah & Folks' is rendered with a real ampersand", allStrings(stage, []).some(function(t) { return t === "Shamek Farrah & Folks" }) || leftTitles().length > 0)
    },

    // ---- v3: search-result rows also need a double-click to start audio ----
    function() { searchField().text = "The White Lady"; svc.search("The White Lady") },
    function() {
      var row = leftRow("The White Lady")
      check("search returns the matching track row", !!row && row.visible)
      var qBefore = svc.queue.length
      click(row)
      check("v3: single-clicking a search result never starts audio", svc.queue.length === qBefore && svc.currentTrack === null)
      doubleClick(row)
    },
    function() {
      check("v3: double-clicking a search result starts it with the search queue", svc.queue.length === 1 && svc.queue[0].title === "The White Lady" && !!svc.currentTrack && svc.currentTrack.title === "The White Lady")
      svc.queue = []; svc.queueIndex = -1
      svc.isPlaying = false; svc.isPaused = false
    },
    function() {
      var names = ["rowTitle", "rowSub", "detailTitle", "detailSub", "detailPreorder", "detailAvail", "detailPartial", "leftEmpty", "detailEmpty", "footerTitle", "footerSub", "footerError", "noticeText", "trackTitle", "trackNum"]
      var bad = []
      for (var i = 0; i < names.length; i++) {
        var it = named(stage, names[i])
        if (!it) continue
        var left = it.horizontalAlignment === Text.AlignLeft || it.horizontalAlignment === Text.AlignHCenter || it.horizontalAlignment === Qt.AlignLeft
        var unmirrored = it.LayoutMirroring.enabled === false
        if (!left || !unmirrored) bad.push(names[i])
      }
      for (var r = 0; r < trackRows().length; r++) {
        var tt = named(trackRows()[r], "trackTitle")
        if (tt && (tt.horizontalAlignment !== Text.AlignLeft || tt.LayoutMirroring.enabled !== false)) bad.push("trackTitle")
      }
      check("v3 RTL: every title/artist/track text is explicitly left-aligned with mirroring disabled" + (bad.length ? " (" + bad.join(",") + ")" : ""), bad.length === 0)
      searchField().text = ""; svc.search("")
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
      toggleHidePreorders()
    },
    function() {
      check("gear menu Hide pre-orders removes both pre-orders, keeps the sort", svc.hidePreorders === true && titlesEqual(leftTitles(), noPre(expRelease)))
      check("Albums (N) is live: 11 after hiding", !!button("Albums (11)"))
      openSettings()
      check("gear menu shows Hide pre-orders highlighted when On", button("Hide pre-orders").selected === true)
      key(Qt.Key_Escape)
      click(sortButton())
    },
    function() { click(button("Recently added")) },
    function() {
      check("filter + sort combine (Recently added without pre-orders)", svc.sortMode === "added" && titlesEqual(leftTitles(), noPre(expAdded)))
      toggleHidePreorders()
    },
    function() {
      check("toggling Hide pre-orders off restores them", svc.hidePreorders === false && titlesEqual(leftTitles(), expAdded) && !!button("Albums (13)"))
      openSettings()
      check("gear menu Hide pre-orders is no longer highlighted", button("Hide pre-orders").selected === false)
      key(Qt.Key_Escape)
      click(button("Playlists (2)"))
    },
    // ---- pre-release: Sort on the Playlists tab (reduced, per-tab, persisted) ----
    function() {
      check("pre-release: Sort is present on the Playlists tab with its reduced label",
        !!button("Sort: Recently added") && sortButton().visible === true)
      check("pre-release: playlists start in the library's source order (Recently added)",
        svc.playlistSortMode === "added" && titlesEqual(leftTitles(), ["Rock & Roll Faves", "Postpunky?"]))
      click(sortButton())
    },
    function() {
      var labels = panel.menuItems.map(function(m) { return m.label })
      check("pre-release: the Playlists sort menu offers EXACTLY Recently added and Title A–Z",
        labels.join("|") === "Recently added|Title A–Z" && !button("Artist A–Z") && !button("Release date"))
      check("pre-release: Recently added is checked on the default Playlists sort",
        panel.menuItems[0].icon === "\uf00c" && panel.menuItems[1].icon !== "\uf00c")
      click(button("Title A–Z"))
    },
    function() {
      check("pre-release: Title A–Z reorders the playlists case-insensitively",
        svc.playlistSortMode === "title" && !!button("Sort: Title A–Z") &&
        titlesEqual(leftTitles(), ["Postpunky?", "Rock & Roll Faves"]))
      check("pre-release: the playlist sort does not change the Albums sort", svc.sortMode === "added")
      click(sortButton())
    },
    function() { click(button("Recently added")) },
    function() {
      check("pre-release: Recently added restores the library source order",
        svc.playlistSortMode === "added" && titlesEqual(leftTitles(), ["Rock & Roll Faves", "Postpunky?"]))
      click(sortButton())
    },
    function() { click(button("Title A–Z")) },
    function() {
      check("pre-release: playlist Title A–Z is the persisted choice for relaunch",
        svc.playlistSortMode === "title")
      searchField().text = "o"
      svc.search("o")
    },
    function() {
      check("pre-release: the search Playlists group follows the playlist sort",
        svc.searchResults.playlists.map(function(p) { return p.name }).join("|") === "Postpunky?|Rock & Roll Faves")
      searchField().text = ""
      svc.search("")
      openSettings()
      check("Hide pre-orders stays available in the gear menu on the Playlists tab", !!button("Hide pre-orders"))
      key(Qt.Key_Escape)
      click(button("Albums (13)"))
    },
    function() {
      check("pre-release: the Albums sort is still its own choice after changing Playlists",
        svc.sortMode === "added" && !!button("Sort: Recently added") && titlesEqual(leftTitles(), expAdded))
    },
    function() { click(sortButton()) },
    function() { click(button("Title A–Z")) },
    function() { toggleHidePreorders() },
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
      check("library Shuffle On via the footer", svc.isShuffled("library") && shuffleLabel() === "Shuffle: On")
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

    // ---- Phase 5: footer transport, progress/seek, error notice ----
    function() {
      // A known queue entry without touching the real player.
      svc.queue = [{
        uid: "p5#0", title: host.longTitle + " " + host.longTitle, artist: "Long Title Artist", album: "Long",
        duration: 200, streamable: true, subsonicId: "t:fx-none", bandcampId: ""
      }]
      svc.queueIndex = 0
      svc.isPlaying = false
      svc.isPaused = false
      svc.playbackError = ""
      svc.position = 0
      svc.duration = 200
      svc.pendingSeek = -1
      tc.mouseMove(stage, 5, 5)
    },
    function() {
      var f = named(stage, "footer")
      var bs = allButtons(f, [])
      var heights = {}, icons = {}, bordered = {}
      for (var i = 0; i < bs.length; i++) {
        heights[Math.round(bs[i].height)] = 1
        icons[bs[i].iconText] = 1
        bordered[bs[i].bordered] = 1
      }
      log("footer buttons=" + bs.length + " heights=" + Object.keys(heights) + " icons=" + JSON.stringify(Object.keys(icons)))
      check("footer transport has exactly 4 buttons (Shuffle, Prev, Play/Pause, Next)", bs.length === 4)
      check("the Stop button is gone (no stop glyph in the window)", !find(stage, function(it) { return it.hasOwnProperty("iconText") && it.iconText === "\uf04d" && it.visible }))
      check("the four are exactly shuffle / prev / play / next", Object.keys(icons).sort().join(",") === ["\uf074", "\uf048", "\uf04b", "\uf051"].sort().join(","))
      check("all four share one height, width, icon size and border (Phase 2.1 style)",
        Object.keys(heights).length === 1 && Object.keys(heights)[0] == Style.spacing.controlHeight &&
        Object.keys(bordered).length === 1 && Object.keys(bordered)[0] === "true" &&
        bs.every(function(b) { return Math.abs(b.width - b.height) < 0.5 && b.iconSize === Style.space(16) }))
      var tr = named(stage, "transportRow")
      var right = tr.mapToItem(f, tr.width, 0).x
      log("transport right=" + right + " footer right(margin " + Style.spacing.md + ")=" + (f.width - Style.spacing.md))
      check("v3: the whole transport group is right-justified in the footer",
        Math.abs(right - (f.width - Style.spacing.md)) <= 1)
      check("Shuffle sits on the left edge of the right-justified transport group",
        named(stage, "footerShuffle").mapToItem(tr, 0, 0).x === 0 && named(stage, "footerNext").mapToItem(tr, 0, 0).x > 0)
      // v3.2: switch to PLAYING now so the next step measures the full footer
      // after layout has settled (the idle-collapse checks are later).
      svc.isPlaying = true
      svc.isPaused = false
    },
    function() {
      var f = named(stage, "footer")
      var title = named(stage, "footerTitle"), sub = named(stage, "footerSub"), pr = named(stage, "progressRow"), kp = keyboardPanel()
      var subBottom = sub.mapToItem(f, 0, 0).y + sub.height
      var progressTop = pr.mapToItem(f, 0, 0).y
      var gap = progressTop - subBottom
      log("v3.1 footer height=" + f.height + " gap=" + gap + " popup=" + kp.contentHeight)
      check("v3.2: playing keeps the progress row visible", pr.visible === true)
      host.playingFooterHeight = f.height
      check("v3.1: footer blank band above the progress bar is roughly halved (v3: 6 px, now 2-4 px)", gap >= 2 && gap <= 4)
      check("v3.1: footer is shorter than the v3 84 px", f.height < 84 && f.height > 70)
      check("v3.1: nothing is clipped — title, artist and progress bar sit inside the footer and do not overlap",
        title.mapToItem(f, 0, 0).y >= 0 && sub.mapToItem(f, 0, 0).y + sub.height <= f.height &&
        pr.mapToItem(f, 0, 0).y + pr.height <= f.height && subBottom <= progressTop)
      check("v3.1: total popup is shorter than the v3 build and still under the 660 px cap",
        kp.contentHeight < host.v3PopupHeight && kp.contentHeight <= 660 &&
        pr.mapToItem(kp, 0, 0).y + pr.height <= kp.height)
    },
    function() {
      var p = named(stage, "footerPlay")
      check("while playing the same button shows Pause, says Pause and is highlighted", p.iconText === "\uf04c" && p.tooltipText === "Pause" && p.active === true)
      svc.isPaused = true
    },
    function() {
      var p = named(stage, "footerPlay")
      check("while paused it flips back to Play", p.iconText === "\uf04b" && p.tooltipText === "Play" && p.active === false)
      svc.isPaused = false
    },
    function() {
      var t = named(stage, "footerTitle"), sub = named(stage, "footerSub")
      log("footer title lines=" + t.lineCount + " truncated=" + t.truncated + " | sub=" + JSON.stringify(sub.text))
      check("now-playing title wraps to at most 2 lines, ellipsis only after line 2", t.text === host.longTitle + " " + host.longTitle && t.lineCount === 2 && t.truncated === true)
      check("line 2 is 'Artist  ·  Album', smaller and dimmed", sub.text === "Long Title Artist  ·  Long" && sub.visible && sub.font.pixelSize < t.font.pixelSize && sub.color.hslLightness < t.color.hslLightness)
    },
    function() {
      svc.duration = 200
      svc.position = 0
      svc.applyPlaybackStatus({ running: true, position: 50, duration: 200, paused: false, idle: false })
    },
    function() {
      check("player position feeds the footer", Math.abs(svc.position - 50) < 0.01)
      check("elapsed and total labels", named(stage, "elapsedLabel").text === "0:50" && named(stage, "totalLabel").text === "3:20")
      var fill = named(stage, "progressFill"), track = named(stage, "progressTrack")
      log("progress fill=" + fill.width + " track=" + track.width + " ratio=" + (fill.width / track.width))
      check("progress bar is determinate and 25% filled", Math.abs(fill.width / track.width - 0.25) < 0.02)
    },
    function() {
      var area = named(stage, "seekArea")
      tc.mouseClick(area, area.width * 0.5, area.height * 0.5)
    },
    function() {
      check("clicking the middle of the bar seeks to half the track", Math.abs(svc.position - 100) < 2 && Math.abs(svc.pendingSeek - 100) < 2)
      check("the bar and elapsed label move immediately", named(stage, "elapsedLabel").text === "1:40" && Math.abs(named(stage, "progressFill").width / named(stage, "progressTrack").width - 0.5) < 0.03)
      var area = named(stage, "seekArea")
      tc.mousePress(area, area.width * 0.2, area.height * 0.5, Qt.LeftButton)
      tc.mouseMove(area, area.width * 0.8, area.height * 0.5, -1, Qt.LeftButton)
    },
    function() {
      check("dragging previews the drop time before releasing", named(stage, "elapsedLabel").text === "2:40" && Math.abs(svc.position - 100) < 2)
      var area = named(stage, "seekArea")
      tc.mouseRelease(area, area.width * 0.8, area.height * 0.5, Qt.LeftButton)
    },
    function() {
      check("releasing a drag seeks to the dropped position", Math.abs(svc.position - 160) < 3 && Math.abs(svc.pendingSeek - 160) < 3)
    },
    function() {
      // Mid-stream failure: the stream goes idle 3 s into a 200 s track.
      svc.queue = [
        { uid: "e1", title: "Bad Stream", artist: "A", album: "X", duration: 200, streamable: true, subsonicId: "t:fx-bad1" },
        { uid: "e2", title: "Good Next", artist: "A", album: "X", duration: 180, streamable: true, subsonicId: "t:fx-bad2" }
      ]
      svc.queueIndex = 0
      svc.isPlaying = true
      svc.isPaused = false
      svc.playbackError = ""
      svc.duration = 200
      svc.position = 3
      svc.failureStreak = 0
      svc.playbackStartedAt = 0
      svc.applyPlaybackStatus({ running: true, position: 3, duration: 200, paused: false, idle: true })
      check("a stream that dies early shows 'Couldn't play <title> — skipped'", svc.playbackError === "Couldn't play Bad Stream — skipped")
      check("...and the queue advances to the next track", svc.queueIndex === 1 && svc.currentTrack.title === "Good Next")
      check("the footer shows the error in place of Artist · Album", named(stage, "footerError").visible && named(stage, "footerError").text === "Couldn't play Bad Stream — skipped" && !named(stage, "footerSub").visible)
      check("the error is drawn in the urgent colour", named(stage, "footerError").color === Color.urgent)
    },
    function() {
      // Natural end: position reaches duration, so it advances silently.
      svc.isPlaying = true
      svc.isPaused = false
      svc.playbackError = ""
      svc.duration = 180
      svc.position = 0
      svc.failureStreak = 0
      svc.playbackStartedAt = 0
      svc.queue = [
        { uid: "n1", title: "First", artist: "A", album: "X", duration: 180, streamable: true, subsonicId: "t:fx-n1" },
        { uid: "n2", title: "Second", artist: "A", album: "X", duration: 170, streamable: true, subsonicId: "t:fx-n2" }
      ]
      svc.queueIndex = 0
      svc.applyPlaybackStatus({ running: true, position: 179.6, duration: 180, paused: false, idle: true })
      check("a track that reaches its duration advances with NO error", svc.queueIndex === 1 && svc.playbackError === "")
      check("the footer error line is hidden again", !named(stage, "footerError").visible)
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.playbackError = ""
      svc.position = 0
      svc.duration = 0
    },

    // ---- Post-v3.2: pause-state reconciliation and poll resilience ----
    function() {
      // mpv owns `pause`; the service must adopt it. An inverted isPaused used
      // to stop the 1 s poll while mpv was actually playing (footer stuck at 0:00).
      svc.queue = [{ uid: "pz#0", title: "Paused Track", artist: "A", album: "X", duration: 200, streamable: true }]
      svc.queueIndex = 0
      svc.isPlaying = true
      svc.isPaused = false
      svc.position = 0
      svc.duration = 200
      svc.pendingSeek = -1
      svc.playbackStartedAt = Date.now()
      svc.applyPlaybackStatus({ running: true, position: 0, duration: 200, paused: true, idle: false })
      check("a paused mpv flips the service to paused (the icon cannot stay inverted)", svc.isPaused === true)
      check("...and the footer shows Play, not Pause", footerPlay().iconText === "\uf04b")
    },
    function() {
      svc.applyPlaybackStatus({ running: true, position: 1.5, duration: 200, paused: false, idle: false })
      check("an unpaused mpv flips the service back and advances the position",
        svc.isPaused === false && Math.abs(svc.position - 1.5) < 0.01)
      check("...and the footer shows Pause again", footerPlay().iconText === "\uf04c")
    },
    function() {
      // A transient status failure (socket not ready, a lost poll) must neither
      // reset nor latch the display; the next good poll must advance again.
      svc.position = 5
      svc.applyPlaybackStatus({ running: false })
      check("a transient poll failure keeps the last position (no reset to 0:00)", Math.abs(svc.position - 5) < 0.01)
      svc.applyPlaybackStatus({ running: true, position: 6, duration: 200, paused: false, idle: false })
      check("the next good poll advances again (no latch)", Math.abs(svc.position - 6) < 0.01)
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
      svc.playbackStartedAt = 0
    },

    // ---- Phase 6: bar text is always plain BC, clicks, cached art for MPRIS ----
    function() {
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
      comparePlaceholder()
    },
    function() {
      var b = barButton()
      check("bar text is exactly BC when stopped (no play/pause glyph instead of BC)", !!b && b.text === "BC")
      check("v3: the bar-art widget is gone (no art image in the plugin tree)", !find(panel, function(it) { return it.objectName === "artImage" }))
      check("stopped writes the bundled placeholder (byte-identical to assets/current-art-placeholder.jpg)", cmpArt.same === true)
      check("placeholder is a valid 128x128 image (never a broken image)", artProbe.status === Image.Ready && artProbe.implicitWidth === 128 && artProbe.implicitHeight === 128)
      svc.queue = [{ uid: "art1", title: "Art One", artist: "A", album: "X", duration: 100, streamable: true,
                     subsonicId: "t:art1", subsonicAlbumId: "", coverArtId: "fx-a" }]
      svc.queueIndex = 0
      svc.isPlaying = true
      svc.isPaused = false
      svc.duration = 100
    },
    function() {
      var b = barButton()
      check("v3: playing the bar stays plain BC (no play/pause suffix)", b.text === "BC")
      check("first cover was written and downscaled to <=128 px", artProbe.status === Image.Ready && artProbe.implicitWidth <= 128 && artProbe.implicitHeight <= 128)
      check("first cover keeps its 300x120 aspect (128x51)", artProbe.implicitWidth === 128 && artProbe.implicitHeight === 51)
      check("playing art is not the placeholder", svc.barArtIsPlaceholder === false)
      host.artRev1 = svc.artRevision
      svc.isPaused = true
    },
    function() {
      var b = barButton()
      check("v3: pausing the bar stays plain BC (no play glyph)", b.text === "BC")
      check("pausing keeps the current cover (no placeholder while paused)", svc.barArtIsPlaceholder === false && artProbe.implicitWidth === 128 && artProbe.implicitHeight === 51)
      svc.isPaused = false
      svc.queue = [{ uid: "art2", title: "Art Two", artist: "A", album: "X", duration: 100, streamable: true,
                     subsonicId: "t:art2", subsonicAlbumId: "", coverArtId: "fx-b" }]
      svc.queueIndex = 0
      svc.isPlaying = true
    },
    function() {
      check("track change rewrote current-art.jpg", svc.artRevision > host.artRev1)
      check("second cover replaced the first and was downscaled (90x260 -> 44x128)", artProbe.status === Image.Ready && artProbe.implicitWidth === 44 && artProbe.implicitHeight === 128)
      check("track-change art is not the placeholder", svc.barArtIsPlaceholder === false)
      check("bar text stays plain BC after the track change", barButton().text === "BC")
      svc.isPlaying = false
      svc.isPaused = false
    },
    function() {
      check("stopping restores the placeholder image (128x128)", artProbe.status === Image.Ready && artProbe.implicitWidth === 128 && artProbe.implicitHeight === 128)
      check("stopped bar is still plain BC", barButton().text === "BC")
      comparePlaceholder()
    },
    function() {
      check("stopping restores the placeholder file", cmpArt.same === true && svc.barArtIsPlaceholder === true)
      svc.queue = [
        { uid: "c1", title: "Click One", artist: "A", album: "X", duration: 100, streamable: true, subsonicId: "t:c1", coverArtId: "fx-a" },
        { uid: "c2", title: "Click Two", artist: "A", album: "X", duration: 100, streamable: true, subsonicId: "t:c2", coverArtId: "fx-a" }
      ]
      svc.queueIndex = 0
      svc.isPlaying = true
      svc.isPaused = false
    },
    function() {
      rightClick(barButton())
    },
    function() {
      check("right-click toggles play/pause (paused)", svc.isPaused === true)
      rightClick(barButton())
    },
    function() {
      check("right-click toggles back to playing", svc.isPaused === false)
      middleClick(barButton())
    },
    function() {
      check("middle-click goes to the next track", svc.queueIndex === 1 && svc.currentTrack.uid === "c2")
      click(barButton())
    },
    function() {
      check("left-click closes the window (and toggles it open again)", !panel.opened)
      click(barButton())
    },
    function() {
      check("left-click opens the window again", panel.opened)
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
    },

    // ---- Phase 7/v3.5.1: Collection moved from the header into the gear menu ----
    function() {
      var sf = searchField(), m = searchMagnifier(), gear = settingsButton()
      var gone = ["Bandcamp", "Discover", "Editorials (Daily)", "Radio", "Your Feed", "Your Collection"]
      check("v3.5.1: Collection is not in the header; the old links stay gone",
        !named(stage, "link-collection") && gone.every(function(l) { return !button(l) }) && !named(stage, "linksRow"))
      var right = sf.mapToItem(stage, 0, 0).x + sf.width
      var cz = named(stage, "headerCatColumn")
      check("v3.5.1: the cat control is the only thing to the right of the field",
        Math.abs(gear.mapToItem(stage, 0, 0).x - right) <= 1 && Math.abs(cz.mapToItem(stage, 0, 0).x - right) <= 1 &&
        allButtons(named(stage, "searchRow"), []).filter(function(b) { return b.objectName !== "searchAction" }).length === 0)
      check("v3.5.1: magnifier sits inside the field's right end, not to its left",
        isInside(m, sf) && m.mapToItem(stage, 0, 0).x >= right - 40 && m.mapToItem(stage, 0, 0).x + m.width <= right)
      check("v3.5.1: Collection keeps the library-username URL (fixture-user)",
        panel.collectionUrl === "https://bandcamp.com/fixture-user" && panel.moreItems[3].label === "Collection" &&
        panel.moreItems[3].enabled === true)
      openSettings()
    },
    function() {
      check("v3.5.1: the gear menu contains the Collection item with the username URL",
        panel.menuOpen && !!button("Collection") && button("Collection").tooltipText === "https://bandcamp.com/fixture-user")
      click(button("Collection"))
    },
    // The offscreen tooltip can eat the next click; focus the search field to settle it.
    function() { check("Collection menu item opens https://bandcamp.com/fixture-user", svc.lastOpenedUrl === "https://bandcamp.com/fixture-user"); click(searchField()) },

    // ---- logout flow (Phase 2), now reached through the gear menu ----
    function() { openSettings() },
    function() { click(button("Log out")) },
    function() { check("gear menu item opens confirmation (does not log out yet)", panel.logoutConfirmOpen && !panel.menuOpen && svc.status !== "Cleared imported session"); key(Qt.Key_Escape) },
    function() { check("Esc cancels confirmation, window stays, no logout", !panel.logoutConfirmOpen && panel.opened && svc.status !== "Cleared imported session"); openSettings() },
    function() { key(Qt.Key_Down); key(Qt.Key_Down); key(Qt.Key_Down); key(Qt.Key_Down) },
    function() { key(Qt.Key_Return) },
    function() { check("Enter on the Log out gear-menu item opens the confirmation", panel.logoutConfirmOpen); key(Qt.Key_Return) },
    function() { check("Enter on confirmation = preselected Cancel: no logout", !panel.logoutConfirmOpen && svc.status !== "Cleared imported session") },
    function() { openSettings() },
    function() { click(button("Log out")) },
    function() { key(Qt.Key_Right) },
    function() { key(Qt.Key_Return) },
    function() { check("confirming runs clearCookies", !panel.logoutConfirmOpen && svc.status === "Cleared imported session"); check("window stays open after logout", panel.opened); click(searchField()) },

    // ---- refresh (Phase 2), now reached through the gear menu ----
    function() { refreshLibrary() },
    function() { },
    function() { },
    function() { },
    function() {
      check("refreshing became true after the gear-menu click", !!seen)
      check("at that moment: gear-menu item disabled, spinning, dimmed", seen && seen.enabled === false && seen.spin === true && seen.op < 1)
      click(searchField())
      openSettings()
      var b = button("Refresh")
      check("refresh finished: not refreshing, gear-menu item re-enabled and still", !svc.refreshing && b && b.enabled === true && b.iconSpinning === false)
      if (panel.menuOpen) key(Qt.Key_Escape)
      log("status after refresh: " + JSON.stringify(svc.status))
    },

    // ---- Phase 8: panel-scoped keyboard navigation ----
    function() {
      panel.focusSearch()
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.listCursor = -1
      panel.trackCursor = -1
      panel.focusPane = ""
      svc.activeTab = 0
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
      check("keyboard: search owns focus on open; no list is focused", searchField().activeFocus && panel.focusPane === "")
    },
    function() { key(Qt.Key_Down) },
    function() {
      var rows = panel.listRows
      check("keyboard: Down enters the left list at row 0", panel.focusPane === "list" && panel.listCursor === 0)
      check("keyboard: the list key catcher has focus", named(stage, "listKeyCatcher").activeFocus)
      check("keyboard: selection follows the cursor (non-toggling)", panel.selectedAlbumUid === rows[0].uid)
    },
    function() { key(Qt.Key_Down) },
    function() {
      var rows = panel.listRows
      check("keyboard: second Down moves to row 1", panel.listCursor === 1 && panel.selectedAlbumUid === rows[1].uid)
      check("keyboard: the cursor row is tinted", alpha(named(leftList().itemAtIndex(1), "rowFill")) > 0.1)
    },
    function() { key(Qt.Key_Up) },
    function() { check("keyboard: Up moves back to row 0", panel.listCursor === 0) },
    function() { key(Qt.Key_Return) },
    function() {
      var rows = panel.listRows
      check("keyboard: Enter plays the selected album's context", svc.queue.length === rows[0].tracks.length && svc.queueIndex === 0)
      check("keyboard: Enter uses the selected album context", svc.playingContextKey === "album:" + rows[0].id)
      // Deterministic playing state: the real backend cannot play in the harness.
      svc.queue = [{ uid: "kbd-track", title: "Keyboard Track", artist: "Keyboard Artist", album: "Keyboard Album", duration: 120 }]
      svc.queueIndex = 0
      svc.isPlaying = true
      svc.isPaused = false
      svc.position = 10
      svc.duration = 120
    },
    function() { key(Qt.Key_Space) },
    function() { check("keyboard: Space in the list pauses playback", svc.isPaused === true); key(Qt.Key_Space) },
    function() { check("keyboard: Space again resumes playback", svc.isPaused === false) },
    function() { key(Qt.Key_Slash) },
    function() { check("keyboard: / returns focus to the search field", panel.focusPane === "" && searchField().activeFocus) },
    function() { key(Qt.Key_Down) },
    function() { typeText("a") },
    function() {
      check("keyboard: typing in a list refocuses search and keeps the character",
        searchField().text === "a" && panel.focusPane === "" && svc.searchQuery === "a")
    },
    function() {
      var before = svc.isPaused
      typeText(" ")
      check("keyboard: Space while typing in search types a space (never toggles)",
        searchField().text === "a " && svc.isPaused === before)
    },
    function() { key(Qt.Key_Escape) },
    function() { check("keyboard: Esc clears search before closing", panel.opened && svc.searchQuery === "" && searchField().text === "") },
    function() { key(Qt.Key_Escape) },
    function() { check("keyboard: the next Esc closes the window", !panel.opened); panel.open() },
    function() {
      var a = panel.albums.filter(function(x) { return svc.tracksFor(x).length > 1 })[0]
      panel.selectAlbum(a)
      panel.focusTracks()
    },
    function() {
      check("keyboard: focusTracks enters the track list at its first row", panel.focusPane === "tracks" && panel.trackCursor === 0)
      check("keyboard: the focused track row is tinted", alpha(named(trackList().itemAtIndex(0), "trackFill")) > 0.1)
      key(Qt.Key_Down)
    },
    function() {
      check("keyboard: Down moves within the focused track list", panel.detailTrackList.length > 1 && panel.trackCursor === 1)
      check("keyboard: the previous track row tint is gone", alpha(named(trackList().itemAtIndex(0), "trackFill")) < 0.15)
      key(Qt.Key_Return)
    },
    function() {
      var rows = panel.detailTrackList
      check("keyboard: Enter plays the focused track", svc.currentTrack && svc.currentTrack.uid === rows[1].uid && svc.queueIndex === 1)
    },

    // ---- v3.3.1: Tab is focus movement, never query text ----
    function() {
      panel.open()
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      svc.activeTab = 0
      panel.selectAlbum(panel.albums[0])
      searchField().text = ""
      svc.search("")
      panel.focusPane = ""
      panel.listCursor = -1
      svc.queue = []
      svc.queueIndex = -1
      prepLists()
      searchField().forceActiveFocus()
    },
    // The owner's exact repro: open panel (search focused), Tab, Down, Tab.
    function() { key(Qt.Key_Tab) },
    function() { key(Qt.Key_Down) },
    function() { key(Qt.Key_Tab) },
    function() {
      var t = searchField().text
      log("v3.3.1 owner Tab/Down/Tab: " + rawText(t) + " query=" + svc.searchQuery.length +
        " left=" + leftList().count + " tracks=" + trackList().count + " focus=" + panel.focusControlName())
      check("v3.3.1: owner Tab/Down/Tab leaves the query EMPTY (raw text length 0)",
        t === "" && svc.searchQuery === "")
      check("v3.3.1: ...and both panes stay populated (no No results blanking)",
        panel.listRows.length > 0 && leftList().count > 0 && trackList().count > 0 &&
        named(stage, "leftEmpty").visible === false && named(stage, "detailEmpty").text === "")
    },
    // The actual injection path: Tab while a list owns focus used to append U+0009.
    function() {
      panel.focusPane = "list"
      if (panel.listCursor < 0) panel.listCursor = 0
      named(stage, "listKeyCatcher").forceActiveFocus()
    },
    function() { key(Qt.Key_Tab) },
    function() {
      check("v3.5: Tab from a focused list (empty queue) leaves to the track list and never types U+0009",
        panel.focusPane === "tracks" && searchField().text === "" && svc.searchQuery === "")
      panel.focusPane = "list"
      named(stage, "listKeyCatcher").forceActiveFocus()
    },
    function() { shiftKey(Qt.Key_Tab) },
    function() {
      check("v3.5: Shift+Tab from a focused list reverses to the sort direction button and never types",
        named(stage, "sortDirectionButton").activeFocus && searchField().text === "" && svc.searchQuery === "")
      panel.focusPane = "list"
      named(stage, "listKeyCatcher").forceActiveFocus()
    },
    function() {
      // Navigation/control keys with empty or control event.text, all with a list
      // focused: none may become query text.
      key(Qt.Key_Delete); key(Qt.Key_Home); key(Qt.Key_End)
      key(Qt.Key_PageDown); key(Qt.Key_PageUp)
      key(Qt.Key_Up); key(Qt.Key_Down); key(Qt.Key_Left); key(Qt.Key_Right)
    },
    function() {
      check("v3.3.1: navigation/control keys with a list focused never enter the query",
        searchField().text === "" && svc.searchQuery === "")
    },
    function() {
      panel.focusPane = "list"
      named(stage, "listKeyCatcher").forceActiveFocus()
      typeText("q")
    },
    function() {
      check("v3.3.1: a genuine printable character with a list focused still jumps to search and is kept",
        searchField().text === "q" && svc.searchQuery === "q" && searchField().activeFocus)
      searchField().text = ""
      svc.search("")
      panel.focusPane = ""
      searchField().forceActiveFocus()
    },
    function() {
      svc.queue = [{ uid: "v331#space", title: "Space Probe", artist: "A", album: "X", duration: 10, streamable: true }]
      svc.queueIndex = 0
      svc.isPlaying = true
      svc.isPaused = false
      panel.focusPane = "list"
      named(stage, "listKeyCatcher").forceActiveFocus()
    },
    function() { key(Qt.Key_Space) },
    function() {
      check("v3.3.1: Space with a list focused toggles playback and is never typed into the query",
        svc.isPaused === true && searchField().text === "" && svc.searchQuery === "")
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
      // The Phase 8 metadata fence below reads currentTrack; restore a real
      // library track so this block does not leave it null.
      var libAlbum = panel.albums.filter(function(x) { return svc.tracksFor(x).length > 0 })[0]
      var libTrack = libAlbum ? svc.tracksFor(libAlbum)[0] : null
      if (libTrack) { svc.queue = [libTrack]; svc.queueIndex = 0 }
      searchField().forceActiveFocus()
    },
    // Header chain in visual order, forward and reverse, with the shared focus state.
    function() {
      searchField().forceActiveFocus()
      host.chain = []
      host.chainFocus = []
      for (var i = 0; i < 6; i++) {
        key(Qt.Key_Tab)
        host.chain.push(panel.focusControlName())
        var f = panel.focusChainItems().filter(function(x) { return x.activeFocus })[0]
        host.chainFocus.push(!!f && (f._showFocusRing !== undefined ? f._showFocusRing : f.activeFocus))
      }
    },
    function() {
      check("v3.5.1: Tab walks search → clear/magnifier → gear → Albums → Playlists → Sort → direction",
        host.chain.join("|") === "searchAction|settingsButton|albumsButton|playlistsButton|sortButton|sortDirectionButton")
      check("v3.5: every chain stop shows the shared focus state",
        host.chainFocus.every(function(x) { return x === true }))
      named(stage, "sortDirectionButton").forceActiveFocus()
      host.chain = []
      for (var i = 0; i < 6; i++) {
        shiftKey(Qt.Key_Tab)
        host.chain.push(panel.focusControlName())
      }
    },
    function() {
      check("v3.5.1: Shift+Tab reverses the same chain",
        host.chain.join("|") === "sortButton|playlistsButton|albumsButton|settingsButton|searchAction|searchField")
      searchField().forceActiveFocus()
    },
    // v3.5.1: focus indication comes from the same theme accent as the rest of the panel.
    function() {
      var gear = settingsButton(), field = searchField()
      field.forceActiveFocus()
      var fieldFocused = String(field.background.border.color)
      gear.forceActiveFocus()
      var fieldIdle = String(field.background.border.color)
      var gearFocused = String(gear.border.color)
      check("v3.5.1: a focused button's border is the theme accent colour",
        String(gear.focusColor) === String(Color.accent) && gearFocused === String(Color.accent))
      check("v3.5.1: the focused search field border is the theme accent and differs from its unfocused border",
        fieldFocused === String(Color.accent) && fieldIdle !== fieldFocused)
      field.forceActiveFocus()
    },
    // Click-to-clear × and its keyboard equivalent.
    function() {
      searchField().text = "La Dee"
      svc.search("La Dee")
      searchField().forceActiveFocus()
    },
    function() {
      var sa = searchAction(), g = searchMagnifier(), refGlyph = iconGlyphOf(sortButton())
      check("v3.3.1: with text the field shows a ×, the Clear search tooltip and the shared icon font",
        sa.iconText === "\uf00d" && sa.tooltipText === "Clear search" && !!g && g.text === "\uf00d" &&
        !!refGlyph && g.font.family === refGlyph.font.family && g.font.pixelSize === refGlyph.font.pixelSize)
      click(sa)
    },
    function() {
      check("v3.3.1: clicking × clears the query, restores both lists and returns focus to the field",
        searchField().text === "" && svc.searchQuery === "" && searchField().activeFocus &&
        leftList().count > 0 && trackList().count > 0)
    },
    function() {
      searchField().text = "The White Lady"
      svc.search("The White Lady")
      searchField().forceActiveFocus()
      key(Qt.Key_Tab)
    },
    function() {
      check("v3.3.1: Tab from search lands on the focused clear control", searchAction().activeFocus && searchAction()._showFocusRing === true)
      key(Qt.Key_Return)
    },
    function() {
      check("v3.3.1: Enter on the focused clear button clears and refocuses the field",
        searchField().text === "" && svc.searchQuery === "" && searchField().activeFocus)
      searchField().text = "La Dee"
      svc.search("La Dee")
      searchField().forceActiveFocus()
      key(Qt.Key_Tab)
    },
    function() { key(Qt.Key_Space) },
    function() {
      check("v3.3.1: Space on the focused clear button clears and refocuses the field too",
        searchField().text === "" && svc.searchQuery === "" && searchField().activeFocus)
    },
    // Gear menu: leading icons share one aligned slot, and Refresh uses the same
    // icon font as Log out.
    function() { openSettings() },
    function() {
      var refresh = button("Refresh"), logout = button("Log out")
      var hide = button("Hide pre-orders")
      var ri = leadingGlyphOf(refresh), li = leadingGlyphOf(logout)
      var card = named(stage, "menuCard")
      check("v3.3.1: Refresh uses the icon font's sync glyph, same family as Log out",
        !!refresh && refresh.leadingIconText === "\uf021" && logout.leadingIconText === "\uf08b" && !!ri && !!li && ri.font.family === li.font.family)
      check("v3.5.1 addendum: Refresh and Log out leading icons share size/weight and aligned boxes/baselines",
        !!ri && !!li && refresh.iconSize === logout.iconSize && ri.font.pixelSize === li.font.pixelSize &&
        ri.font.bold === li.font.bold && refresh.height === logout.height && ri.height === li.height &&
        Math.abs(ri.mapToItem(refresh, 0, 0).y - li.mapToItem(logout, 0, 0).y) <= 0.5)
      var rows = panel.moreItems.map(function(m) { return button(m.label) })
      var glyphs = rows.map(leadingGlyphOf)
      var aligned = rows.length === 5 && glyphs.every(function(g, i) {
        if (!g || !rows[i] || g.text !== rows[i].leadingIconText) return false
        var at = g.mapToItem(rows[i], 0, 0)
        var first = glyphs[0].mapToItem(rows[0], 0, 0)
        return Math.abs(at.x - first.x) <= 0.5 && Math.abs(at.y - first.y) <= 0.5
      })
      check("v3.5.1 addendum: all five menu rows have a leading icon in one aligned slot",
        aligned && rows.every(function(b) { return !!b && b.leadingIconText !== "" }))
      check("v3.5.4: Hide pre-orders uses the eye-slash glyph in the same leading slot and keeps its check slot unchanged",
        !!hide && hide.leadingIconText === "\uf070" && hide.selected === svc.hidePreorders &&
        hide.iconSize === refresh.iconSize && hide.height === refresh.height &&
        (hide.iconText === "\uf00c" || hide.iconText === "\u2003"))
      host.menuShot = null
      host.menuSave = false
      menuShotProbe.source = ""
      card.grabToImage(function(result) {
        host.menuSave = result.saveToFile("/tmp/omatime-v331-gear-menu.png")
        host.menuShot = result
        if (host.menuSave) menuShotProbe.source = "file:///tmp/omatime-v331-gear-menu.png?" + Date.now()
      })
    },
    // grabToImage is async and offscreen frames are lazy; give the callback a
    // couple of harness ticks before checking.
    function() { },
    function() { },
    function() {
      log("v3.3.1 shot: saved=" + host.menuSave + " status=" + menuShotProbe.status +
        " " + menuShotProbe.implicitWidth + "x" + menuShotProbe.implicitHeight)
      check("v3.3.1: the gear menu rendered a screenshot (refresh + log out + checkable item)",
        !!host.menuShot && host.menuSave === true && menuShotProbe.status === Image.Ready &&
        menuShotProbe.implicitWidth > 0 && menuShotProbe.implicitHeight > 0)
      key(Qt.Key_Escape)
    },
    function() {
      check("v3.3.1: Esc still closes only the gear menu", !panel.menuOpen && panel.opened)
      searchField().text = ""
      svc.search("")
      panel.focusPane = ""
      searchField().forceActiveFocus()
    },

    // ---- Phase 8: metadata fence (the daemon reads only this file) ----
    function() { svc.writeMprisState(); mprisProbe.running = true },
    function() {
      var d = {}
      try { d = JSON.parse(mprisProbe.text || "{}") } catch (e) {}
      var keys = Object.keys(d).sort().join(",")
      check("mpris: the state carries title/artist/album from the library",
        !!svc.currentTrack && d.title === svc.currentTrack.title && d.artist === svc.currentTrack.artist && d.album === svc.currentTrack.album)
      check("mpris: the state key set is the explicit whitelist",
        keys === "album,artist,canNext,canPause,canPlay,canPrevious,canSeek,duration,position,status,title,updatedAt")
      check("mpris: no path/url/cover field is written",
        !("path" in d) && !("url" in d) && !("coverArtUrl" in d) && !("streamUrl" in d) && !("artUrl" in d))
      var blob = JSON.stringify(d)
      check("mpris: no URL scheme, query string or credential word in any value",
        !/:\/\//.test(blob) && !/\?/.test(blob) && !/\b(u|t|s)=/.test(blob) && !/(token|password|credential|salt)/i.test(blob))
    },

    // ---- v3.2: narrower window, content-driven row height, idle footer ----
    function() {
      // A controlled library with a 4-track album, a 120-track album and a
      // 4-track playlist. mk() gives each track a distinct title prefix so the
      // search-result counts below are exact.
      svc.collection = [
        synth("a:small", "Small Album", "Small Artist", mk("smallt", 4)),
        synth("a:big", "Big Album", "Big Artist", mk("bigt", 120))
      ]
      svc.playlists = [{ uid: "pl:small", id: "pl:small", name: "Small Playlist", tracks: mk("plt", 4), totalCount: 4 }]
      svc.activeTab = 0
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.focusPane = ""
      searchField().text = ""
      svc.search("")
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.playbackError = ""
      svc.position = 0
      svc.duration = 0
      prepLists()
    },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      var kp = keyboardPanel()
      host.capRowHeight = lr.height
      host.capPopupHeight = kp.contentHeight
      log("v3.2 nothing selected: row=" + lr.height + " popup=" + kp.contentHeight + " panes=" + lp.height + "/" + dp.height)
      check("v3.2: nothing selected (library browsing) keeps the CAP row height", Math.abs(lr.height - Style.space(396)) < 0.5)
      check("v3.2: list and detail panes are exactly the same height and end on the same line",
        Math.abs(lp.height - dp.height) < 0.5 && Math.abs(lp.height - lr.height) < 0.5 &&
        Math.abs((lp.mapToItem(lr, 0, lp.height).y) - (dp.mapToItem(lr, 0, dp.height).y)) < 0.5)
    },
    function() { panel.selectAlbum(svc.collection[collIndex("Small Album")]) },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      var tl = trackList(), kp = keyboardPanel(), floorH = 6 * Style.space(30)
      log("v3.2 4-track album: row=" + lr.height + " listContent=" + tl.contentHeight + " trackListH=" + tl.height + " popup=" + kp.contentHeight)
      check("v3.2: a 4-track album sizes the row below the cap", lr.height < host.capRowHeight - 1 && lr.height <= Style.space(396))
      check("v3.2: ...and never below the six-track-row floor", lr.height >= floorH - 0.5)
      check("v3.2: the 4-track content fits without scrolling", tl.count === 4 && tl.contentHeight <= tl.height + 0.5)
      check("v3.2: the 4-track popup is measurably shorter than the nothing-selected cap state", kp.contentHeight < host.capPopupHeight - 1)
      check("v3.2: (small album) both panes share one height and bottom line",
        Math.abs(lp.height - dp.height) < 0.5 && Math.abs(lp.height - lr.height) < 0.5 &&
        Math.abs((lp.mapToItem(lr, 0, lp.height).y) - (dp.mapToItem(lr, 0, dp.height).y)) < 0.5)
    },
    function() { panel.selectAlbum(svc.collection[collIndex("Big Album")]) },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      var tl = trackList(), kp = keyboardPanel()
      log("v3.2 120-track album: row=" + lr.height + " listContent=" + tl.contentHeight + " trackListH=" + tl.height + " popup=" + kp.contentHeight)
      check("v3.2: a 100+ track album reaches the CAP row height", Math.abs(lr.height - Style.space(396)) < 0.5)
      check("v3.2: ...and its track list scrolls (content taller than the viewport)", tl.count === 120 && tl.contentHeight > tl.height + 1)
      check("v3.2: (large album) both panes share one height and bottom line",
        Math.abs(lp.height - dp.height) < 0.5 && Math.abs(lp.height - lr.height) < 0.5 &&
        Math.abs((lp.mapToItem(lr, 0, lp.height).y) - (dp.mapToItem(lr, 0, dp.height).y)) < 0.5)
    },
    function() { panel.selectPlaylist(svc.playlists[0]) },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      var tl = trackList(), kp = keyboardPanel(), floorH = 6 * Style.space(30)
      log("v3.2 4-track playlist: row=" + lr.height + " popup=" + kp.contentHeight)
      check("v3.2: a 4-track playlist sizes by content, below the cap and above the floor",
        lr.height < host.capRowHeight - 1 && lr.height >= floorH - 0.5 && tl.count === 4)
      check("v3.2: (playlist) both panes share one height and bottom line",
        Math.abs(lp.height - dp.height) < 0.5 && Math.abs(lp.height - lr.height) < 0.5 &&
        Math.abs((lp.mapToItem(lr, 0, lp.height).y) - (dp.mapToItem(lr, 0, dp.height).y)) < 0.5)
    },
    function() { searchField().text = "smallt"; svc.search("smallt") },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      var floorH = 6 * Style.space(30)
      log("v3.2 search 4: row=" + lr.height + " results=" + panel.detailTrackList.length)
      check("v3.2: search results size by result count (4 results -> content height, below the cap)",
        panel.detailTrackList.length === 4 && lr.height < host.capRowHeight - 1 && lr.height >= floorH - 0.5)
      check("v3.2: (search results) both panes share one height and bottom line",
        Math.abs(lp.height - dp.height) < 0.5 && Math.abs(lp.height - lr.height) < 0.5 &&
        Math.abs((lp.mapToItem(lr, 0, lp.height).y) - (dp.mapToItem(lr, 0, dp.height).y)) < 0.5)
    },
    function() { searchField().text = "bigt"; svc.search("bigt") },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      var tl = trackList()
      log("v3.2 search 120: row=" + lr.height + " results=" + panel.detailTrackList.length + " listContent=" + tl.contentHeight + " trackListH=" + tl.height)
      check("v3.2: 100+ search results reach the CAP and scroll",
        panel.detailTrackList.length === 120 && Math.abs(lr.height - Style.space(396)) < 0.5 && tl.contentHeight > tl.height + 1)
      check("v3.2: (large search results) both panes share one height and bottom line",
        Math.abs(lp.height - dp.height) < 0.5 && Math.abs(lp.height - lr.height) < 0.5 &&
        Math.abs((lp.mapToItem(lr, 0, lp.height).y) - (dp.mapToItem(lr, 0, dp.height).y)) < 0.5)
      searchField().text = ""
      svc.search("")
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
    },

    // ---- v3.3: grouped search results (names as well as tracks) ----
    function() {
      var smallTracks = mk("smallt", 4)
      for (var st = 0; st < smallTracks.length; st++) smallTracks[st].album = "Small Album"
      svc.collection = [
        synth("a:small", "Small Album", "Small Artist", smallTracks),
        synth("a:big", "Big Album", "Big Artist", mk("bigt", 120))
      ]
      svc.playlists = [{ uid: "pl:small", id: "pl:small", name: "Small Playlist", tracks: mk("plt", 4), totalCount: 4 }]
      svc.activeTab = 0
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.focusPane = ""
      panel.listCursor = -1
      panel.trackCursor = -1
      searchField().text = ""
      svc.search("")
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.playbackError = ""
      svc.position = 0
      svc.duration = 0
      prepLists()
      searchField().text = "Small Album"; svc.search("Small Album")
    },
    function() {
      var aIdx = leftIndex("Small Album"), hIdx = leftIndex("Tracks (4)"), tIdx = leftIndex("smallt0")
      log("v3.3 album query: headers=" + searchHeaders().join("|") + " kinds=" + searchKinds().join(",") + " album=" + aIdx + " trackHeader=" + hIdx + " firstTrack=" + tIdx)
      check("v3.3: an album-name query returns the album in the Albums section",
        svc.searchResults.albums.length === 1 && svc.searchResults.albums[0].title === "Small Album")
      check("v3.3: the album section sits ABOVE any tracks (header -> album -> Tracks header -> tracks)",
        aIdx >= 0 && hIdx > aIdx && tIdx > hIdx && searchKinds()[aIdx] === "album" && searchKinds()[hIdx] === "header")
      check("v3.3: the album query shows exactly Albums and Tracks headers, each with its count",
        searchHeaders().join("|") === "Albums (1)|Tracks (4)")
      check("v3.3: no empty Playlists section is rendered", searchHeaders().indexOf("Playlists (0)") < 0)
    },
    function() {
      showRow("Small Album")
      doubleClick(leftRow("Small Album"))
    },
    function() {
      var d = panel.detailTrackList
      check("v3.3: activating an album row leaves search and switches to the Albums tab",
        svc.searchQuery === "" && searchField().text === "" && svc.activeTab === 0)
      check("v3.3: ...and lands on that album with its tracks shown",
        panel.selectedAlbumUid === "a:small" && panel.selectedPlaylistUid === "" &&
        panel.detailTitle() === "Small Album" && d.length === 4 && trackList().count === 4)
      check("v3.3: album-row activation does not start playback", svc.queue.length === 0 && svc.currentTrack === null)
      check("v3.3: leaving search removes the group headers", searchHeaders().length === 0)
    },
    function() {
      searchField().text = "Small Playlist"; svc.search("Small Playlist")
    },
    function() {
      var pIdx = leftIndex("Small Playlist"), hIdx = leftIndex("Tracks (4)"), tIdx = leftIndex("plt0")
      log("v3.3 playlist query: headers=" + searchHeaders().join("|") + " playlist=" + pIdx + " trackHeader=" + hIdx + " firstTrack=" + tIdx)
      check("v3.3: a playlist-name query returns the playlist in the Playlists section",
        svc.searchResults.playlists.length === 1 && svc.searchResults.playlists[0].name === "Small Playlist")
      check("v3.3: the playlist section sits ABOVE any tracks (header -> playlist -> Tracks header -> tracks)",
        pIdx >= 0 && hIdx > pIdx && tIdx > hIdx && searchKinds()[pIdx] === "playlist" && searchKinds()[hIdx] === "header")
      check("v3.3: the playlist query shows exactly Playlists and Tracks headers, each with its count",
        searchHeaders().join("|") === "Playlists (1)|Tracks (4)")
    },
    function() {
      showRow("Small Playlist")
      doubleClick(leftRow("Small Playlist"))
    },
    function() {
      check("v3.3: activating a playlist row leaves search, switches to Playlists and selects it",
        svc.searchQuery === "" && svc.activeTab === 1 && panel.selectedPlaylistUid === "pl:small" &&
        panel.selectedAlbumUid === "" && panel.detailTitle() === "Small Playlist" && panel.detailTrackList.length === 4)
      svc.activeTab = 0
      panel.selectedPlaylistUid = ""
    },
    function() {
      searchField().text = "smallt"; svc.search("smallt")
    },
    function() {
      log("v3.3 track-only query: headers=" + searchHeaders().join("|") + " kinds=" + searchKinds().join(","))
      check("v3.3: a track-only query has no album or playlist matches",
        svc.searchResults.albums.length === 0 && svc.searchResults.playlists.length === 0 && svc.searchResults.tracks.length === 4)
      check("v3.3: a track-only query renders ONLY the Tracks section (no empty sections)",
        searchHeaders().join("|") === "Tracks (4)" && searchKinds().join(",") === "header,track,track,track,track")
    },
    function() {
      searchField().forceActiveFocus()
      panel.focusPane = ""
      panel.listCursor = -1
      key(Qt.Key_Down)
    },
    function() {
      check("v3.3: Down from search skips the section header and lands on the first track",
        panel.focusPane === "list" && panel.listCursor === 1 && searchKinds()[1] === "track")
      key(Qt.Key_Down)
    },
    function() {
      check("v3.3: Down again moves between tracks, never onto a header",
        panel.listCursor === 2 && searchKinds()[2] === "track" && svc.queue.length === 0)
      key(Qt.Key_Return)
    },
    function() {
      check("v3.3: Enter on the selected track activates it with the search TRACK results as context",
        svc.queue.length === 4 && svc.queueIndex === 1 && svc.currentTrack && svc.currentTrack.title === "smallt1" &&
        svc.playingContextKey === "search" && svc.context.key === "search" &&
        svc.queue.map(function(t) { return t.title }).join(",") === "smallt0,smallt1,smallt2,smallt3")
      check("v3.3: track activation did not add group rows to the playable queue",
        svc.queue.length === panel.searchTracks.length && svc.queue.every(function(t) { return /^smallt/.test(t.title) }))
      svc.next()
    },
    function() {
      check("v3.3: next from a search track stays inside the search track results",
        svc.queueIndex === 2 && svc.currentTrack.title === "smallt2" && svc.playingContextKey === "search")
    },
    function() {
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
      searchField().text = "zzzznomatch"; svc.search("zzzznomatch")
    },
    function() {
      check("v3.3: a query matching nothing shows the simple No results state",
        leftList().count === 0 && named(stage, "leftEmpty").visible && named(stage, "leftEmpty").text === "No results" &&
        named(stage, "detailEmpty").text === "No results")
      searchField().text = "Small Album"; svc.search("Small Album")
    },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      var ll = leftList(), tl = trackList(), floorH = 6 * Style.space(30)
      log("v3.3 grouped height: row=" + lr.height + " leftContent=" + ll.contentHeight + " leftH=" + ll.height + " rightContent=" + tl.contentHeight + " rightH=" + tl.height + " groups=" + ll.count + " tracks=" + tl.count)
      check("v3.3: grouped height counts headers + items (left content fits the row)",
        ll.count > panel.detailTrackList.length && ll.contentHeight <= ll.height + 0.5 && lr.height >= ll.contentHeight - 0.5)
      check("v3.3: grouped search stays under the cap and above the floor",
        lr.height < Style.space(396) - 0.5 && lr.height >= floorH - 0.5)
      check("v3.3: both panes stay exactly equal in height with groups shown",
        Math.abs(lp.height - dp.height) < 0.5 && Math.abs(lp.height - lr.height) < 0.5 &&
        Math.abs((lp.mapToItem(lr, 0, lp.height).y) - (dp.mapToItem(lr, 0, dp.height).y)) < 0.5)
      check("v3.3: the right track list also fits its rows", tl.contentHeight <= tl.height + 0.5)
      searchField().text = ""
      svc.search("")
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.focusPane = ""
      panel.listCursor = -1
      panel.trackCursor = -1
      svc.activeTab = 0
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
      svc.playbackError = ""
    },

    // ---- v3.4: session-only user queue + Up Next -------------------------
    function() {
      // The v3.2/v3.3 checks swap in small synthetic libraries. Put the fixture
      // library back before exercising real album/track rows again.
      svc.loadLibrary()
      resetUserQueueChecks()
      panel.selectedPlaylistUid = ""
      panel.selectedAlbumUid = ""
      panel.focusPane = ""
      panel.listCursor = -1
      panel.trackCursor = -1
      svc.activeTab = 0
      searchField().text = ""
      svc.search("")
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
      showRow("La Dee La La")
    },
    function() {
      rightClick(leftRow("La Dee La La"))
    },
    function() {
      check("v3.4: right-clicking an album row opens Add to Queue",
        panel.contextMenuOpen && panel.contextMenuKind === "item" &&
        panel.contextMenuEntries.length === 1 && panel.contextMenuEntries[0].label === "Add to Queue" &&
        !!button("Add to Queue") && button("Add to Queue").enabled === true)
      click(button("Add to Queue"))
    },
    function() {
      check("v3.4: Add to Queue on an album appends its streamable tracks in order",
        svc.userQueue.length === 4 && queueTitles().join("|") ===
        "La Dee La La Song|Waiting For Marvin|The White Lady|Along Came Ron Rahsaan")
      check("v3.4: the album add reports how many tracks were queued",
        svc.notice === "Added 4 tracks to queue")
      var up = named(stage, "upNext"), list = named(stage, "upNextList")
      var header = named(stage, "upNextHeader")
      check("v3.4: Up Next appears with its count", up.visible === true && header.text === "Up Next (4)" && list.count === 4)
      check("v3.4: Up Next rows are in added order, title + artist · album",
        named(list.itemAtIndex(0), "upNextTitle").text === "La Dee La La Song" &&
        named(list.itemAtIndex(0), "upNextSub").text === "Shamek Farrah & Folks · La Dee La La" &&
        named(list.itemAtIndex(3), "upNextTitle").text === "Along Came Ron Rahsaan")
      var upY = up.mapToItem(named(stage, "detailPane"), 0, 0).y
      var headY = named(stage, "detailTitle").mapToItem(named(stage, "detailPane"), 0, 0).y
      check("v3.4: Up Next sits ABOVE the context's own content", upY < headY && upY + up.height <= headY)
      check("v3.4: Up Next has a Clear button", !!named(stage, "upNextClear") && named(stage, "upNextClear").text === "Clear")
    },
    function() {
      click(named(stage, "upNextClear"))
    },
    function() {
      check("v3.4: Clear empties the queue", svc.userQueue.length === 0)
      check("v3.4: Up Next disappears when the queue is empty", named(stage, "upNext").visible === false)
      check("v3.4: Clear did not touch playback", svc.currentTrack === null && svc.isPlaying === false)
    },

    // track-row menus: Play Next front / Add to Queue end / duplicates
    function() {
      resetUserQueueChecks()
      // Deselect first: pickAlbum() toggles, and the album from the block above
      // is still selected.
      panel.selectedAlbumUid = ""
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
      showRow("La Dee La La")
      var rows = trackRows()
      rightClick(rows[0])
    },
    function() {
      check("v3.4: right-clicking a streamable track row offers Play Next and Add to Queue",
        panel.contextMenuOpen && panel.contextMenuKind === "track" &&
        panel.contextMenuEntries.map(function(e) { return e.label }).join("|") === "Play Next|Add to Queue" &&
        button("Play Next").enabled === true && button("Add to Queue").enabled === true)
      click(button("Add to Queue"))
    },
    function() {
      check("v3.4: Add to Queue appends the right-clicked track", svc.userQueue.length === 1 && svc.userQueue[0].title === "La Dee La La Song")
      showRow("La Dee La La")
      rightClick(trackRows()[1])
    },
    function() {
      click(button("Play Next"))
    },
    function() {
      check("v3.4: Play Next inserts at the FRONT (duplicates are allowed)",
        queueTitles().join("|") === "Waiting For Marvin|La Dee La La Song")
      check("v3.4: Up Next follows the new order", named(stage, "upNextHeader").text === "Up Next (2)" &&
        named(named(stage, "upNextList").itemAtIndex(0), "upNextTitle").text === "Waiting For Marvin")
      svc.clearUserQueue()
    },

    // unstreamable rows disable both actions
    function() {
      resetUserQueueChecks()
      panel.pickAlbum(svc.collection[collIndex(host.fi)])
      rightClick(trackRows()[0])
    },
    function() {
      check("v3.4: right-clicking an unstreamable track still opens the menu", panel.contextMenuKind === "track")
      check("v3.4: Play Next and Add to Queue are both disabled on an unstreamable row",
        button("Play Next").enabled === false && button("Add to Queue").enabled === false)
      named(stage, "listKeyCatcher").forceActiveFocus()
      key(Qt.Key_Escape)
    },
    function() {
      check("v3.4: Esc closes the row menu without queueing anything", !panel.contextMenuOpen && svc.userQueue.length === 0)
    },

    // album add skip counts (Future Sounds: 1 streamable, 2 unreleased)
    function() {
      resetUserQueueChecks()
      svc.activeTab = 0
      showRow("Future Sounds")
      rightClick(leftRow("Future Sounds"))
    },
    function() {
      click(button("Add to Queue"))
    },
    function() {
      check("v3.4: album add skips unstreamable tracks and reports both counts",
        svc.userQueue.length === 1 && svc.userQueue[0].title === "Released Single" &&
        svc.notice === "Added 1 track to queue · 2 skipped (not streamable)")
      svc.clearUserQueue()
    },

    // Next from a context track plays the queue head; shuffle does not reorder it
    function() {
      resetUserQueueChecks()
      var ctx = mk("uqctx", 4)
      svc.setShuffle("album:uq", true)
      svc.playContext("album", "Queue Context", ctx, 1, "album:uq")
      host.queueProbe = svc.queue[svc.queueIndex + 1]
      var q1 = mk("uq1", 1)[0], q2 = mk("uq2", 1)[0]
      svc.playNextTrack(q1)
      svc.addTrackToQueue(q2)
      host.probe = { q1: q1, q2: q2 }
      svc.next()
    },
    function() {
      check("v3.4: Next from a context track plays the queue head", svc.currentTrack === host.probe.q1 &&
        svc.userQueue.length === 1 && svc.userQueue[0] === host.probe.q2)
      check("v3.4: the context queue/index stay underneath the queue", svc.queueIndex === 0 && svc.playingContextKey === "album:uq")
      svc.next()
    },
    function() {
      check("v3.4: with the context shuffled, queued tracks still play in added order",
        svc.currentTrack === host.probe.q2 && svc.userQueue.length === 0 && svc.isShuffled("album:uq"))
      svc.next()
    },
    function() {
      check("v3.4: when the queue drains, the context resumes AFTER the interrupted track",
        svc.currentTrack === host.queueProbe && svc.currentUserTrack === null &&
        svc.queueIndex === 1 && svc.userQueue.length === 0)
      check("v3.4: the interrupted track is not replayed", svc.currentTrack.uid !== mk("uqctx", 4)[1].uid)
      svc.setShuffle("album:uq", false)
    },

    // Previous steps back through actual history
    function() {
      resetUserQueueChecks()
      var ctx = mk("hctx", 4)
      svc.playContext("album", "History", ctx, 1, "album:hist")
      var p1 = mk("hp1", 1)[0], p2 = mk("hp2", 1)[0]
      svc.playNextTrack(p1)
      svc.addTrackToQueue(p2)
      host.probe = { p1: p1, p2: p2, interrupted: svc.queue[svc.queueIndex] }
      svc.next()
      svc.next()
    },
    function() {
      check("v3.4: two queued tracks played in order", svc.currentTrack === host.probe.p2 && svc.userQueue.length === 0)
      svc.prev()
    },
    function() {
      check("v3.4: Previous from a queued track goes to the previously played queued track",
        svc.currentTrack === host.probe.p1 && queueTitles().join("|") === "hp20")
      svc.prev()
    },
    function() {
      check("v3.4: Previous from the first queued track goes to the interrupted context track",
        svc.currentTrack === host.probe.interrupted && svc.currentUserTrack === null && svc.queueIndex === 1)
      check("v3.4: both queued tracks are pending again after stepping back", queueTitles().join("|") === "hp10|hp20")
      resetUserQueueChecks()
    },

    // queue-row double-click drops itself and everything ahead; right-click removes
    function() {
      resetUserQueueChecks()
      svc.playContext("album", "Drop", mk("dctx", 4), 0, "album:drop")
      var a = mk("dqa", 1)[0], b = mk("dqb", 1)[0], c = mk("dqc", 1)[0]
      svc.addTrackToQueue(a); svc.addTrackToQueue(b); svc.addTrackToQueue(c)
      host.probe = { a: a, b: b, c: c }
    },
    function() {
      doubleClick(named(stage, "upNextList").itemAtIndex(1))
    },
    function() {
      check("v3.4: double-clicking a queue row plays it immediately", svc.currentTrack === host.probe.b)
      check("v3.4: ...dropping it and everything ahead of it", svc.userQueue.length === 1 && svc.userQueue[0] === host.probe.c &&
        named(stage, "upNextHeader").text === "Up Next (1)")
      rightClick(named(stage, "upNextList").itemAtIndex(0))
    },
    function() {
      check("v3.4: right-clicking a queue row offers Remove from queue",
        panel.contextMenuKind === "queue" && panel.contextMenuEntries.length === 1 &&
        panel.contextMenuEntries[0].label === "Remove from queue")
      click(button("Remove from queue"))
    },
    function() {
      check("v3.4: Remove from queue drops only that row and keeps playback",
        svc.userQueue.length === 0 && svc.currentTrack === host.probe.b)
      resetUserQueueChecks()
    },

    // Up Next counts in the v3.2 content-driven height; panes stay equal
    function() {
      resetUserQueueChecks()
      svc.activeTab = 0
      panel.selectedAlbumUid = ""
      panel.pickAlbum(svc.collection[collIndex(host.croc)])
    },
    function() {
      // A full tick later, so the baseline is the settled height, not a
      // half-built detail pane.
      host.upHeightBefore = named(stage, "libraryRow").height
    },
    function() {
      check("v3.4: the no-queue baseline is a normal content-driven height",
        host.upHeightBefore >= 6 * Style.space(30) - 0.5 && host.upHeightBefore <= Style.space(396) + 0.5)
      svc.addTrackToQueue(mk("uh1", 1)[0])
      svc.addTrackToQueue(mk("uh2", 1)[0])
    },
    function() {
      var lr = named(stage, "libraryRow"), lp = named(stage, "leftPane"), dp = named(stage, "detailPane")
      log("v3.4 Up Next height: before=" + host.upHeightBefore + " after=" + lr.height +
        " upNext=" + named(stage, "upNext").height + " panes=" + lp.height + "/" + dp.height)
      check("v3.4: Up Next rows count in the content-driven height",
        lr.height > host.upHeightBefore + 50 && lr.height <= Style.space(396) + 0.5)
      check("v3.4: both panes stay exactly equal with Up Next visible",
        Math.abs(lp.height - lr.height) < 0.5 && Math.abs(dp.height - lr.height) < 0.5 &&
        Math.abs(lp.mapToItem(lr, 0, lp.height).y - dp.mapToItem(lr, 0, dp.height).y) < 0.5)
      check("v3.4: the detail content still fits inside the pane",
        named(stage, "upNext").mapToItem(dp, 0, 0).y >= 0 &&
        named(stage, "upNext").mapToItem(dp, 0, 0).y + named(stage, "upNext").height <= dp.height)
      svc.clearUserQueue()
    },

    // ---- pre-release: Up Next gets its own bordered sub-frame ----
    function() {
      resetUserQueueChecks()
      svc.loadLibrary()
      panel.selectedPlaylistUid = ""
      panel.selectedAlbumUid = ""
      svc.activeTab = 0
      searchField().text = ""
      svc.search("")
      panel.pickAlbum(svc.collection[collIndex(host.croc)])
      showRow(host.croc)
    },
    function() {
      var f = named(stage, "upNext"), dp = named(stage, "detailPane")
      var headY = named(stage, "detailTitle").mapToItem(dp, 0, 0).y
      check("pre-release: an empty queue shows NO Up Next frame and leaves no gap",
        f.visible === false && f.height === 0 && Math.abs(headY - Style.spacing.sm) < 0.5)
      host.frameNoQueueHeadY = headY
      svc.addTrackToQueue(mk("fr1", 1)[0])
    },
    function() {
      var f = named(stage, "upNext"), dp = named(stage, "detailPane")
      var lp = named(stage, "leftPane"), lr = named(stage, "libraryRow"), list = named(stage, "upNextList")
      var head = named(stage, "upNextHeader"), clear = named(stage, "upNextClear")
      var headY = named(stage, "detailTitle").mapToItem(dp, 0, 0).y
      var hy = head.mapToItem(f, 0, 0).y, cy = clear.mapToItem(f, 0, 0).y
      check("pre-release: a non-empty queue shows the bordered Up Next frame",
        f.visible === true && f.height > 0 && f.border.width > 0)
      check("pre-release: the frame border is the shared pane/control border colour",
        f.border.color === dp.border.color && f.border.color === lp.border.color &&
        f.border.color === named(stage, "footer").border.color)
      check("pre-release: the frame height includes its own border and padding",
        Math.abs(f.height - (clear.height + Style.space(2) + list.height
          + 2 * (f.border.width + panel.upNextFramePadding))) < 0.5)
      check("pre-release: header and Clear sit inside the frame's top row",
        isInside(head, f) && isInside(clear, f) &&
        hy >= f.contentTopInset - 0.5 && hy + head.height <= f.contentTopInset + clear.height + 0.5 &&
        Math.abs((hy + head.height / 2) - (cy + clear.height / 2)) < 1)
      check("pre-release: queued rows start below the header/Clear top row",
        list.mapToItem(f, 0, 0).y >= f.contentTopInset + clear.height - 0.5)
      check("pre-release: the frame adds its real height + gap above the album header",
        Math.abs(headY - (host.frameNoQueueHeadY + f.height + Style.spacing.sm)) < 0.5)
      check("pre-release: a small queue keeps both panes exactly equal",
        Math.abs(lp.height - lr.height) < 0.5 && Math.abs(dp.height - lr.height) < 0.5 &&
        Math.abs(lp.mapToItem(lr, 0, lp.height).y - dp.mapToItem(lr, 0, dp.height).y) < 0.5)
      for (var i = 0; i < 7; i++) svc.addTrackToQueue(mk("frx" + i, 1)[0])
    },
    function() {
      var f = named(stage, "upNext"), dp = named(stage, "detailPane")
      var lp = named(stage, "leftPane"), lr = named(stage, "libraryRow")
      var list = named(stage, "upNextList"), tl = trackList()
      var trackY = tl.contentY
      check("pre-release: the queue list caps at six visible rows and scrolls internally",
        list.count === 8 && Math.abs(list.height - 6 * Style.space(30)) < 0.5 &&
        list.contentHeight > list.height + 1)
      list.contentY = list.contentHeight - list.height
      check("pre-release: scrolling the queue never scrolls the album track list",
        list.contentY > 0 && tl.contentY === trackY)
      check("pre-release: a large queue keeps both panes exactly equal with the frame present",
        Math.abs(lp.height - lr.height) < 0.5 && Math.abs(dp.height - lr.height) < 0.5 &&
        Math.abs(lp.mapToItem(lr, 0, lp.height).y - dp.mapToItem(lr, 0, dp.height).y) < 0.5)
      check("pre-release: the frame stays inside the detail pane",
        f.mapToItem(dp, 0, 0).y >= 0 && f.mapToItem(dp, 0, 0).y + f.height <= dp.height)
      svc.clearUserQueue()
    },
    function() {
      check("pre-release: clearing the queue removes the frame (no frame, no leftover gap)",
        named(stage, "upNext").visible === false && named(stage, "upNext").height === 0)
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      svc.activeTab = 0
      searchField().text = ""
      svc.search("")
      panel.focusPane = ""
      panel.listCursor = -1
      panel.trackCursor = -1
    },

    // same context keeps the queue; a new context clears it
    function() {
      resetUserQueueChecks()
      var a = mk("nca", 3), b = mk("ncb", 3)
      svc.playContext("album", "A", a, 0, "album:na")
      svc.playNextTrack(mk("ncq", 1)[0])
      svc.playContext("album", "A", a, 1, "album:na")
    },
    function() {
      check("v3.4: playing another track in the SAME context keeps the queue", svc.userQueue.length === 1)
      svc.playContext("album", "B", mk("ncb", 3), 0, "album:nb")
    },
    function() {
      check("v3.4: playing a track in a NEW context clears the queue", svc.userQueue.length === 0)
      resetUserQueueChecks()
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      svc.activeTab = 0
      searchField().text = ""
      svc.search("")
      panel.focusPane = ""
      panel.listCursor = -1
      panel.trackCursor = -1
    },

    // ======================================== v3.5 ==========================================
    // Part A: sort direction toggle (Albums full set, Playlists reduced set).
    function() {
      if (!panel.opened) panel.open()
      svc.loadLibrary()
      resetUserQueueChecks()
      svc.setHidePreorders(false)
      svc.activeTab = 0
      svc.setSortMode("title")
      svc.setSortDirection("asc")
      svc.setPlaylistSortMode("title")
      svc.setPlaylistSortDirection("asc")
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.focusPane = ""
      panel.listCursor = -1
      panel.trackCursor = -1
      panel.queueCursor = -1
      searchField().text = ""
      svc.search("")
      prepLists()
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
      showRow("La Dee La La")
    },
    function() {
      var d = named(stage, "sortDirectionButton"), s = sortButton()
      check("v3.5 A: a direction button sits beside Sort, 28 px tall and button-styled",
        !!d && d.visible === true && Math.round(d.height) === 28 && d.height === Style.spacing.controlHeight &&
        d.bordered === true && d.tooltipText === "Reverse sort direction")
      check("v3.5 A: it sits immediately to the right of Sort, on the same line",
        Math.abs(d.mapToItem(stage, 0, 0).y - s.mapToItem(stage, 0, 0).y) < 1 &&
        d.mapToItem(stage, 0, 0).x >= s.mapToItem(stage, 0, 0).x + s.width - 1)
      check("v3.5 A: the glyph shows the CURRENT direction (up = ascending)",
        d.iconText === LibraryModel.sortDirectionArrow("asc") && d.iconText === "\uf062")
    },
    function() {
      // Defaults must be exactly the v3 comparators, criterion by criterion.
      var modes = ["added", "artist", "title", "release"], ok = true, why = ""
      for (var i = 0; i < modes.length; i++) {
        var legacy = LibraryModel.sortAlbums(svc.collection, modes[i], false)
        var explicit = LibraryModel.sortAlbums(svc.collection, modes[i], false,
          LibraryModel.defaultSortDirection("albums", modes[i]))
        if (!sameOrder(legacy, explicit)) { ok = false; why = modes[i] }
      }
      var legacyPl = LibraryModel.sortPlaylists(svc.playlists, "title")
      var explicitPl = LibraryModel.sortPlaylists(svc.playlists, "title", "asc")
      check("v3.5 A: each Albums criterion's default direction reproduces the pre-v3.5 comparator exactly" + (why ? " (" + why + ")" : ""), ok)
      check("v3.5 A: the Playlist default direction reproduces the pre-v3.5 comparator exactly", sameOrder(legacyPl, explicitPl))
      check("v3.5 A: documented defaults (Albums added/release descending, artist/title ascending; Playlists ascending)",
        LibraryModel.defaultSortDirection("albums", "added") === "desc" &&
        LibraryModel.defaultSortDirection("albums", "release") === "desc" &&
        LibraryModel.defaultSortDirection("albums", "artist") === "asc" &&
        LibraryModel.defaultSortDirection("albums", "title") === "asc" &&
        LibraryModel.defaultSortDirection("playlists", "added") === "asc" &&
        LibraryModel.defaultSortDirection("playlists", "title") === "asc")
      check("v3.5 A: untouched Title A–Z starts ascending exactly as before", svc.sortDirection === "asc" && titlesEqual(leftTitles(), expTitle))
    },
    function() { click(named(stage, "sortDirectionButton")) },
    function() {
      check("v3.5 A: one click on Title A–Z flips to the EXACT reverse, ties included",
        svc.sortDirection === "desc" && titlesEqual(leftTitles(), expTitle.slice().reverse()))
      check("v3.5 A: the button and the focused sort row now show the down arrow",
        named(stage, "sortDirectionButton").iconText === "\uf063")
      check("v3.5 A: flipping returns focus to the search field", searchField().activeFocus)
      click(named(stage, "sortDirectionButton"))
    },
    function() {
      check("v3.5 A: clicking again restores the default order and up arrow",
        svc.sortDirection === "asc" && titlesEqual(leftTitles(), expTitle) &&
        named(stage, "sortDirectionButton").iconText === "\uf062")
      svc.setSortMode("release")
    },
    function() {
      check("v3.5 A: Release date still defaults to newest-first",
        svc.sortDirection === "desc" && titlesEqual(leftTitles(), expRelease))
      click(named(stage, "sortDirectionButton"))
    },
    function() {
      check("v3.5 A: Release date flips to the exact reverse (oldest-first)",
        svc.sortDirection === "asc" && titlesEqual(leftTitles(), expRelease.slice().reverse()))
      click(named(stage, "sortDirectionButton"))
      svc.setSortMode("added")
    },
    function() {
      check("v3.5 A: Recently added still defaults to newest-first",
        svc.sortDirection === "desc" && titlesEqual(leftTitles(), expAdded))
      click(named(stage, "sortDirectionButton"))
    },
    function() {
      check("v3.5 A: Recently added flips to the exact reverse",
        svc.sortDirection === "asc" && titlesEqual(leftTitles(), expAdded.slice().reverse()))
      click(named(stage, "sortDirectionButton"))
      svc.setSortMode("title")
      svc.setSortDirection("desc")
    },
    function() {
      check("v3.5 A: Title direction desc is remembered while the criterion is unchanged",
        svc.sortDirection === "desc" && titlesEqual(leftTitles(), expTitle.slice().reverse()))
      svc.setSortMode("artist")
    },
    function() {
      check("v3.5 A: choosing a NEW criterion resets direction to that criterion's default",
        svc.sortMode === "artist" && svc.sortDirection === "asc" && titlesEqual(leftTitles(), expArtist))
      svc.setSortMode("title")
      svc.setSortDirection("desc")
      click(sortButton())
    },
    function() {
      check("v3.5 A: sort menu still has exactly the four Albums criteria",
        panel.menuItems.map(function(m) { return m.label }).join("|") === "Recently added|Artist A–Z|Title A–Z|Release date")
      check("v3.5 A: the selected sort row shows the same direction arrow",
        panel.menuItems[2].icon === "\uf00c" && panel.menuItems[2].trailing === "\uf063" &&
        panel.menuItems.filter(function(m) { return m.trailing && m.trailing !== "" }).length === 1)
      click(button("Title A–Z"))
    },
    function() {
      check("v3.5 A: choosing the selected criterion again restores its default direction",
        svc.sortMode === "title" && svc.sortDirection === "asc" && titlesEqual(leftTitles(), expTitle))
      click(button("Playlists (2)"))
    },
    function() {
      check("v3.5 A: the Playlists tab has its own direction (up by default)",
        svc.activeTab === 1 && svc.playlistSortDirection === "asc" &&
        named(stage, "sortDirectionButton").iconText === "\uf062" &&
        titlesEqual(leftTitles(), ["Postpunky?", "Rock & Roll Faves"]))
      click(sortButton())
    },
    function() {
      check("v3.5 A: the Playlists sort menu still offers exactly two criteria",
        panel.menuItems.map(function(m) { return m.label }).join("|") === "Recently added|Title A–Z" && panel.menuItems.length === 2)
      key(Qt.Key_Escape)
      click(named(stage, "sortDirectionButton"))
    },
    function() {
      check("v3.5 A: Playlists Title A–Z flips to the exact reverse",
        svc.playlistSortDirection === "desc" && titlesEqual(leftTitles(), ["Rock & Roll Faves", "Postpunky?"]) &&
        named(stage, "sortDirectionButton").iconText === "\uf063")
      check("v3.5 A: flipping Playlists does not touch the Albums direction", svc.sortDirection === "asc" || svc.sortDirection === "desc")
      svc.setPlaylistSortDirection("asc")
      svc.setPlaylistSortMode("title")
      svc.activeTab = 0
      svc.setSortMode("title")
      svc.setSortDirection("asc")
    },
    // Search groups follow the criterion and the direction.
    function() {
      searchField().text = "o"
      svc.search("o")
    },
    function() {
      host.probe = { albumsAsc: svc.searchResults.albums.map(function(a) { return a.title }).join("|") }
      svc.setSortDirection("desc")
    },
    function() {
      var albumsDesc = svc.searchResults.albums.map(function(a) { return a.title }).join("|")
      check("v3.5 A: the search Albums group follows the direction exactly",
        albumsDesc === host.probe.albumsAsc.split("|").reverse().join("|") && albumsDesc !== host.probe.albumsAsc)
      svc.setSortDirection("asc")
      svc.setPlaylistSortMode("title")
      svc.setPlaylistSortDirection("asc")
      searchField().text = "o"
      svc.search("o")
    },
    function() {
      host.probe = { plAsc: svc.searchResults.playlists.map(function(p) { return p.name }).join("|") }
      svc.setPlaylistSortDirection("desc")
    },
    function() {
      var plDesc = svc.searchResults.playlists.map(function(p) { return p.name }).join("|")
      check("v3.5 A: the search Playlists group follows its tab's direction exactly",
        plDesc === host.probe.plAsc.split("|").reverse().join("|") && plDesc !== host.probe.plAsc)
      searchField().text = ""
      svc.search("")
      svc.setPlaylistSortDirection("asc")
    },

    // Part B: complete Tab traversal, queue control and visible focus.
    function() {
      resetUserQueueChecks()
      svc.activeTab = 0
      svc.setSortMode("title")
      svc.setSortDirection("asc")
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.focusPane = ""
      panel.listCursor = -1
      panel.trackCursor = -1
      panel.queueCursor = -1
      searchField().text = ""
      svc.search("")
      prepLists()
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
      showRow("La Dee La La")
      searchField().forceActiveFocus()
      host.chain = []
    },
    function() {
      for (var i = 0; i < 13; i++) { key(Qt.Key_Tab); host.chain.push(panel.focusControlName()) }
    },
    function() {
      log("v3.5 Tab chain (no queue): " + host.chain.join("|"))
      check("v3.5.1: the full Tab order with NO queue skips the queue frame entirely and wraps",
        host.chain.join("|") === "searchAction|settingsButton|albumsButton|playlistsButton|sortButton|sortDirectionButton|leftList|trackList|footerShuffle|footerPrev|footerPlay|footerNext|searchField")
      svc.addTrackToQueue(svc.collection[collIndex("La Dee La La")].tracks[0])
      svc.addTrackToQueue(svc.collection[collIndex("La Dee La La")].tracks[1])
      searchField().forceActiveFocus()
      host.chain = []
    },
    function() {
      for (var i = 0; i < 15; i++) { key(Qt.Key_Tab); host.chain.push(panel.focusControlName()) }
    },
    function() {
      log("v3.5 Tab chain (queue): " + host.chain.join("|"))
      check("v3.5.1: with a queue the chain adds Up Next and Clear between the left list and the track list",
        host.chain.join("|") === "searchAction|settingsButton|albumsButton|playlistsButton|sortButton|sortDirectionButton|leftList|upNextList|upNextClear|trackList|footerShuffle|footerPrev|footerPlay|footerNext|searchField")
      panel.focusPane = ""
      panel.listCursor = -1
      named(stage, "sortDirectionButton").forceActiveFocus()
      key(Qt.Key_Tab)
    },
    function() {
      var rows = panel.listRows, idx = -1
      for (var i = 0; i < rows.length; i++) if (rows[i].uid === panel.selectedAlbumUid) { idx = i; break }
      check("v3.5 B: entering the left list focuses the selected/current row with a visible cursor",
        panel.focusPane === "list" && idx >= 0 && panel.listCursor === idx &&
        alpha(named(leftList().itemAtIndex(idx), "rowFill")) > 0.1 &&
        String(named(leftList().itemAtIndex(idx), "rowFill").border.color) === String(Color.accent))
      key(Qt.Key_Tab)
    },
    function() {
      check("v3.5 B: Tab from the left list enters Up Next at row 0, visibly focused",
        panel.focusPane === "queue" && panel.queueCursor === 0 &&
        alpha(named(named(stage, "upNextList").itemAtIndex(0), "upNextFill")) > 0.1 &&
        String(named(named(stage, "upNextList").itemAtIndex(0), "upNextFill").border.color) === String(Color.accent))
      key(Qt.Key_Down)
    },
    function() {
      check("v3.5 B: arrows move within Up Next and move the visible cursor",
        panel.queueCursor === 1 &&
        alpha(named(named(stage, "upNextList").itemAtIndex(0), "upNextFill")) < 0.15 &&
        alpha(named(named(stage, "upNextList").itemAtIndex(1), "upNextFill")) > 0.1 &&
        String(named(named(stage, "upNextList").itemAtIndex(0), "upNextFill").border.color) !== String(Color.accent) &&
        String(named(named(stage, "upNextList").itemAtIndex(1), "upNextFill").border.color) === String(Color.accent))
      key(Qt.Key_Tab)
    },
    function() {
      check("v3.5 B: Tab leaves Up Next for Clear, which shows its focus ring",
        named(stage, "upNextClear").activeFocus && named(stage, "upNextClear")._showFocusRing === true)
      key(Qt.Key_Tab)
    },
    function() {
      check("v3.5 B: Tab from Clear enters the track list at the current row",
        panel.focusPane === "tracks" && panel.trackCursor === 0 &&
        alpha(named(trackList().itemAtIndex(0), "trackFill")) > 0.1 &&
        String(named(trackList().itemAtIndex(0), "trackFill").border.color) === String(Color.accent))
      key(Qt.Key_Tab)
    },
    function() {
      check("v3.5 B: Tab from the track list reaches the footer transport (Shuffle)",
        named(stage, "footerShuffle").activeFocus && named(stage, "footerShuffle")._showFocusRing === true)
      key(Qt.Key_Tab); key(Qt.Key_Tab); key(Qt.Key_Tab)
    },
    function() {
      check("v3.5 B: the footer chain reaches Next (after Shuffle, Previous, Play/Pause)",
        named(stage, "footerNext").activeFocus)
      // Activate a footer control by keyboard: Shuffle is the safest (no playback).
      named(stage, "footerShuffle").forceActiveFocus()
      var before = panel.shuffleOn
      key(Qt.Key_Return)
      check("v3.5 B: Enter activates a focused footer button", panel.shuffleOn === !before)
      named(stage, "footerShuffle").forceActiveFocus()
      var mid = panel.shuffleOn
      key(Qt.Key_Space)
      check("v3.5 B: Space activates a focused footer button too", panel.shuffleOn === !mid)
      if (panel.shuffleOn) svc.setShuffle(panel.contextKey, false)
    },
    function() {
      searchField().forceActiveFocus()
      host.chain = []
      for (var i = 0; i < 15; i++) { shiftKey(Qt.Key_Tab); host.chain.push(panel.focusControlName()) }
    },
    function() {
      log("v3.5 reverse chain: " + host.chain.join("|"))
      check("v3.5.1: Shift+Tab reverses the full chain across every boundary, queue included",
        host.chain.join("|") === "footerNext|footerPlay|footerPrev|footerShuffle|trackList|upNextClear|upNextList|leftList|sortDirectionButton|sortButton|playlistsButton|albumsButton|settingsButton|searchAction|searchField")
    },
    function() {
      panel.enterQueueRegion()
    },
    function() {
      check("v3.5 B: Up Next owns focus before the queue vanishes", panel.focusPane === "queue" && named(stage, "listKeyCatcher").activeFocus)
      svc.clearUserQueue()
    },
    function() {
      check("v3.5 B: a queue vanishing under focus lands on the track list, never on nothing",
        panel.upNextCount === 0 && panel.focusPane === "tracks" && named(stage, "listKeyCatcher").activeFocus)
    },

    // Part C: queue keys on the focused list only.
    function() {
      resetUserQueueChecks()
      svc.activeTab = 0
      searchField().text = ""
      svc.search("")
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
      prepLists()
      panel.enterTrackRegion()
    },
    function() {
      check("v3.5 C: track list focus starts at row 0", panel.focusPane === "tracks" && panel.trackCursor === 0)
      ctrlKey(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Ctrl+Enter in the track list adds the focused track to the queue",
        svc.userQueue.length === 1 && queueTitles().join("|") === "La Dee La La Song")
      check("v3.5 C: adding to the queue never starts or changes playback",
        svc.currentTrack === null && svc.isPlaying === false && svc.playingContextKey === "")
      key(Qt.Key_Down)
      altKey(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Alt+Enter in the track list puts the focused track next",
        queueTitles().join("|") === "Waiting For Marvin|La Dee La La Song" && svc.currentTrack === null)
      key(Qt.Key_Down)
      ctrlKey(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: further Ctrl+Enter adds append in order",
        queueTitles().join("|") === "Waiting For Marvin|La Dee La La Song|The White Lady")
      svc.clearUserQueue()
      panel.selectedAlbumUid = ""
      panel.pickAlbum(svc.collection[collIndex(host.fi)])
      panel.enterTrackRegion()
    },
    function() {
      ctrlKey(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Ctrl+Enter on an unstreamable track is a no-op",
        svc.userQueue.length === 0 && svc.notice === "Not yet released")
      altKey(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Alt+Enter on an unstreamable track is the same no-op + notice",
        svc.userQueue.length === 0 && svc.notice === "Not yet released" && svc.currentTrack === null)
      svc.clearUserQueue()
      panel.selectedAlbumUid = ""
      panel.pickAlbum(svc.collection[collIndex("Future Sounds")])
      panel.listCursor = -1
      panel.focusToken("leftList")
    },
    function() {
      var rows = panel.listRows, idx = -1
      for (var i = 0; i < rows.length; i++) if (rows[i].uid === panel.selectedAlbumUid) { idx = i; break }
      check("v3.5 C: the left list is focused on the whole-item row", panel.focusPane === "list" && panel.listCursor === idx)
      ctrlKey(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Ctrl+Enter on an album row adds the WHOLE item, streamable tracks only",
        queueTitles().join("|") === "Released Single" &&
        svc.notice === "Added 1 track to queue · 2 skipped (not streamable)")
      host.probe = { titles: queueTitles().join("|"), notice: svc.notice }
      altKey(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Alt+Enter on an album row does nothing (albums have no Play Next)",
        queueTitles().join("|") === host.probe.titles && svc.notice === host.probe.notice)
      svc.clearUserQueue()
      svc.activeTab = 0
      var a = mk("qkctx", 4)
      svc.playContext("album", "Queue Keys", a, 1, "album:qk")
      host.probe = { a: mk("qka", 1)[0], b: mk("qkb", 1)[0], c: mk("qkc", 1)[0], queueIndex: svc.queueIndex }
      svc.addTrackToQueue(host.probe.a)
      svc.addTrackToQueue(host.probe.b)
      svc.addTrackToQueue(host.probe.c)
      panel.queueCursor = -1
      panel.enterQueueRegion()
    },
    function() {
      key(Qt.Key_Down)
    },
    function() {
      check("v3.5 C: queue cursor starts on the second row", panel.focusPane === "queue" && panel.queueCursor === 1)
      key(Qt.Key_Delete)
    },
    function() {
      check("v3.5 C: Delete removes the focused queue row and stays on the NEXT row",
        queueTitles().join("|") === "qka0|qkc0" && panel.queueCursor === 1 && svc.currentTrack !== null)
      check("v3.5 C: removing a queue row never changes the playback context",
        svc.queueIndex === host.probe.queueIndex && svc.playingContextKey === "album:qk")
      key(Qt.Key_Delete)
    },
    function() {
      check("v3.5 C: deleting the LAST row selects the previous one",
        queueTitles().join("|") === "qka0" && panel.queueCursor === 0)
      key(Qt.Key_Delete)
    },
    function() {
      check("v3.5 C: deleting the only row lands focus on the track list",
        svc.userQueue.length === 0 && panel.focusPane === "tracks" && named(stage, "listKeyCatcher").activeFocus)
      svc.addTrackToQueue(host.probe.a)
      svc.addTrackToQueue(host.probe.b)
      svc.addTrackToQueue(host.probe.c)
      panel.enterQueueRegion()
    },
    function() {
      key(Qt.Key_Down)
      key(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Enter on a queue row plays it NOW with double-click semantics",
        svc.currentTrack === host.probe.b && queueTitles().join("|") === "qkc0")
      check("v3.5 C: Enter leaves the underlying context/index untouched",
        svc.queueIndex === host.probe.queueIndex && svc.playingContextKey === "album:qk")
      resetUserQueueChecks()
    },
    // The search field is a text editor: no queue shortcuts, normal Delete.
    function() {
      searchField().text = "abc"
      searchField().cursorPosition = 1
      searchField().forceActiveFocus()
      var before = svc.userQueue.length
      ctrlKey(Qt.Key_Return)
      altKey(Qt.Key_Return)
      check("v3.5 C: Ctrl/Alt+Enter in the search field do nothing (no queue, no activation)",
        searchField().text === "abc" && svc.userQueue.length === before)
      key(Qt.Key_Delete)
    },
    function() {
      check("v3.5 C: Delete in the search field deletes text like any editor", searchField().text === "ac")
      searchField().text = ""
      searchField().cursorPosition = 0
      svc.search("")
    },
    // Addendum: Menu / Shift+F10, Up/Down, Enter activates, Esc closes, focus returns.
    function() {
      resetUserQueueChecks()
      svc.activeTab = 0
      searchField().text = ""
      svc.search("")
      panel.selectedAlbumUid = ""
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
      prepLists()
      panel.trackCursor = -1
      panel.enterTrackRegion()
      menuKey()
    },
    function() {
      check("v3.5 C: Menu on a focused track row opens the same context menu",
        panel.contextMenuOpen && panel.contextMenuKind === "track" && panel.contextMenuSource === "tracks")
      check("v3.5 C: menu rows carry the dimmed keyboard hints",
        button("Play Next").trailingText === "Alt+Enter" && button("Add to Queue").trailingText === "Ctrl+Enter")
      key(Qt.Key_Down)
    },
    function() {
      check("v3.5 C: Down navigates the context menu", panel.contextMenuIndex === 1)
      key(Qt.Key_Up)
      key(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Enter activates the highlighted item and closes the menu",
        !panel.contextMenuOpen && queueTitles().join("|") === "La Dee La La Song" && svc.currentTrack === null)
      check("v3.5 C: focus returns to the opening row", panel.focusPane === "tracks" && panel.trackCursor === 0 &&
        named(stage, "listKeyCatcher").activeFocus)
      host.probe = { titles: queueTitles().join("|") }
      menuKey()
    },
    function() {
      check("v3.5 C: the context menu reopens on the same row", panel.contextMenuOpen && panel.contextMenuKind === "track")
      key(Qt.Key_Escape)
    },
    function() {
      check("v3.5 C: Esc closes the menu without acting and returns focus to the row",
        !panel.contextMenuOpen && queueTitles().join("|") === host.probe.titles &&
        panel.focusPane === "tracks" && named(stage, "listKeyCatcher").activeFocus)
      panel.enterQueueRegion()
      shiftF10()
    },
    function() {
      check("v3.5 C: Shift+F10 opens the queue row's menu with its Delete hint",
        panel.contextMenuOpen && panel.contextMenuKind === "queue" && panel.contextMenuSource === "queue" &&
        button("Remove from queue").trailingText === "Del")
      key(Qt.Key_Return)
    },
    function() {
      check("v3.5 C: Enter removes the focused queue row and returns focus to the queue",
        queueTitles().join("|") === "" && panel.focusPane === "tracks" && !panel.contextMenuOpen)
      resetUserQueueChecks()
    },

    // Part D: keyboard shortcuts view in the body slot.
    function() {
      resetUserQueueChecks()
      svc.activeTab = 0
      svc.setSortMode("title")
      svc.setSortDirection("asc")
      searchField().text = ""
      svc.search("")
      panel.selectedAlbumUid = ""
      panel.selectedPlaylistUid = ""
      panel.pickAlbum(svc.collection[collIndex(host.croc)])
      prepLists()
      showRow(host.croc)
      svc.addTrackToQueue(mk("helpq1", 1)[0])
      svc.addTrackToQueue(mk("helpq2", 1)[0])
      leftList().contentY = 4
      trackList().contentY = 3
      host.probe = {
        uid: panel.selectedAlbumUid,
        leftY: leftList().contentY,
        trackY: trackList().contentY,
        queue: queueTitles().join("|"),
        queueIndex: svc.queueIndex,
        libraryRowY: named(stage, "libraryRow").mapToItem(stage, 0, 0).y,
        libraryRowH: named(stage, "libraryRow").height
      }
    },
    function() {
      openSettings()
      click(button("Keyboard shortcuts"))
    },
    function() {
      var hv = named(stage, "shortcutsView")
      var groups = allNamed(stage, "shortcutsGroup", []).filter(function(g) { return g.visible })
      var keys = allNamed(stage, "shortcutsKey", []).filter(function(k) { return k.visible })
      var descs = allNamed(stage, "shortcutsDesc", []).filter(function(d) { return d.visible })
      log("v3.5 help: groups=" + groups.length + " rows=" + keys.length + " height=" + hv.height +
        " content=" + named(stage, "shortcutsFlickable").contentHeight)
      check("v3.5 D: Keyboard shortcuts opens the shortcuts view in the body slot",
        panel.helpOpen && hv.visible === true && Math.abs(hv.mapToItem(stage, 0, 0).y - host.probe.libraryRowY) < 0.5 &&
        Math.abs(hv.width - named(stage, "libraryRow").width) < 0.5)
      check("v3.5 D: opening moves focus into the view", hv.activeFocus && panel.focusControlName() === "shortcutsView")
      check("v3.5 D: the four groups appear in order in two side-by-side columns",
        groups.map(function(g) { return g.text }).join("|") === "Navigation|Playback|Queue|Search & menus" &&
        groups[0].mapToItem(hv, 0, 0).x < groups[2].mapToItem(hv, 0, 0).x &&
        Math.abs(groups[0].mapToItem(hv, 0, 0).x - groups[1].mapToItem(hv, 0, 0).x) < 0.5 &&
        Math.abs(groups[2].mapToItem(hv, 0, 0).x - groups[3].mapToItem(hv, 0, 0).x) < 0.5)
      check("v3.5 D: rows use the existing two-column sizes and colours",
        keys.length === 16 && keys.length === descs.length &&
        keys[0].width === Style.space(108) && descs[0].x === Style.space(112) &&
        keys[0].font.pixelSize === Style.font.bodySmall && descs[0].font.pixelSize === Style.font.caption &&
        String(keys[0].color) === String(named(stage, "searchField").color))
      check("v3.5.1 D: the reflowed view fits its height (internal scroll is only a fallback)",
        hv.height >= 6 * Style.space(30) - 0.5 && hv.height <= Style.space(396) + 0.5 &&
        named(stage, "shortcutsFlickable").contentHeight <= named(stage, "shortcutsFlickable").height + 0.5)
    },
    function() {
      var all = panel.helpRows.map(function(r) { return (r.key || "") + " " + (r.text || "") }).join(" | ")
      var required = ["Tab / Shift+Tab", "↑ / ↓", "← / →", "Enter", "Space", "Ctrl+Enter", "Alt+Enter",
        "Delete", "/", "Menu / Shift+F10", "Esc", "sort direction"]
      var missing = required.filter(function(k) { return all.indexOf(k) < 0 })
      check("v3.5 D: every Part A–C/addendum shortcut is listed" + (missing.length ? " (missing " + missing.join(", ") + ")" : ""),
        missing.length === 0)
      key(Qt.Key_Escape)
    },
    function() {
      check("v3.5 D: Esc closes the view, keeps the window, and returns focus to the gear",
        !panel.helpOpen && panel.opened && settingsButton().activeFocus)
      check("v3.5 D: selection, pane scrolling and the queue are restored exactly",
        panel.selectedAlbumUid === host.probe.uid &&
        leftList().contentY === host.probe.leftY && trackList().contentY === host.probe.trackY &&
        queueTitles().join("|") === host.probe.queue && svc.queueIndex === host.probe.queueIndex)
      openSettings()
      click(button("Keyboard shortcuts"))
    },
    function() {
      check("v3.5 D: the shortcuts item opens the view again", panel.helpOpen)
      openSettings()
      click(button("Keyboard shortcuts"))
    },
    function() {
      check("v3.5 D: selecting Keyboard shortcuts again closes the view (toggle)",
        !panel.helpOpen && panel.opened && settingsButton().activeFocus)
    },
    function() {
      // Reachable entirely from the keyboard: Tab to the gear, Enter, Down ×2, Enter.
      searchField().forceActiveFocus()
      key(Qt.Key_Tab); key(Qt.Key_Tab)
    },
    function() {
      check("v3.5 D: the keyboard path reaches the gear", settingsButton().activeFocus)
      key(Qt.Key_Return)
    },
    function() {
      check("v3.5 D: Enter opens the gear menu from the keyboard", panel.menuOpen && panel.menuKind === "more")
      key(Qt.Key_Down); key(Qt.Key_Down); key(Qt.Key_Return)
    },
    function() {
      check("v3.5 D: Down ×2 + Enter opens the shortcuts view from the keyboard",
        panel.helpOpen && named(stage, "shortcutsView").activeFocus)
      key(Qt.Key_Escape)
    },
    function() {
      check("v3.5 D: Esc from the keyboard path returns focus to the gear", !panel.helpOpen && settingsButton().activeFocus)
      // Leave non-default directions on disk for the relaunch phase.
      svc.setSortMode("title")
      svc.setSortDirection("desc")
      svc.setPlaylistSortMode("title")
      svc.setPlaylistSortDirection("desc")
      svc.setHidePreorders(true)
    },
    function() {
      check("v3.5 A: the final phase-1 directions are persisted for relaunch",
        svc.sortDirection === "desc" && svc.playlistSortDirection === "desc" && svc.hidePreorders === true)
      resetUserQueueChecks()
    },

    function() {
      svc.queue = [{ uid: "v32#0", title: host.longTitle + " " + host.longTitle, artist: "Long Title Artist", album: "Long", duration: 200, streamable: true }]
      svc.queueIndex = 0
      svc.isPlaying = false
      svc.isPaused = false
      svc.playbackError = ""
      svc.position = 50
      svc.duration = 200
    },
    function() {
      var f = named(stage, "footer"), pr = named(stage, "progressRow"), t = named(stage, "footerTitle"), tr = named(stage, "transportRow")
      log("v3.2 idle footer: height=" + f.height + " playing=" + host.playingFooterHeight + " progressVisible=" + pr.visible)
      check("v3.2: stopped/idle hides the progress row (bar + time labels)", pr.visible === false)
      check("v3.2: idle footer is measurably shorter than the playing footer", f.height < host.playingFooterHeight - 1)
      check("v3.2: idle footer still holds the now-playing line and the transport",
        t.mapToItem(f, 0, 0).y >= 0 && t.mapToItem(f, 0, 0).y + t.height <= f.height &&
        tr.mapToItem(f, 0, 0).y >= 0 && tr.mapToItem(f, 0, 0).y + tr.height <= f.height)
      svc.isPlaying = true
      svc.isPaused = false
    },
    function() {
      var f = named(stage, "footer"), pr = named(stage, "progressRow")
      check("v3.2: playing brings the progress row back", pr.visible === true)
      check("v3.2: the playing footer returns to its full height", Math.abs(f.height - host.playingFooterHeight) < 1)
      svc.isPlaying = false
      svc.isPaused = true
    },
    function() {
      check("v3.2: paused keeps the progress row (only stopped/idle collapses)", named(stage, "progressRow").visible === true)
      svc.isPaused = false
      svc.isPlaying = false
      svc.playbackError = "Couldn't play Idle Track — skipped"
    },
    function() {
      var f = named(stage, "footer"), pr = named(stage, "progressRow"), err = named(stage, "footerError"), sub = named(stage, "footerSub")
      log("v3.2 idle error footer: height=" + f.height + " errorVisible=" + err.visible)
      check("v3.2: an idle error is still shown in the footer", err.visible === true && err.text === "Couldn't play Idle Track — skipped" && sub.visible === false)
      check("v3.2: the idle error text sits inside the footer (not collapsed away)", err.mapToItem(f, 0, 0).y >= 0 && err.mapToItem(f, 0, 0).y + err.height <= f.height)
      check("v3.2: the error state does not force the progress row back", pr.visible === false)
      svc.playbackError = ""
      svc.queue = []
      svc.queueIndex = -1
      svc.position = 0
      svc.duration = 0
    },

    // ---- Post-v3.2 regression: the first track of a session (real mpv) ----
    function() {
      // The owner's player was left paused; mpv keeps `pause` across loadfile,
      // so a fresh session's first track loaded paused. The first click then
      // unpaused mpv while flipping the service's flag the other way, which
      // stopped the poll and froze the footer at 0:00. Play must clear the
      // inherited pause, and the poll must advance with NO track change.
      mpvPause.running = true
      host.pauseUntil = Date.now() + 1200
    },
    function() {
      var tone = Quickshell.env("HARNESS_TONE") || ""
      check("harness: a local tone fixture exists for the first-track check", tone !== "")
      check("harness: the isolated mpv is paused before the first track", mpvPauseExit === 0)
      svc.queue = [{ uid: "first#0", title: "First Track", artist: "A", album: "X", duration: 10, streamable: true, streamUrl: "file://" + tone }]
      svc.queueIndex = 0
      svc.isPlaying = false
      svc.isPaused = false
      svc.playbackError = ""
      svc.position = 0
      svc.duration = 10
      svc.pendingSeek = -1
      svc.playCurrent()
      host.pauseUntil = Date.now() + 3200
    },
    function() {
      check("first track after a fresh start plays (mpv's stale pause is cleared)", svc.isPlaying === true && svc.isPaused === false)
      check("first track position advances with NO track change", svc.position > 0.5)
      check("the footer elapsed label is no longer stuck at 0:00", named(stage, "elapsedLabel").text !== "0:00")
      svc.stop()
      svc.queue = []
      svc.queueIndex = -1
      svc.position = 0
      svc.duration = 0
    },

    // ---- Global keys: the toggle IPC verb and cold-start transport no-ops ----
    function() {
      // The plugin ships no binds. A user bind calls the plugin IPC, and this
      // verb asks the shell's own panel lifecycle to summon or hide this
      // plugin's popup (PluginShellApi.toggle, scoped to our own id).
      var calls = []
      var fake = {
        pluginId: "com.github.dtotheatothevtothee.omatimeatbandcamp",
        toggle: function(id, payload) { calls.push([String(id), String(payload)]); return true }
      }
      svc.shell = fake
      check("toggle IPC asks the shell to toggle this plugin's panel", svc.togglePanel() === "ok")
      check("...passing this plugin's id and no payload",
        calls.length === 1 && calls[0][0] === "com.github.dtotheatothevtothee.omatimeatbandcamp" && calls[0][1] === "")
      svc.shell = { pluginId: "com.github.dtotheatothevtothee.omatimeatbandcamp", toggle: function() { return false } }
      check("a refused toggle reports unavailable", svc.togglePanel() === "unavailable")
      svc.shell = { toggle: function() { return true } }
      check("toggle without a scoped plugin id reports unavailable", svc.togglePanel() === "unavailable")
      svc.shell = null
      check("toggle without a shell API reports unavailable (no crash)", svc.togglePanel() === "unavailable")
    },
    function() {
      // Cold state: nothing loaded this session. All three transport verbs are
      // harmless no-ops, and Next must never start unrequested playback.
      svc.queue = []
      svc.queueIndex = -1
      svc.isPlaying = false
      svc.isPaused = false
      svc.position = 0
      svc.duration = 0
      svc.playbackError = ""
      svc.togglePlay()
      check("cold start: play/pause does nothing (no track loaded)", svc.isPlaying === false && svc.isPaused === false && svc.currentTrack === null)
      svc.next()
      check("cold start: next never starts unrequested playback", svc.isPlaying === false && svc.currentTrack === null && svc.position === 0)
      svc.prev()
      check("cold start: previous never starts unrequested playback", svc.isPlaying === false && svc.currentTrack === null && svc.position === 0)
    },

    // ---- v3.5.5: queue persistence (Up Next only) ------------------------
    function() {
      resetUserQueueChecks()
      svc.loadLibrary()
      panel.selectedPlaylistUid = ""
      panel.selectedAlbumUid = ""
      panel.pickAlbum(svc.collection[collIndex("La Dee La La")])
      var alb = svc.collection[collIndex("La Dee La La")]
      host.probe = { t0: alb.tracks[0], t1: alb.tracks[1], t2: alb.tracks[2] }
      check("v3.5.5: a clean slate starts with an empty Up Next queue", svc.userQueue.length === 0)
    },
    function() {
      // Save/load round-trip: add two fixture tracks, forget the in-memory
      // state, and read the persisted queue back.
      svc.addTrackToQueue(host.probe.t0)
      svc.addTrackToQueue(host.probe.t1)
      host.probe.saved = queueTitles().join("|")
      clearQueueMemory()
      svc.restoreQueue()
      check("v3.5.5: the Up Next queue survives a save/load round-trip",
        queueTitles().join("|") === host.probe.saved &&
        host.probe.saved === "La Dee La La Song|Waiting For Marvin")
      check("v3.5.5: a restored queue starts stopped (playback is not restored)",
        svc.currentUserTrack === null && svc.isPlaying === false && svc.isPaused === false)
    },
    function() {
      // Duplicates are entries, not indices: A,B,A must come back as A,B,A.
      svc.clearUserQueue()
      svc.addTrackToQueue(host.probe.t0)
      svc.addTrackToQueue(host.probe.t1)
      svc.addTrackToQueue(host.probe.t0)
      clearQueueMemory()
      svc.restoreQueue()
      check("v3.5.5: duplicates and their order survive a save/load round-trip",
        queueTitles().join("|") === "La Dee La La Song|Waiting For Marvin|La Dee La La Song")
    },
    function() {
      // Consumption: playing the head removes it, and the persisted copy must
      // not bring it back after a simulated restart. Synthetic collection
      // tracks keep this check off the network (no stream source).
      resetUserQueueChecks()
      var ts = [
        { uid: "v355#0", title: "Persist A", artist: "P", album: "Persist", duration: 10, streamable: true },
        { uid: "v355#1", title: "Persist B", artist: "P", album: "Persist", duration: 10, streamable: true },
        { uid: "v355#2", title: "Persist C", artist: "P", album: "Persist", duration: 10, streamable: true }
      ]
      svc.collection = svc.collection.concat([synth("v355", "Persist", "P", ts)])
      svc.addTrackToQueue(ts[0])
      svc.addTrackToQueue(ts[1])
      svc.addTrackToQueue(ts[2])
      svc.startUserQueueAt(0)
      check("v3.5.5: starting a queued track consumes it from Up Next",
        svc.currentUserTrack === ts[0] && queueTitles().join("|") === "Persist B|Persist C")
      clearQueueMemory()
      svc.restoreQueue()
      check("v3.5.5: consumption persists across a simulated restart",
        queueTitles().join("|") === "Persist B|Persist C" && svc.currentUserTrack === null)
    },
    function() {
      // Clear persists: the live queue and the file both end up empty.
      resetUserQueueChecks()
      svc.addTrackToQueue(host.probe.t0)
      svc.clearUserQueue()
      clearQueueMemory()
      svc.restoreQueue()
      check("v3.5.5: Clear persists across a simulated restart", svc.userQueue.length === 0)
    },
    function() {
      // A new playback context clears the queue AND its persisted copy.
      resetUserQueueChecks()
      var a = synth("v355nca", "Persist A", "P", mk("v355pa", 2))
      var b = synth("v355ncb", "Persist B", "P", mk("v355pb", 2))
      svc.collection = svc.collection.concat([a, b])
      svc.playContext("album", "Persist A", a.tracks, 0, "album:v355nca")
      svc.addTrackToQueue(a.tracks[1])
      svc.playContext("album", "Persist B", b.tracks, 0, "album:v355ncb")
      clearQueueMemory()
      svc.restoreQueue()
      check("v3.5.5: a new playback context clears the persisted queue",
        svc.userQueue.length === 0)
    },
    function() {
      // Revalidation: an entry whose track is gone is dropped silently.
      resetUserQueueChecks()
      var gone = { uid: "gone#0", title: "Gone Track", artist: "Nobody", album: "Nowhere" }
      svc.restoreQueue(JSON.stringify({ version: 1, pending: [UserQueue.identityOf(gone), UserQueue.identityOf(host.probe.t0)] }))
      check("v3.5.5: restore silently drops an entry whose track is gone",
        queueTitles().join("|") === "La Dee La La Song")
    },
    function() {
      // Revalidation: an entry that is no longer streamable is dropped too.
      resetUserQueueChecks()
      var ut = { uid: "v355u#0", title: "Not Streamable", artist: "P", album: "Persist", duration: 10, streamable: false }
      svc.collection = svc.collection.concat([synth("v355u", "Persist", "P", [ut])])
      svc.restoreQueue(JSON.stringify({ version: 1, pending: [UserQueue.identityOf(host.probe.t0), UserQueue.identityOf(ut)] }))
      check("v3.5.5: restore silently drops an entry that is no longer streamable",
        queueTitles().join("|") === "La Dee La La Song")
    },
    function() {
      // Corrupt and missing data both mean an empty queue, never an error and
      // never a broken panel.
      svc.userQueueState = { pending: [host.probe.t0], current: null, resumeIndex: -1, history: [] }
      svc.restoreQueue("{ this is not json")
      check("v3.5.5: a corrupt persisted queue restores as empty and leaves the panel working",
        svc.userQueue.length === 0 && panel.opened === true && named(stage, "upNext").visible === false)
      svc.restoreQueue("")
      check("v3.5.5: a missing persisted queue restores as empty (no error)",
        svc.userQueue.length === 0 && panel.opened === true)
    },
    function() {
      // Real corrupt file on disk (the service watches queue.json).
      svc.userQueueState = { pending: [host.probe.t0], current: null, resumeIndex: -1, history: [] }
      rawQueueFile.setText("{ definitely not json")
    },
    function() {
      svc.restoreQueue()
      check("v3.5.5: an on-disk corrupt queue.json restores as empty, panel fine",
        svc.userQueue.length === 0 && panel.opened === true)
    },
    function() {
      // Leave a real fixture queue on disk for the relaunch phase. This is the
      // last mutation: no later step may overwrite it.
      resetUserQueueChecks()
      svc.loadLibrary()
      var alb = svc.collection[collIndex("La Dee La La")]
      svc.addTrackToQueue(alb.tracks[0])
      svc.addTrackToQueue(alb.tracks[1])
      check("v3.5.5: the queue left for the relaunch phase is the fixture album's first two tracks",
        queueTitles().join("|") === "La Dee La La Song|Waiting For Marvin")
    }
  ]

  // ======================================== PHASE 2 ==========================================
  property var steps2: [
    function() { panel.open() },
    function() {
      prepLists()
      check("[relaunch] v3.5: Albums sort direction restored from disk (descending)",
        svc.sortDirection === "desc" && named(stage, "sortDirectionButton").iconText === "\uf063")
      check("[relaunch] v3.5: Playlists sort direction restored independently (descending)",
        svc.playlistSortDirection === "desc" &&
        LibraryModel.sortPlaylists(svc.playlists, "title", "desc")[0].name === "Rock & Roll Faves")
      check("[relaunch] v3.5: the restored direction reorders the relaunched Albums list",
        titlesEqual(leftTitles(), noPre(expTitle).slice().reverse()))
      // Return to the default directions so the v3.1 sort assertions below keep
      // their original meaning; the persisted direction was exercised above.
      svc.setSortDirection("asc")
      svc.setPlaylistSortDirection("asc")
    },
    function() {
      prepLists()
      check("[relaunch] sort choice restored from disk (Title A–Z)", svc.sortMode === "title" && !!button("Sort: Title A–Z"))
      check("[relaunch] Hide pre-orders restored (On)", svc.hidePreorders === true)
      check("[relaunch] v3.5.5: the persisted Up Next queue is restored, stopped",
        svc.userQueue.length === 2 && queueTitles().join("|") === "La Dee La La Song|Waiting For Marvin" &&
        svc.currentUserTrack === null && svc.isPlaying === false)
      check("[relaunch] list is Title A–Z without pre-orders", titlesEqual(leftTitles(), noPre(expTitle)))
      check("[relaunch] Albums (N) reflects the restored filter", !!button("Albums (11)"))
      openSettings()
      check("[relaunch] gear menu shows Hide pre-orders highlighted", button("Hide pre-orders").selected === true)
      key(Qt.Key_Escape)
    },
    function() { click(button("Sort: Title A–Z")) },
    function() {
      check("[relaunch] sort menu marks the restored choice", panel.menuItems[2].icon === "\uf00c" && panel.menuItems[0].icon !== "\uf00c")
      key(Qt.Key_Escape)
    },
    function() { toggleHidePreorders() },
    function() {
      check("[relaunch] filter can be turned off again", svc.hidePreorders === false && titlesEqual(leftTitles(), expTitle))
      click(button("Playlists (2)"))
    },
    function() {
      check("[relaunch] playlist sort restored from disk (Title A–Z)",
        svc.playlistSortMode === "title" && svc.sortMode === "title" && !!button("Sort: Title A–Z"))
      check("[relaunch] playlists are Title A–Z in the relaunched process",
        titlesEqual(leftTitles(), ["Postpunky?", "Rock & Roll Faves"]))
      click(sortButton())
    },
    function() {
      check("[relaunch] playlist sort menu still has exactly two options",
        panel.menuItems.map(function(m) { return m.label }).join("|") === "Recently added|Title A–Z")
      check("[relaunch] the restored playlist choice is the checked item",
        panel.menuItems[1].icon === "\uf00c" && panel.menuItems[0].icon !== "\uf00c")
      key(Qt.Key_Escape)
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
      check("[real] Collection is built from the real username and enabled in the gear menu",
        panel.bandcampUser !== "" &&
        panel.collectionUrl === "https://bandcamp.com/" + encodeURIComponent(panel.bandcampUser) &&
        panel.moreItems[3].label === "Collection" && panel.moreItems[3].enabled === true &&
        panel.moreItems[3].tooltip === panel.collectionUrl)
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
      var allTrunc = []
      var n = leftList().count
      for (var i = 0; i < Math.min(n, 700); i++) {
        var r = leftList().itemAtIndex(i)
        if (!r) continue
        var tt = named(r, "rowTitle")
        if (tt.truncated && tt.lineCount < 2) rowsBad.push(tt.text)
        if (tt.truncated) allTrunc.push(tt.text)
      }
      log("[real] truncated row titles (" + allTrunc.length + "): " + allTrunc.join(" || "))
      check("[real] across all albums no row is truncated on a single line", rowsBad.length === 0)
      check("[real] v3.3: the real-data smoke still reports 0 truncated row titles", allTrunc.length === 0)
      var detailTrunc = []
      for (var di = 0; di < svc.collection.length; di++) {
        panel.selectAlbum(svc.collection[di])
        var dt = named(stage, "detailTitle")
        if (dt && dt.truncated) detailTrunc.push(dt.text)
      }
      panel.selectedAlbumUid = ""
      log("[real] truncated detail titles (" + detailTrunc.length + "): " + detailTrunc.join(" || "))
      var bad = entityFree(allStrings(stage, []))
      check("[real] no literal HTML entity anywhere in the rendered tree", bad.length === 0)
    }
  ]

  readonly property var steps: phase === "2" ? steps2 : (phase === "real" ? stepsReal : steps1)
  property int si: 0
  // Steps that need real time (a load, a poll) set this instead of calling
  // TestCase.wait(): qWait from inside this runner aborts the QML engine.
  property double pauseUntil: 0
  Timer {
    id: runner; interval: 450; repeat: true
    onTriggered: {
      if (host.pauseUntil > Date.now()) return
      host.pauseUntil = 0
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
