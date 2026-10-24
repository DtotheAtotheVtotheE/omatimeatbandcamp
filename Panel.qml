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

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // `albums` is what the Albums list shows (sorted, optionally without pre-orders).
  readonly property var albums: service ? service.albumsView : []
  readonly property var playlists: service ? service.playlists : []
  readonly property string query: service ? service.searchQuery : ""
  readonly property var searchTracks: service ? service.searchResults.tracks : []
  readonly property var currentTrack: service ? service.currentTrack : null
  readonly property bool playing: service ? service.isPlaying : false
  readonly property bool paused: service ? service.isPaused : false
  readonly property bool refreshing: service ? service.refreshing : false

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
  readonly property bool detailPlayable: query === "" && !!detailItem

  // Overflow (⋯) menu and Sort menu share one card (menuKind: "", "more", "sort"). New
  // "more" entries go in moreItems; destructive ones must go through a ConfirmDialog.
  property string menuKind: ""
  readonly property bool menuOpen: menuKind !== ""
  property int menuIndex: 0
  property bool logoutConfirmOpen: false
  readonly property var moreItems: [
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

  implicitWidth: showIcon ? button.implicitWidth : 0
  implicitHeight: showIcon ? button.implicitHeight : 0

  onOpenedChanged: {
    if (!opened) { menuKind = ""; logoutConfirmOpen = false }
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

  function toggleMenu() {
    menuIndex = 0
    if (menuKind === "more") closeMenu()
    else menuKind = "more"
  }

  function toggleSortMenu() {
    menuIndex = 0
    if (menuKind === "sort") closeMenu()
    else menuKind = "sort"
  }

  function runMenuAction(action) {
    var kind = menuKind
    menuKind = ""
    if (action === "logout") {
      logoutConfirmOpen = true
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
    if (detailStreamable < detailTotal || (detailIsAlbum && selectedAlbum.isPreorder))
      return detailStreamable + " of " + detailTotal + " tracks available"
    return ""
  }

  function partialLine() {
    if (!detailIsAlbum || !selectedAlbum.tracksLoaded) return ""
    var declared = selectedAlbum.declaredCount
    return declared > detailTotal && detailTotal > 0
      ? "Showing " + detailTotal + " of " + declared + " tracks (the source returned fewer)" : ""
  }

  function emptyLine() {
    if (!detailItem || query !== "" || detailTotal > 0) return ""
    if (detailIsAlbum && !selectedAlbum.tracksLoaded) return "Tracks are still loading — the library is syncing"
    return "No tracks in this " + (detailIsAlbum ? "album" : "playlist")
  }

  // ---- bar icon -----------------------------------------------------------
  BarIconButton {
    id: button
    visible: root.showIcon
    anchors.fill: parent
    bar: root.bar
    text: root.playing && !root.paused ? "\uf04c" : "BC"
    tooltipText: root.tooltip
    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        if (root.service) root.service.togglePlay()
      } else {
        root.toggle()
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
    contentWidth: panel.fittedContentWidth(Style.space(920))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(660))

    Column {
      id: contentColumn
      anchors.fill: parent
      spacing: Style.spacing.md

      // header ---------------------------------------------------------------
      Item {
        width: parent.width
        height: Style.spacing.controlHeight

        Text {
          textFormat: Text.PlainText
          text: "OmaTimeAtBandCamp"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        // The only header control. Close is Esc / click outside; logout and
        // other rare actions live in this menu.
        BcButton {
          id: menuButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf141"
          tooltipText: "More"
          active: root.menuOpen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.toggleMenu()
        }
      }

      // search ---------------------------------------------------------------
      TextField {
        id: searchField
        width: parent.width
        placeholderText: "Search albums, playlists, tracks…"
        foreground: root.foreground
        font.family: root.fontFamily
        onTextChanged: if (root.service) root.service.search(text)

        // The search field owns keyboard focus for the whole window, so the
        // overlays are handled here, before its own text entry. While the
        // logout confirmation or the ⋯ menu is open it owns the keyboard.
        // (Qt fires Keys.onEscapePressed before Keys.onPressed, so Esc is
        // handled in its own handler below.)
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.logoutConfirmOpen) {
            logoutConfirm.handleKey(event)
            event.accepted = true
          } else if (root.menuOpen) {
            if (event.key === Qt.Key_Down) root.menuIndex = Math.min(root.menuItems.length - 1, root.menuIndex + 1)
            else if (event.key === Qt.Key_Up) root.menuIndex = Math.max(0, root.menuIndex - 1)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.runMenuAction(root.menuItems[root.menuIndex].action)
            event.accepted = true
          }
        }
        // Esc backs out one layer at a time: confirmation, menu, search text, window.
        Keys.onEscapePressed: function(event) {
          if (root.logoutConfirmOpen) root.cancelLogout()
          else if (root.menuOpen) root.closeMenu()
          else if (text !== "") { text = ""; root.service.search("") }
          else root.close()
          event.accepted = true
        }
      }

      // toolbar --------------------------------------------------------------
      Item {
        width: parent.width
        height: Style.spacing.controlHeight

        Row {
          id: toolbarLeft
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          BcButton {
            text: "Albums (" + root.albums.length + ")"
            selected: (root.service ? root.service.activeTab : 0) === 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.activeTab = 0
          }

          BcButton {
            text: "Playlists (" + root.playlists.length + ")"
            selected: (root.service ? root.service.activeTab : 0) === 1
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.activeTab = 1
          }

          // One toggle with exactly two states, highlighted when On; applies to the
          // current context only (see contextKey).
          BcButton {
            text: "Shuffle: " + (root.shuffleOn ? "On" : "Off")
            selected: root.shuffleOn
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.toggleShuffle(root.contextKey)
          }

          // Sorting and the pre-order filter apply to the Albums list only.
          BcButton {
            id: sortButton
            visible: !root.service || root.service.activeTab === 0
            text: "Sort: " + LibraryModel.sortLabel(root.service ? root.service.sortMode : "added")
            iconText: "\uf0d7"
            active: root.menuKind === "sort"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleSortMenu()
          }

          BcButton {
            id: hidePreorderButton
            visible: !root.service || root.service.activeTab === 0
            text: "Hide pre-orders"
            selected: root.service ? root.service.hidePreorders : false
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.setHidePreorders(!root.service.hidePreorders)
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
            width: Math.min(implicitWidth, Math.max(0, contentColumn.width - toolbarLeft.width - refreshButton.width - Style.spacing.md * 2))
            anchors.verticalCenter: parent.verticalCenter
          }

          BcButton {
            id: refreshButton
            text: "Refresh"
            iconText: "\u21BB"
            tooltipText: root.refreshing ? "Refreshing library…" : "Refresh library"
            enabled: !root.refreshing
            iconSpinning: root.refreshing
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.refresh()
          }
        }
      }

      // library + detail -----------------------------------------------------
      Row {
        width: parent.width
        height: Style.space(430)
        spacing: Style.spacing.md

        Item {
          id: leftPane
          width: parent.width * 0.38
          height: parent.height

          ListView {
            id: listColumn
            objectName: "leftList"
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.query !== ""
              ? root.searchTracks
              : (root.service && root.service.activeTab === 1 ? root.playlists : root.albums)

            // Two-line rows: title wraps to at most two lines (ellipsis only after the
            // second), artist (or track count) on a smaller dimmed line below, and a
            // PRE-ORDER pill with the release date when the album is a pre-order.
            delegate: Item {
              id: rowItem
              width: listColumn.width
              height: rowCol.implicitHeight + Style.space(14)

              readonly property bool isSearch: root.query !== ""
              readonly property bool isPlaylist: !isSearch && root.service && root.service.activeTab === 1
              readonly property var item: modelData
              readonly property bool selected: !!item && !isSearch
                && (isPlaylist ? root.selectedPlaylistUid === item.uid : root.selectedAlbumUid === item.uid)
              readonly property bool preorder: !!item && !isSearch && !isPlaylist && item.isPreorder === true

              Rectangle {
                objectName: "rowFill"
                anchors.fill: parent
                radius: Style.cornerRadius
                color: rowItem.selected ? Util.alpha(Color.accent, 0.22)
                  : (mouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
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
                x: Style.space(11)
                width: parent.width - Style.space(19)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  objectName: "rowTitle"
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: rowItem.selected
                  text: rowItem.item ? (rowItem.isPlaylist ? (rowItem.item.name || rowItem.item.title || "Playlist") : (rowItem.item.title || "")) : ""
                }

                Text {
                  objectName: "rowSub"
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  text: {
                    var it = rowItem.item
                    if (!it) return ""
                    if (rowItem.isSearch) return (it.artist || "") + (it.album ? "  ·  " + it.album : "")
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var it = rowItem.item
                  if (!it) return
                  if (rowItem.isSearch) { root.playTrackNow(it, root.searchTracks); return }
                  if (rowItem.isPlaylist) root.pickPlaylist(it)
                  else root.pickAlbum(it)
                }
              }
            }
          }

          Text {
            objectName: "leftEmpty"
            anchors.centerIn: parent
            width: parent.width - Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: listColumn.count === 0
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: root.query !== "" ? "No tracks match your search"
              : (root.service && root.service.activeTab === 1 ? "No playlists yet"
                : (root.service && root.service.hidePreorders && root.service.collection.length > 0 ? "Only pre-orders here — turn off Hide pre-orders"
                  : "No library yet — press Refresh"))
          }
        }

        BorderSurface {
          width: parent.width - leftPane.width - Style.spacing.md
          height: parent.height
          radius: Style.cornerRadius
          color: "transparent"
          // Frame the detail pane with the theme's brightest colour so it
          // reads as its own surface, distinct from the list on the left.
          borderSpec: Border.flat(Util.alpha(Color.accent, 0.75), Style.normalBorderWidth)

          Column {
            id: detailColumn
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            spacing: Style.spacing.sm

            // Header: same two-line treatment as the rows (title wraps, artist or count
            // on its own dimmed line), plus pre-order state and track availability.
            Item {
              id: detailHeader
              width: parent.width
              height: Math.max(headerCol.implicitHeight, playButton.visible ? playButton.height : 0)

              Column {
                id: headerCol
                anchors.left: parent.left
                anchors.right: playButton.visible ? playButton.left : parent.right
                anchors.rightMargin: playButton.visible ? Style.spacing.md : 0
                spacing: Style.space(2)

                Text {
                  objectName: "detailTitle"
                  textFormat: Text.PlainText
                  width: parent.width
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
                  visible: text !== ""
                  wrapMode: Text.Wrap
                  text: root.partialLine()
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Plays the current context (this album / playlist) from its start. Reads
              // "Play available" when some of its tracks cannot be streamed yet.
              BcButton {
                id: playButton
                objectName: "detailPlay"
                anchors.right: parent.right
                anchors.top: parent.top
                visible: root.detailPlayable
                enabled: root.detailStreamable > 0
                iconText: "\uf04b"
                text: root.detailStreamable < root.detailTotal ? "Play available" : "Play"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.playContextNow()
              }
            }

            Item {
              width: parent.width
              height: parent.height - detailHeader.height - parent.spacing

              ListView {
                id: trackList
                objectName: "trackList"
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.detailTrackList

                // Track titles wrap. Tracks that cannot be streamed (unreleased) are dimmed,
                // have no hover and show "—" instead of a duration; clicking one only shows
                // a notice. The playing track is highlighted with a play marker.
                delegate: Item {
                  id: trackRow
                  width: ListView.view.width
                  height: Math.max(Style.space(34), trackTitle.implicitHeight + Style.space(14))

                  readonly property var track: modelData
                  readonly property bool playable: !!track && track.streamable !== false
                  readonly property bool current: !!track && !!track.uid && !!root.currentTrack && root.currentTrack.uid === track.uid
                  opacity: playable ? 1.0 : 0.45

                  Rectangle {
                    objectName: "trackFill"
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: trackRow.current ? Util.alpha(Color.accent, 0.22)
                      : (trackRow.playable && tMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
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
                    cursorShape: trackRow.playable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                      if (!trackRow.track) return
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
      BorderSurface {
        width: parent.width
        height: Style.space(64)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Item {
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.md
          anchors.rightMargin: Style.spacing.md

          Column {
            anchors.left: parent.left
            anchors.right: controls.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.currentTrack ? (root.currentTrack.title || "") : "Nothing playing"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              textFormat: Text.PlainText
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
              visible: root.service && root.service.playbackError !== ""
              text: root.service ? root.service.playbackError : ""
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            // Nerd Font glyphs (PUA range) so the icons stay monochrome and
            // inherit the theme — Unicode media symbols such as U+23F8 fall
            // back to colour-emoji presentation and paint their own background.
            // Same BcButton as everywhere else; Phase 5 reworks this row.
            BcButton {
              iconText: "\uf048"
              tooltipText: "Previous"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.prev()
            }

            BcButton {
              iconText: root.playing && !root.paused ? "\uf04c" : "\uf04b"
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
              iconText: "\uf04d"
              tooltipText: "Stop"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.stop()
            }

            BcButton {
              iconText: "\uf051"
              tooltipText: "Next"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.next()
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
