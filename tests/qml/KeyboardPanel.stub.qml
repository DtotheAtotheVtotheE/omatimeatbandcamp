import QtQuick
import qs.Commons

// HARNESS STUB (throwaway copy only): same API as the real KeyboardPanel, drawn as a plain Item.
Item {
  id: root
  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int padding: Style.spacing.popupPadding
  property int contentWidth: 920
  property int contentHeight: 600
  property bool open: false
  property Item focusTarget: null
  default property alias contentItem: holder.children
  function fittedContentWidth(w, cap) { return cap ? Math.min(w, cap) : w }
  function fittedContentHeight(h, cap) { var d = h + padding * 2 + 4; return cap ? Math.min(d, cap) : d }
  function close() { if (owner && "close" in owner) owner.close() }
  x: 0; y: anchorItem.height + 10
  width: contentWidth; height: contentHeight
  visible: open
  Rectangle { anchors.fill: parent; color: Color.popups.background; border.color: Color.popups.border; border.width: 2 }
  Item { id: holder; anchors.fill: parent; anchors.margins: root.padding + 2 }
  onOpenChanged: if (open && focusTarget) Qt.callLater(function() { focusTarget.forceActiveFocus() })
}
