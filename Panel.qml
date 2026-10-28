import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "LibraryModel.js" as LibraryModel

// OmaTimeAtBandCamp popup.
//
// This file is the plugin's only entry point (kinds: service + bar-widget): it
// draws the bar icon and the popup anchored beneath it. Library data and
// playback state live in the service singleton, reached through `bar.shell`.
Panel {
  id: root
  moduleName: "com.github.dtotheatothevtothee.omatimeatbandcamp"
  ipcTarget: "omatimeatbandcamp.panel"

  readonly property var service: (bar && bar.shell && bar.shell.serviceFor)
    ? bar.shell.serviceFor("com.github.dtotheatothevtothee.omatimeatbandcamp") : null

  readonly property bool showIcon: {
    var v = setting("showIcon", true)
    return !(v === false || v === "false" || v === 0 || v === "0")
  }
  // v3: the bar text is plain "BC" in every playback state. The separate
  // bar-art widget is gone; backend cover art is kept for MPRIS.
  readonly property string barLabel: "BC"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // `albums` is what the Albums list shows (sorted, optionally without pre-orders).
  readonly property var albums: service ? service.albumsView : []
  readonly property var playlists: service ? service.playlists : []
  readonly property string query: service ? service.searchQuery : ""
  readonly property var searchTracks: service ? service.searchResults.tracks : []
  readonly property var searchAlbums: service ? service.searchResults.albums : []
  readonly property var searchPlaylists: service ? service.searchResults.playlists : []
  // v3.3: grouped search rows. Empty query keeps the old library/playlist list
  // (no section headers). A non-empty query renders Albums, then Playlists, then
  // Tracks, each under a header and only when that section has matches. The
  // header rows are part of the list model (so they scroll and count towards the
  // content-driven height) but are skipped by keyboard navigation.
  readonly property var searchRows: buildSearchRows()
  readonly property var currentTrack: service ? service.currentTrack : null
  readonly property bool playing: service ? service.isPlaying : false
  readonly property bool paused: service ? service.isPaused : false
  readonly property bool refreshing: service ? service.refreshing : false
  readonly property real position: service ? service.position : 0
  readonly property real duration: service ? service.duration : 0
  readonly property string playbackError: service ? service.playbackError : ""
  // v3.4: the session-only user queue shown above the context content.
  readonly property var userQueue: service ? service.userQueue : []
  readonly property int upNextCount: userQueue ? userQueue.length : 0

  readonly property string tooltip: currentTrack && currentTrack.title
    ? (currentTrack.title + (currentTrack.artist ? " — " + currentTrack.artist : ""))
    : "OmaTimeAtBandCamp"

  // Selection is kept as a uid and resolved against the live library, so it survives
  // a background sync replacing the library objects. Clicking the selected row again
  // clears it (back to the whole-library context).
  property string selectedAlbumUid: ""
  property string selectedPlaylistUid: ""
  readonly property var selectedAlbum: LibraryModel.findByUid(service ? service.collection : [], selectedAlbumUid)
  readonly property var selectedPlaylist: LibraryModel.findByUid(playlists, selectedPlaylistUid)

  // The playback/shuffle context is whatever the detail pane is showing: search
  // results, the selected playlist, the selected album, or (nothing selected) the
  // whole library. Shuffle is remembered per context.
  readonly property string contextKey: query !== "" ? "search"
    : selectedPlaylist ? "playlist:" + selectedPlaylist.id
    : selectedAlbum ? "album:" + selectedAlbum.id
    : "library"
  readonly property bool shuffleOn: service ? service.isShuffled(contextKey) : false

  // What the right pane is about.
  readonly property var detailItem: query !== "" ? null : (selectedPlaylist || selectedAlbum)
  readonly property bool detailIsAlbum: query === "" && !selectedPlaylist && !!selectedAlbum
  readonly property var detailTrackList: detailTracks()
  readonly property int detailTotal: detailTrackList.length
  readonly property int detailStreamable: {
    var n = 0
    for (var i = 0; i < detailTrackList.length; i++) if (detailTrackList[i].streamable !== false) n++
    return n
  }

  // v3: one border colour for the album list, the detail pane and the footer.
  // It is the detail pane's existing theme-accent border, now shared by all three.
  readonly property var paneBorderSpec: Border.flat(Util.alpha(Color.accent, 0.75), Style.normalBorderWidth)

  // v3.1: one control height for every named control (search field, gear,
  // Collection, Albums/Playlists/Sort and the four footer transport buttons).
  // The token is BcButton's existing height, so the buttons and the field
  // cannot drift apart.
  readonly property int controlHeight: Style.spacing.controlHeight

  // v3.2: the list/detail row is content-driven. Nothing selected keeps the
  // old fixed browsing height (the cap); a selection or search result sizes
  // itself by the detail header plus the track rows actually shown, with a
  // floor of six 30 px track rows. Long lists still stop at the cap and scroll.
  readonly property real detailCapHeight: Style.space(396)
  readonly property int detailMinTrackRows: 6
  readonly property real detailBaseTrackRowHeight: Style.space(30)
  // v3.4: Up Next rows are content like any other. They are counted in the
  // detail row height under the same floor/cap. The section shows up to six
  // rows at once (the same six-row unit as the floor) and scrolls beyond that;
  // the context's own track list keeps the remaining space.
  readonly property real upNextRowHeight: Style.space(30)
  readonly property int upNextMaxVisibleRows: detailMinTrackRows
  readonly property real upNextListHeight: upNextCount === 0 ? 0
    : Math.min(upNextCount, upNextMaxVisibleRows) * upNextRowHeight
  readonly property real upNextSectionHeight: upNextCount === 0 ? 0
    : controlHeight + Style.space(2) + upNextListHeight
  readonly property bool detailContextActive: query !== "" || !!selectedPlaylist || !!selectedAlbum
  readonly property real detailRowContentHeight: detailHeader.height + Style.spacing.sm
    + (upNextCount > 0 ? upNextSectionHeight + Style.spacing.sm : 0)
    + (trackList ? trackList.contentHeight : 0)
  // v3.3: in the grouped search state the left list contains section headers as
  // well as items. The row must be tall enough for every rendered row, not just
  // the right-hand track list, so use the taller of the two panes under the same
  // floor/cap. The left pane's 1 px inner margins are included so the last row
  // is fully visible rather than needing a 2 px scroll. The two panes still bind
  // to the one row height.
  readonly property real searchListContentHeight: query !== "" && listColumn
    ? listColumn.contentHeight + Style.space(2) : 0
  readonly property real libraryRowContentHeight: Math.max(detailRowContentHeight, searchListContentHeight)
  readonly property real libraryRowHeight: {
    if (!detailContextActive) return detailCapHeight
    var floorHeight = detailMinTrackRows * detailBaseTrackRowHeight
    return Math.max(floorHeight, Math.min(detailCapHeight, libraryRowContentHeight))
  }

  // Overflow (gear) menu and Sort menu share one card (menuKind: "", "more", "sort").
  // New gear entries go in moreItems; destructive ones must go through a ConfirmDialog.
  // Refresh and the Hide pre-orders filter live here in v3, not in the toolbar.
  property string menuKind: ""
  readonly property bool menuOpen: menuKind !== ""
  property int menuIndex: 0
  property bool logoutConfirmOpen: false
  // v3.4 row context menu. It is a separate overlay from the gear/sort menu so
  // right-clicking a row never disturbs the toolbar menus.
  property bool contextMenuOpen: false
  property string contextMenuKind: ""       // "track", "item", "queue"
  property var contextMenuTrack: null
  property var contextMenuItem: null
  property int contextMenuQueueIndex: -1
  property var contextMenuEntries: []
  property real contextMenuAnchorX: 0
  property real contextMenuAnchorY: 0
  readonly property var moreItems: [
    { icon: "\uf021", label: "Refresh library", action: "refresh", enabled: !root.refreshing, spinning: root.refreshing },
    { icon: root.service && root.service.hidePreorders ? "\uf00c" : "\u2003", label: "Hide pre-orders", action: "hide-preorders", checked: root.service ? root.service.hidePreorders : false },
    { icon: "\uf08b", label: "Log out / Clear Bandcamp session", action: "logout" }
  ]
  readonly property var sortItems: {
    var out = []
    for (var i = 0; i < LibraryModel.SORT_MODES.length; i++) {
      var m = LibraryModel.SORT_MODES[i]
      out.push({ icon: service && service.sortMode === m.id ? "\uf00c" : "\u2003", label: m.label, action: "sort:" + m.id, checked: service && service.sortMode === m.id })
    }
    return out
  }
  readonly property var menuItems: menuKind === "sort" ? sortItems : moreItems

  // v3: one Collection link remains. Its URL is built from the username the
  // backend recorded in the library, so it stays disabled until it is known.
  // Verified live on 2026-10-23 (V2-NOTES Phase 7).
  readonly property string bandcampUser: service ? String(service.detectedUser || "") : ""
  readonly property string collectionUrl: bandcampUser === ""
    ? "" : "https://bandcamp.com/" + encodeURIComponent(bandcampUser)

  // ---- keyboard (Phase 8) -------------------------------------------------
  // Panel-scoped only: no global shortcut is registered, no Hyprland binding is
  // touched. Focus is either the search field ("") or one of the two lists.
  // Down/Up from search enters the left list; Left/Right switch lists; `/`
  // returns to search; Esc keeps the Phase 2 layering.
  property string focusPane: ""       // "", "list", "tracks"
  property int listCursor: -1
  property int trackCursor: -1
  readonly property var listRows: query !== ""
    ? searchRows
    : (service && service.activeTab === 1 ? playlists : albums)

  function buildSearchRows() {
    var out = []
    if (query === "") return out
    if (searchAlbums.length > 0) {
      out.push({ rowKind: "header", section: "albums", title: "Albums (" + searchAlbums.length + ")", count: searchAlbums.length })
      for (var a = 0; a < searchAlbums.length; a++) {
        var alb = searchAlbums[a]
        out.push({ rowKind: "album", item: alb, uid: alb.uid, title: alb.title || "", name: alb.title || "" })
      }
    }
    if (searchPlaylists.length > 0) {
      out.push({ rowKind: "header", section: "playlists", title: "Playlists (" + searchPlaylists.length + ")", count: searchPlaylists.length })
      for (var p = 0; p < searchPlaylists.length; p++) {
        var pl = searchPlaylists[p]
        out.push({ rowKind: "playlist", item: pl, uid: pl.uid, title: pl.name || pl.title || "Playlist", name: pl.name || pl.title || "Playlist" })
      }
    }
    if (searchTracks.length > 0) {
      out.push({ rowKind: "header", section: "tracks", title: "Tracks (" + searchTracks.length + ")", count: searchTracks.length })
      for (var t = 0; t < searchTracks.length; t++) {
        var tr = searchTracks[t]
        out.push({ rowKind: "track", item: tr, uid: tr.uid, title: tr.title || "" })
      }
    }
    return out
  }

  function isHeaderRow(row) { return !!row && row.rowKind === "header" }

  function focusSearch() {
    focusPane = ""
    searchField.forceActiveFocus()
  }

  // v3.3.1: the header focus chain in visual order. Every member is a real
  // focus target using the shell's shared focus fill/border (TextField or
  // Button focusable:true). Tab/Shift+Tab only ever move focus; they are never
  // query text. Hidden controls (Sort on the Playlists tab) are skipped.
  readonly property var focusChain: [searchField, searchAction, collectionButton,
    menuButton, albumsButton, playlistsButton, sortButton]

  function focusChainItems() {
    var out = []
    for (var i = 0; i < focusChain.length; i++) {
      var it = focusChain[i]
      if (it && it.visible && it.enabled) out.push(it)
    }
    return out
  }

  function focusControlName() {
    var items = focusChainItems()
    for (var i = 0; i < items.length; i++) if (items[i].activeFocus) return items[i].objectName
    if (listKeyCatcher.activeFocus) return "listKeyCatcher"
    return ""
  }

  function moveFocus(step) {
    var items = focusChainItems()
    if (items.length === 0) { focusSearch(); return }
    var current = -1
    for (var i = 0; i < items.length; i++) if (items[i].activeFocus) current = i
    var next = current < 0 ? (step > 0 ? 0 : items.length - 1)
      : (current + step + items.length) % items.length
    focusPane = ""
    items[next].forceActiveFocus()
  }

  // Returns true when the event was a focus-only Tab/Shift+Tab. The caller must
  // stop here: no Tab key may reach text entry or the type-to-search branch.
  function handleTabKey(event) {
    if (event.key === Qt.Key_Backtab
        || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
      moveFocus(-1)
      event.accepted = true
      return true
    }
    if (event.key === Qt.Key_Tab) {
      moveFocus(1)
      event.accepted = true
      return true
    }
    return false
  }

  // Type-to-search accepts one genuine printable character only. Control
  // characters (Tab U+0009, newlines, DEL/C1, ...) and empty event.text are
  // never appended to the query.
  function isPrintableText(text) {
    if (!text || text.length !== 1) return false
    var c = text.charCodeAt(0)
    return c >= 0x20 && c !== 0x7f && !(c >= 0x80 && c <= 0x9f)
  }

  function clearSearch() {
    if (searchField) searchField.text = ""
    if (service) service.search("")
    listCursor = -1
  }

  function handleEscape() {
    if (logoutConfirmOpen) cancelLogout()
    else if (contextMenuOpen) closeContextMenu()
    else if (menuOpen) closeMenu()
    else if (query !== "" || (searchField && searchField.text !== "")) { clearSearch(); focusSearch() }
    else close()
  }

  // Keyboard selection never toggles: moving the cursor onto the already
  // selected row must not deselect it (clicking still toggles, Phase 4.0).
  function selectAlbum(alb) { if (!alb) return; selectedPlaylistUid = ""; selectedAlbumUid = alb.uid }
  function selectPlaylist(pl) { if (!pl) return; selectedAlbumUid = ""; selectedPlaylistUid = pl.uid }

  function clampCursor(i, n) { return Math.max(0, Math.min(n - 1, i)) }

  function enterList(delta) {
    var rows = listRows
    if (!rows.length) return
    focusPane = "list"
    if (listCursor < 0 || listCursor >= rows.length) {
      var i = -1, uid = selectedPlaylistUid || selectedAlbumUid
      for (var k = 0; k < rows.length; k++) if (!isHeaderRow(rows[k]) && rows[k].uid === uid) { i = k; break }
      if (i < 0) {
        i = delta > 0 ? 0 : rows.length - 1
        while (i >= 0 && i < rows.length && isHeaderRow(rows[i])) i += delta
      }
      listCursor = i
    } else {
      var next = listCursor + delta
      while (next >= 0 && next < rows.length && isHeaderRow(rows[next])) next += delta
      if (next >= 0 && next < rows.length) listCursor = next
    }
    if (listCursor < 0 || listCursor >= rows.length) return
    applyListCursor()
    listKeyCatcher.forceActiveFocus()
  }

  function applyListCursor() {
    var rows = listRows
    if (listCursor < 0 || listCursor >= rows.length) return
    listColumn.positionViewAtIndex(listCursor, ListView.Contain)
    if (query !== "") return                  // search results: cursor only
    if (service && service.activeTab === 1) selectPlaylist(rows[listCursor])
    else selectAlbum(rows[listCursor])
  }

  function focusTracks() {
    if (detailTrackList.length === 0) return
    focusPane = "tracks"
    if (trackCursor < 0 || trackCursor >= detailTrackList.length) {
      var i = -1
      for (var k = 0; k < detailTrackList.length; k++)
        if (currentTrack && detailTrackList[k].uid === currentTrack.uid) { i = k; break }
      trackCursor = i >= 0 ? i : 0
    }
    trackList.positionViewAtIndex(trackCursor, ListView.Contain)
    listKeyCatcher.forceActiveFocus()
  }

  function moveCursor(delta) {
    if (focusPane === "tracks") {
      if (!detailTrackList.length) return
      trackCursor = clampCursor((trackCursor < 0 ? 0 : trackCursor) + delta, detailTrackList.length)
      trackList.positionViewAtIndex(trackCursor, ListView.Contain)
      return
    }
    enterList(delta)
  }

  function switchPane(direction) {
    if (direction > 0) focusTracks()
    else if (detailTrackList.length > 0) {
      focusPane = "list"
      if (listCursor < 0 || listCursor >= listRows.length || isHeaderRow(listRows[listCursor])) {
        listCursor = -1
        for (var i = 0; i < listRows.length; i++) if (!isHeaderRow(listRows[i])) { listCursor = i; break }
      }
      applyListCursor()
      listKeyCatcher.forceActiveFocus()
    }
  }

  function activateCursor() {
    if (focusPane === "tracks") {
      var t = detailTrackList[trackCursor]
      if (!t) return
      if (t.streamable !== false) playTrackNow(t, detailTrackList)
      else if (service) service.notify(service.unavailableMessage(t))
      return
    }
    var row = listRows[listCursor]
    if (!row || isHeaderRow(row)) return
    if (query !== "") {
      if (row.rowKind === "album") { activateSearchAlbum(row.item); return }
      if (row.rowKind === "playlist") { activateSearchPlaylist(row.item); return }
      playTrackNow(row.item || row, searchTracks)
      return
    }
    if (service && service.activeTab === 1) { selectPlaylist(row); service.playPlaylist(row) }
    else { selectAlbum(row); service.playAlbum(row) }
  }

  // v3.3: activating a grouped album/playlist row is navigation, not playback.
  // Leave search, switch to the matching tab, select the named thing and show its
  // tracks — the same end state as clicking that row in the normal list.
  function activateSearchAlbum(alb) {
    if (!alb) return
    clearSearch()
    if (service) service.activeTab = 0
    selectedPlaylistUid = ""
    selectedAlbumUid = alb.uid
    focusSearch()
  }

  function activateSearchPlaylist(pl) {
    if (!pl) return
    clearSearch()
    if (service) service.activeTab = 1
    selectedAlbumUid = ""
    selectedPlaylistUid = pl.uid
    focusSearch()
  }

  function noteListClick(index) { listCursor = index; focusPane = "list"; listKeyCatcher.forceActiveFocus() }
  function noteTrackClick(index) { trackCursor = index; focusPane = "tracks"; listKeyCatcher.forceActiveFocus() }

  implicitWidth: showIcon ? barRow.implicitWidth : 0
  implicitHeight: showIcon ? barRow.implicitHeight : 0

  onOpenedChanged: {
    if (!opened) { menuKind = ""; logoutConfirmOpen = false; contextMenuOpen = false; focusPane = ""; listCursor = -1; trackCursor = -1 }
    else if (service && service.collection.length === 0) service.refresh()
  }

  onMenuKindChanged: if (menuKind !== "") placeMenu()

  function placeMenu() {
    var b = menuKind === "sort" ? sortButton : menuButton
    var p = b.mapToItem(menuLayer, 0, 0)
    var x = menuKind === "sort" ? p.x : p.x + b.width - menuCard.width
    menuCard.x = Math.max(0, Math.min(menuLayer.width - menuCard.width, x))
    menuCard.y = p.y + b.height + Style.space(4)
  }

  function closeMenu() {
    menuKind = ""
    searchField.forceActiveFocus()
  }

  // ---- v3.4 row context menu ----------------------------------------------
  function openContextMenu(kind, entries, anchorItem, x, y) {
    contextMenuKind = kind
    contextMenuEntries = entries
    contextMenuOpen = true
    var p = anchorItem.mapToItem(contextMenuLayer, x, y)
    contextMenuAnchorX = p.x
    contextMenuAnchorY = p.y
  }

  function openTrackMenu(track, anchorItem, x, y) {
    if (!service || !track) return
    contextMenuTrack = track
    contextMenuItem = null
    contextMenuQueueIndex = -1
    var playable = track.streamable !== false
    openContextMenu("track", [
      { label: "Play Next", action: "play-next", enabled: playable },
      { label: "Add to Queue", action: "queue-track", enabled: playable }
    ], anchorItem, x, y)
  }

  function openItemMenu(item, anchorItem, x, y) {
    if (!service || !item) return
    contextMenuTrack = null
    contextMenuItem = item
    contextMenuQueueIndex = -1
    openContextMenu("item", [
      { label: "Add to Queue", action: "queue-item", enabled: true }
    ], anchorItem, x, y)
  }

  function openQueueMenu(index, anchorItem, x, y) {
    if (!service) return
    contextMenuTrack = null
    contextMenuItem = null
    contextMenuQueueIndex = index
    openContextMenu("queue", [
      { label: "Remove from queue", action: "queue-remove", enabled: true }
    ], anchorItem, x, y)
  }

  function closeContextMenu() {
    contextMenuOpen = false
    contextMenuKind = ""
    contextMenuEntries = []
    contextMenuTrack = null
    contextMenuItem = null
    contextMenuQueueIndex = -1
  }

  function runContextAction(action) {
    var track = contextMenuTrack
    var item = contextMenuItem
    var index = contextMenuQueueIndex
    closeContextMenu()
    if (!service) return
    if (action === "play-next") service.playNextTrack(track)
    else if (action === "queue-track") service.addTrackToQueue(track)
    else if (action === "queue-item") service.addItemToQueue(item)
    else if (action === "queue-remove") service.removeUserQueueAt(index)
  }

  function playQueueRow(index) {
    if (service) service.startUserQueueAt(index)
  }

  function toggleMenu() {
    menuIndex = 0
    if (menuKind === "more") {
      closeMenu()
    } else {
      menuKind = "more"
      // The menu's own Up/Down/Enter handling lives on the search field (it owns
      // the window's keyboard). The gear is now a Tab stop too, so hand focus
      // back to the field when the menu opens; v3.3.1 keeps both behaviours.
      focusSearch()
    }
  }

  function toggleSortMenu() {
    menuIndex = 0
    if (menuKind === "sort") {
      closeMenu()
    } else {
      menuKind = "sort"
      focusSearch()
    }
  }

  function runMenuAction(action) {
    var kind = menuKind
    menuKind = ""
    if (action === "logout") {
      logoutConfirmOpen = true
    } else if (action === "refresh") {
      if (service && !service.refreshing) service.refresh()
      searchField.forceActiveFocus()
    } else if (action === "hide-preorders") {
      if (service) service.setHidePreorders(!service.hidePreorders)
      searchField.forceActiveFocus()
    } else if (action.indexOf("sort:") === 0) {
      if (service) service.setSortMode(action.substring(5))
      searchField.forceActiveFocus()
    }
  }

  function cancelLogout() {
    logoutConfirmOpen = false
    searchField.forceActiveFocus()
  }

  function confirmLogout() {
    logoutConfirmOpen = false
    if (service) service.clearCookies()
    searchField.forceActiveFocus()
  }

  // Clicking the selected row again deselects it; clicking another row moves the selection.
  function pickAlbum(alb) {
    if (service) service.notice = ""     // a stale "Not yet released" must not follow you to another album
    selectedPlaylistUid = ""
    selectedAlbumUid = selectedAlbumUid === alb.uid ? "" : alb.uid
  }

  function pickPlaylist(pl) {
    if (service) service.notice = ""
    selectedAlbumUid = ""
    selectedPlaylistUid = selectedPlaylistUid === pl.uid ? "" : pl.uid
  }

  function playTrackNow(track, list) {
    if (!service) return
    var tracks = list || [track]
    service.playContext("list", detailTitle(), tracks, service.indexOfTrack(tracks, track), contextKey)
  }

  // Footer Play with nothing loaded, and the detail pane's Play button: play the
  // current context from its start (shuffled if that context's Shuffle is On).
  function playContextNow() {
    if (!service) return
    if (query !== "") {
      if (searchTracks.length > 0) service.playContext("search", "Search results", searchTracks, undefined, "search")
    } else if (selectedPlaylist) {
      service.playPlaylist(selectedPlaylist)
    } else if (selectedAlbum) {
      service.playAlbum(selectedAlbum)
    } else {
      service.playLibrary()
    }
  }

  // Progress shown in the footer: the drag preview while dragging, the player otherwise.
  function shownProgress() {
    var r = seekMouse.preview >= 0 ? seekMouse.preview : (service ? service.progress : 0)
    return Math.max(0, Math.min(1, r))
  }

  function shownSeconds() {
    if (seekMouse.preview >= 0) return seekMouse.preview * root.duration
    return root.position
  }

  function fmtTime(sec) { return LibraryModel.fmtClock(sec) }

  function detailTracks() {
    if (query !== "") return searchTracks
    if (selectedPlaylist) return service ? service.tracksFor(selectedPlaylist) : []
    if (selectedAlbum) return service ? service.tracksFor(selectedAlbum) : []
    return []
  }

  function detailTitle() {
    if (query !== "") return "Search results"
    if (selectedPlaylist) return selectedPlaylist.name || selectedPlaylist.title || "Playlist"
    if (selectedAlbum) return selectedAlbum.title || ""
    return "Pick an album or playlist"
  }

  function detailSubtitle() {
    if (query !== "") return searchTracks.length + (searchTracks.length === 1 ? " track" : " tracks")
    if (selectedPlaylist) return detailTotal + (detailTotal === 1 ? " track" : " tracks")
    if (selectedAlbum) return selectedAlbum.artist || ""
    return ""
  }

  function preorderLine() {
    if (!detailIsAlbum || !selectedAlbum.isPreorder) return ""
    var d = LibraryModel.fmtDate(selectedAlbum.releaseTs)
    return "PRE-ORDER" + (d ? " · releases " + d : "")
  }

  function availabilityLine() {
    if (!detailItem || query !== "") return ""
    if (detailIsAlbum && !selectedAlbum.tracksLoaded) return ""
    if (detailStreamable < detailTotal || (detailIsAlbum && selectedAlbum.isPreorder)) {
      var line = detailStreamable + " of " + detailTotal + " tracks available"
      // v3: the old detail-pane "Play available" button is gone. Preserve the
      // information in the availability line for partially released contexts.
      if (detailStreamable > 0 && detailStreamable < detailTotal) line += " · Play available"
      return line
    }
    return ""
  }

  function partialLine() {
    if (!detailIsAlbum || !selectedAlbum.tracksLoaded) return ""
    var declared = selectedAlbum.declaredCount
    return declared > detailTotal && detailTotal > 0
      ? "Showing " + detailTotal + " of " + declared + " tracks (the source returned fewer)" : ""
  }

  function emptyLine() {
    if (query !== "") {
      if (searchAlbums.length + searchPlaylists.length + searchTracks.length === 0) return "No results"
      if (searchTracks.length === 0) return "No matching tracks"
      return ""
    }
    if (!detailItem || detailTotal > 0) return ""
    if (detailIsAlbum && !selectedAlbum.tracksLoaded) return "Tracks are still loading — the library is syncing"
    return "No tracks in this " + (detailIsAlbum ? "album" : "playlist")
  }

  // ---- bar icon -----------------------------------------------------------
  // The BC click target of record. v3 removed the companion art widget and the
  // play/pause suffix, so the bar always reads plain BC; cover art is still
  // cached for MPRIS.
  Row {
    id: barRow
    visible: root.showIcon

    WidgetButton {
      id: button
      objectName: "barButton"
      bar: root.bar
      text: root.barLabel
      fontFamily: root.fontFamily
      fixedWidth: -1
      tooltipText: root.tooltip
      onPressed: function(b) {
        if (!root.service) return
        if (b === Qt.RightButton) root.service.togglePlay()
        else if (b === Qt.MiddleButton) root.service.next()
        else root.toggle()             // left: open/close the window
      }
    }
  }

  // ---- popup --------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(835))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(660))

    Column {
      id: contentColumn
      anchors.fill: parent
      // v3 compact pass: sections sit a little closer together. Wrapping and
      // the 660 px popup cap are unchanged.
      spacing: Style.spacing.sm

      // header ---------------------------------------------------------------
      // v3.1: the title is the only thing in this row. The gear moved down to
      // the search row, and the title is one step larger (about +2 pt).
      Item {
        id: headerRow
        objectName: "headerRow"
        width: parent.width
        height: root.controlHeight

        Text {
          objectName: "headerTitle"
          textFormat: Text.PlainText
          text: "OmaTimeAtBandCamp"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle + 2
          font.bold: true
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // search ---------------------------------------------------------------
      // v3.1, left to right: the flexible search field (the magnifier now sits
      // inside its right end), Collection, then the gear/settings button.
      Item {
        width: parent.width
        height: root.controlHeight

        Row {
          id: searchRow
          objectName: "searchRow"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: root.controlHeight
          spacing: Style.spacing.sm

          TextField {
            id: searchField
            objectName: "searchField"
            // v3.2: the field takes every pixel left after Collection and the
            // gear (and the two Row gaps). No half-row rule.
            width: Math.max(0, searchRow.width - collectionButton.width
              - menuButton.width - 2 * searchRow.spacing)
            height: root.controlHeight
            // A little less vertical padding than the stock 30 px field: the
            // text still fits (asserted by the harness) at the shared 28 px.
            verticalPadding: Style.spacing.sm
            // Leave room inside the right edge for the clear/magnifier control.
            rightPadding: horizontalPadding + root.controlHeight + Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Search albums, playlists, tracks…"
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: {
              if (root.service) root.service.search(text)
              root.listCursor = -1
            }

            // v3.3.1: the right-end icon is a real control in the focus chain.
            // Empty field: magnifier, click focuses (as before). With text: a ×
            // with tooltip "Clear search"; click (or Enter/Space when focused)
            // clears and returns focus to the field. Same icon font/size and
            // shared focus fill/border as every other BcButton.
            BcButton {
              id: searchAction
              objectName: "searchAction"
              text: ""
              iconText: searchField.text !== "" ? "\uf00d" : "\uf002"
              iconSize: Style.space(16)
              height: root.controlHeight
              width: height
              bordered: false
              focusable: true
              tooltipText: searchField.text !== "" ? "Clear search" : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.right: parent.right
              anchors.rightMargin: 0
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                if (searchField.text !== "") root.clearSearch()
                root.focusSearch()
              }
              Keys.onPressed: function(event) { root.handleTabKey(event) }
              Keys.onEscapePressed: function(event) { root.handleEscape(); event.accepted = true }
            }

            // The search field owns keyboard focus for the whole window, so the
            // overlays are handled here, before its own text entry. While the
            // logout confirmation or the menu is open it owns the keyboard.
            // (Qt fires Keys.onEscapePressed before Keys.onPressed, so Esc is
            // handled in its own handler below.)
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              // v3.3.1: Tab/Shift+Tab are ALWAYS focus movement, in every state,
              // so they can never reach text entry as a U+0009 character.
              if (root.handleTabKey(event)) return
              if (root.logoutConfirmOpen) {
                logoutConfirm.handleKey(event)
                event.accepted = true
              } else if (root.menuOpen) {
                if (event.key === Qt.Key_Down) root.menuIndex = Math.min(root.menuItems.length - 1, root.menuIndex + 1)
                else if (event.key === Qt.Key_Up) root.menuIndex = Math.max(0, root.menuIndex - 1)
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.runMenuAction(root.menuItems[root.menuIndex].action)
                event.accepted = true
              } else if (root.contextMenuOpen) {
                // The row context menu is mouse-driven; keep keys from acting
                // underneath it. Esc closes it through handleEscape().
                event.accepted = true
              } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                // Down/Up leave text entry and move through the focused list.
                root.enterList(event.key === Qt.Key_Down ? 1 : -1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Enter plays whatever is selected (no-op when nothing is).
                if (root.listRows.length > 0 && root.listCursor >= 0) { root.activateCursor(); event.accepted = true }
              }
            }
            // Esc backs out one layer at a time: confirmation, menu, search text, window.
            Keys.onEscapePressed: function(event) {
              root.handleEscape()
              event.accepted = true
            }
          }

          BcButton {
            id: collectionButton
            objectName: "link-collection"
            text: "Collection"
            height: root.controlHeight
            enabled: root.collectionUrl !== ""
            focusable: true
            tooltipText: root.collectionUrl !== "" ? root.collectionUrl : "Username not known yet"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: if (root.service) root.service.openExternal(root.collectionUrl)
            Keys.onPressed: function(event) { root.handleTabKey(event) }
            Keys.onEscapePressed: function(event) { root.handleEscape(); event.accepted = true }
          }

          // v3.1: the gear/settings button now lives in the search row. Its menu
          // entries and behaviour are unchanged.
          BcButton {
            id: menuButton
            objectName: "settingsButton"
            iconText: "\uf013"
            height: root.controlHeight
            tooltipText: "Settings"
            active: root.menuOpen
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.toggleMenu()
            Keys.onPressed: function(event) { root.handleTabKey(event) }
            Keys.onEscapePressed: function(event) { root.handleEscape(); event.accepted = true }
          }
        }
      }

      // toolbar --------------------------------------------------------------
      Item {
        width: parent.width
        height: root.controlHeight

        Row {
          id: toolbarLeft
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          BcButton {
            id: albumsButton
            objectName: "albumsButton"
            text: "Albums (" + root.albums.length + ")"
            height: root.controlHeight
            selected: (root.service ? root.service.activeTab : 0) === 0
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.activeTab = 0
            Keys.onPressed: function(event) { root.handleTabKey(event) }
            Keys.onEscapePressed: function(event) { root.handleEscape(); event.accepted = true }
          }

          BcButton {
            id: playlistsButton
            objectName: "playlistsButton"
            text: "Playlists (" + root.playlists.length + ")"
            height: root.controlHeight
            selected: (root.service ? root.service.activeTab : 0) === 1
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.activeTab = 1
            Keys.onPressed: function(event) { root.handleTabKey(event) }
            Keys.onEscapePressed: function(event) { root.handleEscape(); event.accepted = true }
          }

          // Sorting applies to the Albums list only. Shuffle moved to the
          // footer transport in v3; Refresh/Hide pre-orders moved to the gear menu.
          BcButton {
            id: sortButton
            objectName: "sortButton"
            visible: !root.service || root.service.activeTab === 0
            height: root.controlHeight
            text: "Sort: " + LibraryModel.sortLabel(root.service ? root.service.sortMode : "added")
            iconText: "\uf0d7"
            active: root.menuKind === "sort"
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleSortMenu()
            Keys.onPressed: function(event) { root.handleTabKey(event) }
            Keys.onEscapePressed: function(event) { root.handleEscape(); event.accepted = true }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Text {
            visible: root.service && root.service.status !== ""
            text: root.service ? root.service.status : ""
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: Math.min(implicitWidth, Math.max(0, contentColumn.width - toolbarLeft.width - Style.spacing.md * 2))
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // library + detail -----------------------------------------------------
      // v3.2: the row height is content-driven (see libraryRowHeight). Both
      // panes are always exactly this tall, so their bottom edges coincide.
      Row {
        id: libraryRow
        objectName: "libraryRow"
        width: parent.width
        height: root.libraryRowHeight
        spacing: Style.spacing.md

        BorderSurface {
          id: leftPane
          objectName: "leftPane"
          // v3.2: keep list/detail proportions close to the old 38/62, while
          // giving the narrower list enough width that no title truncates
          // that fitted at the v3.1 width (verified against the real library).
          width: parent.width * 0.422
          height: parent.height
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: root.paneBorderSpec

          Item {
            anchors.fill: parent
            anchors.margins: Style.space(1)

          ListView {
            id: listColumn
            objectName: "leftList"
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.listRows

            // v3.3: search rows are grouped by section. Header rows are small,
            // non-interactive labels with the section count; item rows keep the
            // existing two-line treatment. Empty-query rows are unchanged.
            delegate: Item {
              id: rowItem
              width: listColumn.width
              height: rowItem.isHeader
                ? sectionHeader.implicitHeight + Style.space(6)
                : rowCol.implicitHeight + Style.space(10)

              readonly property var raw: modelData
              readonly property bool isSearch: root.query !== ""
              readonly property bool isHeader: isSearch && !!raw && raw.rowKind === "header"
              readonly property bool isPlaylist: !isSearch && root.service && root.service.activeTab === 1
              readonly property var item: (isSearch && raw && raw.item !== undefined) ? raw.item : raw
              readonly property string rowKind: isSearch && raw ? (raw.rowKind || "track") : (isPlaylist ? "playlist" : "album")
              readonly property bool selected: !!item && !isSearch
                && (isPlaylist ? root.selectedPlaylistUid === item.uid : root.selectedAlbumUid === item.uid)
              readonly property bool cursor: root.focusPane === "list" && index === root.listCursor
              readonly property bool preorder: !!item && !isSearch && !isPlaylist && item.isPreorder === true

              Text {
                id: sectionHeader
                objectName: "sectionHeader"
                visible: rowItem.isHeader
                textFormat: Text.PlainText
                x: Style.space(11)
                width: parent.width - Style.space(19)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignLeft
                LayoutMirroring.enabled: false
                elide: Text.ElideRight
                text: rowItem.isHeader && rowItem.raw ? (rowItem.raw.title || "") : ""
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Rectangle {
                objectName: "rowFill"
                visible: !rowItem.isHeader
                anchors.fill: parent
                radius: Style.cornerRadius
                color: rowItem.selected ? Util.alpha(Color.accent, 0.22)
                  : (rowItem.cursor ? Util.alpha(Color.accent, 0.12)
                    : (mouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"))
              }

              Rectangle {
                objectName: "rowBar"
                visible: rowItem.selected
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: Style.space(3)
                anchors.bottomMargin: Style.space(3)
                width: Style.space(3)
                radius: width / 2
                color: Color.accent
              }

              Column {
                id: rowCol
                visible: !rowItem.isHeader
                x: Style.space(11)
                width: parent.width - Style.space(19)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  objectName: "rowTitle"
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: rowItem.selected
                  text: rowItem.isHeader ? "" : (rowItem.item
                    ? (rowItem.rowKind === "playlist" ? (rowItem.item.name || rowItem.item.title || "Playlist") : (rowItem.item.title || ""))
                    : "")
                }

                Text {
                  objectName: "rowSub"
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  text: {
                    if (rowItem.isHeader) return ""
                    var it = rowItem.item
                    if (!it) return ""
                    if (rowItem.isSearch) {
                      if (rowItem.rowKind === "album") return it.artist || ""
                      if (rowItem.rowKind === "playlist") {
                        var n = it.totalCount !== undefined ? it.totalCount : (it.tracks ? it.tracks.length : 0)
                        return n + (n === 1 ? " track" : " tracks")
                      }
                      return (it.artist || "") + (it.album ? "  ·  " + it.album : "")
                    }
                    if (rowItem.isPlaylist) return it.totalCount + (it.totalCount === 1 ? " track" : " tracks")
                    return it.artist || ""
                  }
                }

                Row {
                  objectName: "rowPill"
                  visible: rowItem.preorder
                  spacing: Style.space(6)

                  BorderSurface {
                    height: Style.space(16)
                    width: pillText.implicitWidth + Style.space(10)
                    radius: Style.space(3)
                    color: Util.alpha(Color.accent, 0.18)
                    borderSpec: Border.flat(Color.accent, 1)

                    Text {
                      id: pillText
                      objectName: "pillText"
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      horizontalAlignment: Text.AlignLeft
                      LayoutMirroring.enabled: false
                      text: "PRE-ORDER"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    objectName: "pillDate"
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    LayoutMirroring.enabled: false
                    visible: text !== ""
                    text: rowItem.item && rowItem.item.releaseTs ? LibraryModel.fmtDate(rowItem.item.releaseTs) : ""
                    color: Qt.darker(root.foreground, 1.3)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                enabled: !rowItem.isHeader
                hoverEnabled: !rowItem.isHeader
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: rowItem.isHeader ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: function(ev) {
                  // v3: a single click only selects. Search rows wait for a
                  // double-click before acting: tracks play, album/playlist rows
                  // navigate to their normal tab. Right-click opens the v3.4
                  // queue menu for the row without changing the selection.
                  var it = rowItem.item
                  if (!it || rowItem.isHeader) return
                  if (ev.button === Qt.RightButton) {
                    if (rowItem.isSearch && rowItem.rowKind === "track") root.openTrackMenu(it, mouse, ev.x, ev.y)
                    else root.openItemMenu(it, mouse, ev.x, ev.y)
                    return
                  }
                  root.noteListClick(index)
                  if (rowItem.isSearch) return
                  if (rowItem.isPlaylist) root.pickPlaylist(it)
                  else root.pickAlbum(it)
                }
                onDoubleClicked: function(ev) {
                  if (ev.button !== Qt.LeftButton) return
                  var it = rowItem.item
                  if (!it || rowItem.isHeader || !rowItem.isSearch) return
                  root.noteListClick(index)
                  if (rowItem.rowKind === "album") root.activateSearchAlbum(it)
                  else if (rowItem.rowKind === "playlist") root.activateSearchPlaylist(it)
                  else root.playTrackNow(it, root.searchTracks)
                }
              }
            }
          }

          Text {
            objectName: "leftEmpty"
            anchors.centerIn: parent
            width: parent.width - Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            LayoutMirroring.enabled: false
            wrapMode: Text.Wrap
            visible: listColumn.count === 0
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: root.query !== "" ? "No results"
              : (root.service && root.service.activeTab === 1 ? "No playlists yet"
                : (root.service && root.service.hidePreorders && root.service.collection.length > 0 ? "Only pre-orders here — turn off Hide pre-orders"
                  : "No library yet — press Refresh"))
          }
          }
        }

        BorderSurface {
          objectName: "detailPane"
          width: parent.width - leftPane.width - Style.spacing.md
          height: parent.height
          radius: Style.cornerRadius
          color: "transparent"
          // v3: same shared border as the album list and the footer.
          borderSpec: root.paneBorderSpec

          Column {
            id: detailColumn
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            spacing: Style.spacing.sm

            // v3.4: Up Next sits ABOVE the context's own header/content. It is
            // the session-only user queue, in added order. Rows select nothing:
            // double-click plays a row immediately (dropping it and everything
            // ahead); right-click removes it. Clear only empties the queue.
            Item {
              id: upNextSection
              objectName: "upNext"
              visible: root.upNextCount > 0
              width: parent.width
              height: root.upNextSectionHeight

              Column {
                anchors.fill: parent
                spacing: Style.space(2)

                Item {
                  id: upNextHeaderRow
                  width: parent.width
                  height: root.controlHeight

                  Text {
                    id: upNextHeader
                    objectName: "upNextHeader"
                    textFormat: Text.PlainText
                    text: "Up Next (" + root.upNextCount + ")"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    LayoutMirroring.enabled: false
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  BcButton {
                    id: upNextClear
                    objectName: "upNextClear"
                    text: "Clear"
                    height: root.controlHeight
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    tooltipText: "Clear the queue"
                    onClicked: if (root.service) root.service.clearUserQueue()
                  }
                }

                ListView {
                  id: upNextList
                  objectName: "upNextList"
                  width: parent.width
                  height: root.upNextListHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  model: root.userQueue
                  delegate: Item {
                    id: upNextRow
                    width: ListView.view.width
                    height: root.upNextRowHeight

                    readonly property var track: modelData

                    Rectangle {
                      objectName: "upNextFill"
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: upNextMouse.containsMouse
                        ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                    }

                    Column {
                      x: Style.space(8)
                      width: parent.width - Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0

                      Text {
                        objectName: "upNextTitle"
                        textFormat: Text.PlainText
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                        LayoutMirroring.enabled: false
                        elide: Text.ElideRight
                        text: upNextRow.track ? (upNextRow.track.title || "") : ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        objectName: "upNextSub"
                        textFormat: Text.PlainText
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                        LayoutMirroring.enabled: false
                        elide: Text.ElideRight
                        text: upNextRow.track
                          ? (upNextRow.track.artist || "")
                            + (upNextRow.track.album ? " · " + upNextRow.track.album : "")
                          : ""
                        color: Qt.darker(root.foreground, 1.5)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: upNextMouse
                      objectName: "upNextMouse"
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      cursorShape: Qt.PointingHandCursor
                      onDoubleClicked: root.playQueueRow(index)
                      onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                          root.openQueueMenu(index, upNextRow, mouse.x, mouse.y)
                      }
                    }
                  }
                }
              }
            }

            // Header: same two-line treatment as the rows (title wraps, artist or count
            // on its own dimmed line), plus pre-order state and track availability.
            // v3: no Play button here; playback starts from a double-click, Enter or
            // the footer. "Play available" is carried by the availability line.
            Item {
              id: detailHeader
              width: parent.width
              height: headerCol.implicitHeight

              Column {
                id: headerCol
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(2)

                Text {
                  objectName: "detailTitle"
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  text: root.detailTitle()
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  objectName: "detailSub"
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  visible: text !== ""
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  text: root.detailSubtitle()
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  objectName: "detailPreorder"
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  visible: text !== ""
                  wrapMode: Text.Wrap
                  text: root.preorderLine()
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  objectName: "detailAvail"
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  visible: text !== ""
                  wrapMode: Text.Wrap
                  text: root.availabilityLine()
                  color: Qt.darker(root.foreground, 1.2)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  objectName: "detailPartial"
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  visible: text !== ""
                  wrapMode: Text.Wrap
                  text: root.partialLine()
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Item {
              width: parent.width
              height: Math.max(0, parent.height - detailHeader.height - root.upNextSectionHeight
                - (root.upNextCount > 0 ? 2 : 1) * parent.spacing)

              ListView {
                id: trackList
                objectName: "trackList"
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.detailTrackList

                // Track titles wrap. Tracks that cannot be streamed (unreleased) are dimmed,
                // have no hover and show "—" instead of a duration. v3: a single click only
                // selects; a double-click starts playback at that track. Unreleased tracks
                // cannot start playback by any gesture.
                delegate: Item {
                  id: trackRow
                  width: ListView.view.width
                  height: Math.max(Style.space(30), trackTitle.implicitHeight + Style.space(10))

                  readonly property var track: modelData
                  readonly property bool playable: !!track && track.streamable !== false
                  readonly property bool current: !!track && !!track.uid && !!root.currentTrack && root.currentTrack.uid === track.uid
                  readonly property bool cursor: root.focusPane === "tracks" && index === root.trackCursor
                  opacity: playable ? 1.0 : 0.45

                  Rectangle {
                    objectName: "trackFill"
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: trackRow.current ? Util.alpha(Color.accent, 0.22)
                      : (trackRow.cursor ? Util.alpha(Color.accent, 0.12)
                        : (trackRow.playable && tMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"))
                  }

                  Rectangle {
                    objectName: "trackBar"
                    visible: trackRow.current
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Style.space(3)
                    anchors.bottomMargin: Style.space(3)
                    width: Style.space(3)
                    radius: width / 2
                    color: Color.accent
                  }

                  Text {
                    objectName: "playingIndicator"
                    textFormat: Text.PlainText
                    visible: trackRow.current
                    x: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf04b"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    objectName: "trackNum"
                    textFormat: Text.PlainText
                    x: Style.space(22)
                    width: Style.space(26)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    LayoutMirroring.enabled: false
                    text: trackRow.track && trackRow.track.track_num ? trackRow.track.track_num + "." : ""
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: trackTitle
                    objectName: "trackTitle"
                    textFormat: Text.PlainText
                    x: Style.space(50)
                    width: parent.width - Style.space(50) - Style.space(58)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    LayoutMirroring.enabled: false
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: trackRow.track ? (trackRow.track.title || "") : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: trackRow.current
                  }

                  Text {
                    objectName: "trackDuration"
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    LayoutMirroring.enabled: false
                    text: trackRow.playable ? LibraryModel.fmtDuration(trackRow.track ? trackRow.track.duration : 0) : "—"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: tMouse
                    objectName: "trackMouse"
                    anchors.fill: parent
                    hoverEnabled: trackRow.playable
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: trackRow.playable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: function(mouse) {
                      if (!trackRow.track) return
                      if (mouse.button === Qt.RightButton) {
                        // Unstreamable rows still open the menu, with both
                        // queue actions disabled.
                        root.openTrackMenu(trackRow.track, tMouse, mouse.x, mouse.y)
                        return
                      }
                      // Selection only. Audio starts on double-click (or Enter/footer).
                      root.noteTrackClick(index)
                      if (!trackRow.playable && root.service) root.service.notify(root.service.unavailableMessage(trackRow.track))
                    }
                    onDoubleClicked: {
                      if (!trackRow.track) return
                      root.noteTrackClick(index)
                      if (trackRow.playable) root.playTrackNow(trackRow.track, root.detailTrackList)
                      else if (root.service) root.service.notify(root.service.unavailableMessage(trackRow.track))
                    }
                  }
                }
              }

              Text {
                objectName: "detailEmpty"
                anchors.centerIn: parent
                width: parent.width - Style.space(24)
                horizontalAlignment: Text.AlignHCenter
                LayoutMirroring.enabled: false
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.emptyLine()
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              // Short-lived message (e.g. "Not yet released"); floats so nothing shifts.
              BorderSurface {
                objectName: "noticePill"
                visible: !!root.service && root.service.notice !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(8)
                width: noticeText.implicitWidth + Style.space(24)
                height: noticeText.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: Color.popups.background
                borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)

                Text {
                  id: noticeText
                  objectName: "noticeText"
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  horizontalAlignment: Text.AlignLeft
                  LayoutMirroring.enabled: false
                  text: root.service ? root.service.notice : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }

      // now playing ----------------------------------------------------------
      // Two-line now-playing text on the left; transport (Shuffle, Prev, Play/Pause,
      // Next) right-justified. Identical BcButton style, no Stop button. A seekable
      // progress bar with elapsed/total labels. A failed stream replaces the
      // Artist · Album line with a visible error notice.
      BorderSurface {
        id: footer
        objectName: "footer"
        width: parent.width
        // v3.1: the blank band between the now-playing text and the progress
        // bar is halved. The footer's v3 inner height (84 - 2*5) left
        // 54 - nowPlaying.height between them; half of that is used here, so
        // the popup is shorter by the saving in every now-playing state and
        // the two-line case still has positive space (nothing is clipped).
        readonly property real footerGap: Math.max(0,
          (Style.space(54) - nowPlaying.implicitHeight) / 2)
        // v3.2: stopped/idle hides the progress row and drops the gap that was
        // measured from it. Playing/paused keep exactly the v3.1 layout. The
        // error line lives in nowPlaying, so an idle error still renders even
        // though the bar is gone.
        readonly property bool showProgress: root.playing || root.paused
        height: Math.round(Style.space(5) + Math.max(nowPlaying.implicitHeight, transportRow.height)
          + (showProgress ? footerGap + progressRow.height : 0) + Style.space(5))
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, Color.accent)
        // v3: the album list, detail pane and footer share one border colour.
        borderSpec: root.paneBorderSpec

        Item {
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.md
          anchors.rightMargin: Style.spacing.md
          anchors.topMargin: Style.space(5)
          anchors.bottomMargin: Style.space(5)

          Column {
            id: nowPlaying
            anchors.left: parent.left
            anchors.top: parent.top
            width: Math.max(0, transportRow.x - Style.spacing.md)
            spacing: Style.space(2)

            Text {
              objectName: "footerTitle"
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              LayoutMirroring.enabled: false
              text: root.currentTrack ? (root.currentTrack.title || "") : "Nothing playing"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              width: parent.width
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              objectName: "footerSub"
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              LayoutMirroring.enabled: false
              visible: root.playbackError === ""
              text: root.currentTrack
                ? ((root.currentTrack.artist || "") + (root.currentTrack.album ? "  ·  " + root.currentTrack.album : ""))
                : ""
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              objectName: "footerError"
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              LayoutMirroring.enabled: false
              visible: root.playbackError !== ""
              text: root.playbackError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Row {
            id: transportRow
            objectName: "transportRow"
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.spacing.sm

            // Per-context shuffle moved here from the toolbar in v3. Same state
            // model as v2; highlighted while the current context is On.
            BcButton {
              id: footerShuffle
              objectName: "footerShuffle"
              iconText: "\uf074"
              height: root.controlHeight
              tooltipText: "Shuffle: " + (root.shuffleOn ? "On" : "Off")
              selected: root.shuffleOn
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.toggleShuffle(root.contextKey)

              // v3.1: a tiny dot centred under the glyph marks this context's
              // Shuffle as On. It lives in the button's bottom padding, so the
              // button's height/layout never change.
              Rectangle {
                objectName: "shuffleDot"
                visible: root.shuffleOn
                width: Style.space(4)
                height: width
                radius: width / 2
                color: Color.accent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
              }
            }

            // Nerd Font glyphs (PUA range) so the icons stay monochrome and
            // inherit the theme — Unicode media symbols such as U+23F8 fall
            // back to colour-emoji presentation and paint their own background.
            BcButton {
              objectName: "footerPrev"
              iconText: "\uf048"
              height: root.controlHeight
              tooltipText: "Previous"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.prev()
            }

            // One button: Play when idle/paused, Pause while playing. The Stop button is
            // gone (mpv needs no stop to release a stream; loading replaces it).
            BcButton {
              id: footerPlay
              objectName: "footerPlay"
              iconText: root.playing && !root.paused ? "\uf04c" : "\uf04b"
              height: root.controlHeight
              tooltipText: root.playing && !root.paused ? "Pause" : "Play"
              active: root.playing && !root.paused
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (!root.service) return
                if (root.service.currentTrack) root.service.togglePlay()
                else root.playContextNow()
              }
            }

            BcButton {
              objectName: "footerNext"
              iconText: "\uf051"
              height: root.controlHeight
              tooltipText: "Next"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.next()
            }
          }

          Item {
            id: progressRow
            objectName: "progressRow"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.space(20)
            visible: footer.showProgress

            Text {
              id: elapsedLabel
              objectName: "elapsedLabel"
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignLeft
              LayoutMirroring.enabled: false
              text: root.fmtTime(root.shownSeconds())
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              id: totalLabel
              objectName: "totalLabel"
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              LayoutMirroring.enabled: false
              text: root.fmtTime(root.duration)
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item {
              id: seekArea
              objectName: "seekArea"
              anchors.left: elapsedLabel.right
              anchors.right: totalLabel.left
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height

              Rectangle {
                id: progressTrack
                objectName: "progressTrack"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                color: Util.alpha(root.foreground, 0.25)
              }

              Rectangle {
                id: progressFill
                objectName: "progressFill"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: progressTrack.width * root.shownProgress()
                height: progressTrack.height
                radius: progressTrack.radius
                color: Color.accent
              }

              Rectangle {
                id: seekHandle
                objectName: "seekHandle"
                visible: root.duration > 0
                width: Style.space(10)
                height: width
                radius: width / 2
                color: Color.accent
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(progressTrack.width - width, progressTrack.width * root.shownProgress() - width / 2))
              }

              // Click to seek, drag to scrub: the fill follows the pointer while the
              // button is down and the seek is sent on release.
              MouseArea {
                id: seekMouse
                objectName: "seekMouse"
                anchors.fill: parent
                enabled: root.duration > 0
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                property real preview: -1
                function ratioAt(x) { return width > 0 ? Math.max(0, Math.min(1, x / width)) : 0 }
                onPressed: function(mouse) { preview = ratioAt(mouse.x) }
                onPositionChanged: function(mouse) { if (pressed) preview = ratioAt(mouse.x) }
                onReleased: function(mouse) {
                  var r = ratioAt(mouse.x)
                  preview = -1
                  if (root.service) root.service.seekTo(r * root.duration)
                }
                onCanceled: preview = -1
              }
            }
          }
        }
      }
    }

    // Panel-scoped key catcher for the two lists. It only has focus after the
    // user enters a list (Down/Up or a row click); it registers nothing global.
    Item {
      id: listKeyCatcher
      objectName: "listKeyCatcher"
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        // v3.3.1: Tab/Shift+Tab move focus out of the lists. Handled before the
        // type-to-search branch so U+0009 can never become query text.
        if (root.handleTabKey(event)) return
        if (event.key === Qt.Key_Escape) {
          root.handleEscape(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
          root.moveCursor(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Left) { root.switchPane(-1); event.accepted = true; return }
        if (event.key === Qt.Key_Right) { root.switchPane(1); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateCursor(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Space) {
          // Only reached when the search field does NOT have focus, so Space
          // never steals a space from a search query.
          if (root.service) root.service.togglePlay()
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Slash || event.text === "/") { root.focusSearch(); event.accepted = true; return }
        // Typing while a list is focused returns to search and keeps the character.
        // v3.3.1: only a genuine printable character qualifies; navigation and
        // control keys carry empty or control-character event.text and must never
        // be appended to the query (the Tab/Down/Tab blanking bug).
        if (root.isPrintableText(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
          root.focusSearch()
          searchField.text = searchField.text + event.text
          searchField.cursorPosition = searchField.text.length
          event.accepted = true
        }
      }
    }

    // v3.4 row context menu (Play Next / Add to Queue / Remove from queue).
    // Separate from the gear/sort card so right-click never moves the toolbar
    // menu. Clamped inside the window; click-outside closes it.
    Item {
      id: contextMenuLayer
      anchors.fill: parent
      visible: root.contextMenuOpen
      z: 60

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeContextMenu()
      }

      BorderSurface {
        id: contextMenuCard
        objectName: "contextMenu"
        width: Style.space(240)
        height: contextMenuColumn.implicitHeight + contentTopInset + contentBottomInset
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.flat(Color.popups.border, Style.normalBorderWidth)
        padding: Style.space(6)
        x: Math.max(0, Math.min(contextMenuLayer.width - width, root.contextMenuAnchorX))
        y: Math.max(0, Math.min(contextMenuLayer.height - height, root.contextMenuAnchorY))

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: contextMenuColumn
          anchors.fill: parent
          anchors.topMargin: contextMenuCard.contentTopInset
          anchors.rightMargin: contextMenuCard.contentRightInset
          anchors.bottomMargin: contextMenuCard.contentBottomInset
          anchors.leftMargin: contextMenuCard.contentLeftInset
          spacing: Style.spacing.sm

          Repeater {
            model: root.contextMenuEntries

            BcButton {
              required property int index
              required property var modelData
              objectName: "contextMenuButton"
              width: contextMenuColumn.width
              leftAlign: true
              text: modelData.label
              iconText: "\u2003"
              enabled: modelData.enabled !== false
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.runContextAction(modelData.action)
            }
          }
        }
      }
    }

    // Menu card (⋯ overflow menu and Sort menu) ------------------------------------
    // Click anywhere outside the card closes the menu (the window itself stays open);
    // the card sits just under the button that opened it.
    Item {
      id: menuLayer
      anchors.fill: parent
      visible: root.menuOpen
      z: 50

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeMenu()
      }

      BorderSurface {
        id: menuCard
        objectName: "menuCard"
        width: Math.min(root.menuKind === "sort" ? Style.space(220) : Style.space(300), parent.width)
        height: menuColumn.implicitHeight + contentTopInset + contentBottomInset
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.flat(Color.popups.border, Style.normalBorderWidth)
        padding: Style.space(6)

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: menuColumn
          anchors.fill: parent
          anchors.topMargin: menuCard.contentTopInset
          anchors.rightMargin: menuCard.contentRightInset
          anchors.bottomMargin: menuCard.contentBottomInset
          anchors.leftMargin: menuCard.contentLeftInset
          spacing: Style.spacing.sm

          Repeater {
            model: root.menuItems

            BcButton {
              required property int index
              required property var modelData
              width: menuColumn.width
              leftAlign: true
              text: modelData.label
              iconText: modelData.icon
              selected: modelData.checked === true
              active: root.menuIndex === index
              enabled: modelData.enabled !== false
              iconSpinning: modelData.spinning === true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.runMenuAction(modelData.action)
            }
          }
        }
      }
    }

    // Logout confirmation. Cancel is preselected so an accidental Return is the
    // safe answer.
    ConfirmDialog {
      id: logoutConfirm
      anchors.fill: parent
      z: 100
      opened: root.logoutConfirmOpen
      message: "Log out of Bandcamp? This deletes the Bandcamp session the plugin imported from your browser. "
        + "Your cached library stays, but private items won't load until a session is imported again on the next Refresh."
      cancelText: "Cancel"
      confirmText: "Log out"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onOpenedChanged: if (opened) selectedIndex = 0
      onCanceled: root.cancelLogout()
      onConfirmed: root.confirmLogout()
    }
  }
}
