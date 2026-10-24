import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

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

  readonly property var albums: service ? service.collection : []
  readonly property var playlists: service ? service.playlists : []
  readonly property string query: service ? service.searchQuery : ""
  readonly property var searchTracks: service ? service.searchResults.tracks : []
  readonly property var currentTrack: service ? service.currentTrack : null
  readonly property var trackCache: service ? service.trackCache : ({})
  readonly property bool playing: service ? service.isPlaying : false
  readonly property bool paused: service ? service.isPaused : false
  readonly property bool refreshing: service ? service.refreshing : false

  readonly property string tooltip: currentTrack && currentTrack.title
    ? (currentTrack.title + (currentTrack.artist ? " — " + currentTrack.artist : ""))
    : "OmaTimeAtBandCamp"

  property var selectedAlbum: null
  property var selectedPlaylist: null

  // The playback/shuffle context is whatever the detail pane is showing: search
  // results, the selected playlist, the selected album, or (nothing selected) the
  // whole library. Shuffle is remembered per context.
  readonly property string contextKey: query !== "" ? "search"
    : selectedPlaylist ? "playlist:" + selectedPlaylist.id
    : selectedAlbum ? "album:" + selectedAlbum.id
    : "library"
  readonly property bool shuffleOn: service ? service.isShuffled(contextKey) : false

  // Overflow (⋯) menu and its confirmation. New menu entries are added to
  // `menuItems`; destructive ones must go through a ConfirmDialog like logout.
  property bool menuOpen: false
  property int menuIndex: 0
  property bool logoutConfirmOpen: false
  readonly property var menuItems: [
    { icon: "\uf08b", label: "Log out / Clear Bandcamp session", action: "logout" }
  ]

  implicitWidth: showIcon ? button.implicitWidth : 0
  implicitHeight: showIcon ? button.implicitHeight : 0

  onOpenedChanged: {
    if (!opened) { menuOpen = false; logoutConfirmOpen = false }
    else if (service && service.collection.length === 0) service.refresh()
  }

  function toggleMenu() {
    menuIndex = 0
    menuOpen = !menuOpen
    if (!menuOpen) searchField.forceActiveFocus()
  }

  function runMenuAction(action) {
    menuOpen = false
    if (action === "logout") logoutConfirmOpen = true
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

  function pickAlbum(alb) {
    selectedPlaylist = null
    selectedAlbum = alb
    if (service) service.requestTracks(alb)
  }

  function pickPlaylist(pl) {
    selectedAlbum = null
    selectedPlaylist = pl
    if (service && (!pl.tracks || pl.tracks.length === 0)) service.requestTracks(pl)
  }

  function playTrackNow(track, list) {
    if (!service) return
    var tracks = list || [track]
    service.playContext("list", detailTitle(), tracks, tracks.indexOf(track), contextKey)
  }

  // Footer Play with nothing loaded: play the current context from its start
  // (shuffled if that context's Shuffle is On).
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
    if (selectedAlbum) return (selectedAlbum.title || "") + (selectedAlbum.artist ? " — " + selectedAlbum.artist : "")
    return "Pick an album or playlist"
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
          else if (root.menuOpen) root.toggleMenu()
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

        ListView {
          id: listColumn
          width: parent.width * 0.38
          height: parent.height
          clip: true
          model: root.query !== ""
            ? root.searchTracks
            : (root.service && root.service.activeTab === 1 ? root.playlists : root.albums)
          delegate: Rectangle {
            width: listColumn.width
            height: Style.space(40)
            color: "transparent"
            radius: Style.cornerRadius

            readonly property bool isSearch: root.query !== ""
            readonly property bool isPlaylist: !isSearch && root.service && root.service.activeTab === 1
            readonly property var item: modelData
            readonly property bool selected: (!isSearch && !isPlaylist && root.selectedAlbum === item)
              || (isPlaylist && root.selectedPlaylist === item)

            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: parent.selected ? Style.selectedFillFor(root.foreground, Color.accent)
                : (mouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
            }

            Text {
              textFormat: Text.PlainText
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.sm
              anchors.rightMargin: Style.spacing.sm
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              text: {
                var it = modelData
                if (!it) return ""
                if (parent.isSearch) return (it.title || "") + (it.artist ? "  ·  " + it.artist : "")
                if (parent.isPlaylist) return it.name || it.title || "Playlist"
                return (it.title || "") + (it.artist ? "  ·  " + it.artist : "")
              }
            }

            MouseArea {
              id: mouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var it = parent.item
                if (!it) return
                if (root.query !== "") { root.playTrackNow(it, root.searchTracks); return }
                if (root.service && root.service.activeTab === 1) root.pickPlaylist(it)
                else root.pickAlbum(it)
              }
            }
          }
        }

        BorderSurface {
          width: parent.width - listColumn.width - Style.spacing.md
          height: parent.height
          radius: Style.cornerRadius
          color: "transparent"
          // Frame the detail pane with the theme's brightest colour so it
          // reads as its own surface, distinct from the list on the left.
          borderSpec: Border.flat(Util.alpha(Color.accent, 0.75), Style.normalBorderWidth)

          Column {
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            spacing: Style.spacing.sm

            Text {
            textFormat: Text.PlainText
            width: parent.width
            height: Style.space(24)
            text: root.detailTitle()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }

          ListView {
            id: trackList
            width: parent.width
            height: parent.height - Style.space(24) - parent.spacing
            clip: true
            model: root.detailTracks()
            delegate: Rectangle {
              width: ListView.view.width
              height: Style.space(34)
              color: "transparent"
              radius: Style.cornerRadius

              readonly property var track: modelData
              readonly property bool current: root.service && root.currentTrack === track

              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: parent.current ? Style.selectedFillFor(root.foreground, Color.accent)
                  : (tMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.sm
                anchors.rightMargin: Style.spacing.sm
                spacing: Style.spacing.sm

                Text {
                  textFormat: Text.PlainText
                  text: (track.track_num ? track.track_num + "." : "")
                  width: Style.space(28)
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: track.title || ""
                  width: parent.width - Style.space(90)
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: track.duration
                    ? Math.floor(track.duration / 60) + ":" + ("0" + Math.floor(track.duration % 60)).slice(-2)
                    : ""
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: tMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.playTrackNow(track, root.detailTracks())
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

    // ⋯ menu ------------------------------------------------------------------
    // Click anywhere outside the card closes the menu (the window itself stays
    // open); the card sits just under the header button.
    Item {
      anchors.fill: parent
      visible: root.menuOpen
      z: 50

      MouseArea {
        anchors.fill: parent
        onClicked: root.toggleMenu()
      }

      BorderSurface {
        id: menuCard
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.controlHeight + Style.spacing.sm
        width: Math.min(Style.space(300), parent.width)
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
              selected: root.menuIndex === index
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
