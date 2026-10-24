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
      check("Play all still present (delete this check in Phase 3)", !!button("Play all"))
      check("Refresh is a labelled toolbar button with icon", !!button("Refresh") && button("Refresh").iconText !== "")
    },
    function() {
      var bs = allButtons(stage, [])
      var hs = {}, ic = {}, bd = {}
      for (var i = 0; i < bs.length; i++) { hs[Math.round(bs[i].height)] = 1; ic[bs[i].iconSize] = 1; bd[bs[i].bordered] = 1 }
      log("buttons=" + bs.length + " heights=" + Object.keys(hs) + " iconSizes=" + Object.keys(ic) + " bordered=" + Object.keys(bd) + " controlHeight=" + Style.spacing.controlHeight + " space16=" + Style.space(16))
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
