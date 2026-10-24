import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Separate bar-art module, placed immediately left of the BC module. It never
// fetches anything: the main plugin's backend writes current-art.jpg and this
// widget only displays that local file. FileView watches it so a track change
// repaints without restarting the shell (the backend also sends RTMIN+8 to a
// legacy Waybar image module for the same reason).
Item {
  id: root
  property var bar: null
  property string moduleName: ""
  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string artPath: home + "/.cache/omatimeatbandcamp/current-art.jpg"
  readonly property string mainPlugin: Quickshell.env("OMATIME_PLUGIN_DIR")
    || (home + "/.config/omarchy/plugins/com.github.dtotheatothevtothee.omatimeatbandcamp")
  readonly property string placeholderPath: mainPlugin + "/assets/current-art-placeholder.jpg"
  readonly property int artSize: {
    var n = Number(setting("barArtSize", 24))
    return isFinite(n) ? Math.max(16, Math.min(64, Math.round(n))) : 24
  }
  property int revision: 0
  property bool fallback: false

  onRevisionChanged: fallback = false

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  implicitWidth: artSize
  implicitHeight: artSize

  Image {
    id: image
    objectName: "artImage"
    anchors.fill: parent
    sourceSize.width: root.artSize
    sourceSize.height: root.artSize
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    source: root.fallback
      ? "file://" + root.placeholderPath
      : "file://" + root.artPath + "?v=" + root.revision
    onStatusChanged: if (status === Image.Error) root.fallback = true
  }

  FileView {
    id: artFile
    path: root.artPath
    watchChanges: true
    printErrors: false
    onLoaded: root.revision += 1
    onTextChanged: root.revision += 1
  }

  // The file may be created a moment after the bar starts. Keep showing the
  // bundled placeholder while retrying, so a missing/partial file never paints
  // a broken-image icon and the real cover appears as soon as it is written.
  Timer {
    interval: 900
    repeat: true
    running: root.fallback
    onTriggered: { root.fallback = false; root.revision += 1 }
  }
}
