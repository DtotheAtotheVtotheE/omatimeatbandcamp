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

  readonly property string tooltip: currentTrack && currentTrack.title
    ? (currentTrack.title + (currentTrack.artist ? " — " + currentTrack.artist : ""))
    : "OmaTimeAtBandCamp"

  property var selectedAlbum: null
  property var selectedPlaylist: null

  implicitWidth: showIcon ? button.implicitWidth : 0
  implicitHeight: showIcon ? button.implicitHeight : 0

  onOpenedChanged: if (opened && service && service.collection.length === 0) service.refresh()

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
    service.playContext("list", "Selection", tracks, tracks.indexOf(track))
  }

  function cycleShuffle() {
    if (service) service.setShuffle(((service.shuffleMode || 0) + 1) % 4)
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

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          PanelActionButton {
            iconText: "\u21BB"
            tooltipText: "Refresh library"
            foreground: root.foreground
            size: Style.spacing.controlHeight
            onClicked: if (root.service) root.service.refresh()
          }

          PanelActionButton {
            iconText: "\uF08B"
            tooltipText: "Clear imported Bandcamp session"
            foreground: root.foreground
            size: Style.spacing.controlHeight
            onClicked: if (root.service) root.service.clearCookies()
          }

          PanelActionButton {
            iconText: "\u2715"
            tooltipText: "Close"
            foreground: root.foreground
            size: Style.spacing.controlHeight
            onClicked: root.close()
          }
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
        Keys.onEscapePressed: function(event) {
          if (text !== "") { text = ""; root.service.search("") }
          else root.close()
          event.accepted = true
        }
      }

      // tabs + status --------------------------------------------------------
      Item {
        width: parent.width
        height: Style.spacing.controlHeight

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Button {
            text: "Albums (" + root.albums.length + ")"
            bordered: true
            selected: (root.service ? root.service.activeTab : 0) === 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            height: Style.spacing.controlHeight
            onClicked: if (root.service) root.service.activeTab = 0
          }

          Button {
            text: "Playlists (" + root.playlists.length + ")"
            bordered: true
            selected: (root.service ? root.service.activeTab : 0) === 1
            foreground: root.foreground
            fontFamily: root.fontFamily
            height: Style.spacing.controlHeight
            onClicked: if (root.service) root.service.activeTab = 1
          }

          Button {
            text: "Play all"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            height: Style.spacing.controlHeight
            onClicked: if (root.service) root.service.playAll()
          }

          Button {
            text: root.service ? root.service.shuffleLabel : "Shuffle: Off"
            bordered: true
            selected: root.service && root.service.shuffleMode > 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            height: Style.spacing.controlHeight
            onClicked: root.cycleShuffle()
          }
        }

        Text {
          visible: root.service && root.service.status !== ""
          text: root.service ? root.service.status : ""
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
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
            Button {
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              iconText: "\uf048"
              tooltipText: "Previous"
              foreground: root.foreground
              onClicked: if (root.service) root.service.prev()
            }

            // Primary play/pause: persistent fill built from the active theme's
            // accent colour so it matches the theme rather than a fixed hue.
            BorderSurface {
              id: playButton
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              radius: Style.cornerRadius
              color: Util.alpha(Color.accent, playMouse.containsMouse ? 0.5 : 0.3)
              Behavior on color { ColorAnimation { duration: 100 } }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.playing && !root.paused ? "\uf04c" : "\uf04b"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              MouseArea {
                id: playMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.togglePlay()
              }

              PanelToolTip {
                visible: playMouse.containsMouse
                text: root.playing && !root.paused ? "Pause" : "Play"
                fontFamily: root.fontFamily
              }
            }

            Button {
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              iconText: "\uf04d"
              tooltipText: "Stop"
              foreground: root.foreground
              onClicked: if (root.service) root.service.stop()
            }
            Button {
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              iconText: "\uf051"
              tooltipText: "Next"
              foreground: root.foreground
              onClicked: if (root.service) root.service.next()
            }
          }
        }
      }
    }
  }
}
