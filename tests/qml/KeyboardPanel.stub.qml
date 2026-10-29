import QtQuick
import qs.Commons

// HARNESS STUB (throwaway copy only): same API as the real KeyboardPanel, drawn as a plain Item.
Item {
  id: root
  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int padding: Style.spacing.popupPadding
  // The real KeyboardPanel exposes a surface borderSpec; the stub's Rectangle
  // draws a 2 px border, so mirror that width here.
  property var borderSpec: Border.flat(Color.popups.border, 2)
  property int contentWidth: 920
  property int contentHeight: 600
  // v3.5.4 retry: the real KeyboardPanel is a full-screen layer surface whose
  // `width` is the monitor width, while the visible card is `contentWidth`.
  // The stub used to conflate them, hiding the 531b8f7 live bug. Keep them
  // separate so tests can reproduce the live parent chain by changing only
  // `surfaceWidth`.
  property real surfaceWidth: contentWidth
  property bool open: false
  property Item focusTarget: null
  default property alias contentItem: holder.children
  function fittedContentWidth(w, cap) { return cap ? Math.min(w, cap) : w }
  function fittedContentHeight(h, cap) { var d = h + padding * 2 + 4; return cap ? Math.min(d, cap) : d }
  function close() { if (owner && "close" in owner) owner.close() }
  x: 0; y: anchorItem.height + 10
  width: surfaceWidth; height: contentHeight
  visible: open
  Rectangle {
    width: root.contentWidth; height: root.contentHeight
    color: Color.popups.background; border.color: Color.popups.border; border.width: 2
  }
  Item {
    id: holder
    x: root.padding + 2; y: root.padding + 2
    width: Math.max(0, root.contentWidth - 2 * (root.padding + 2))
    height: Math.max(0, root.contentHeight - 2 * (root.padding + 2))
  }
  onOpenChanged: if (open && focusTarget) Qt.callLater(function() { focusTarget.forceActiveFocus() })
}
