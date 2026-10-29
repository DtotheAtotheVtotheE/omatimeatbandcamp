import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The one button style for every control in the OmaTimeAtBandcamp window:
// same height, same padding, same border and radius, same 16px icon, same
// hover / pressed / selected states (all inherited from the shell Button, so
// themes keep control of the look). Icon-only buttons are square.
//
// Use `selected` for toggles that are On, `active` for "its menu is open",
// `iconSpinning` for work in progress. Never draw a bare glyph as a control.
Button {
  id: root

  bordered: true
  iconSize: Style.space(16)
  fontSize: Style.font.body
  height: Style.spacing.controlHeight
  width: text === "" ? height : implicitWidth
  opacity: enabled ? 1.0 : 0.45

  // Optional second label at the right edge: the current sort arrow on the
  // selected sort row, and the keyboard hint on a context-menu row. It keeps
  // `text` (and therefore every existing label lookup) unchanged.
  property string trailingText: ""

  // v3.5.1 addendum: a fixed-width leading icon slot, separate from the
  // existing iconText/check slot. Menu rows use it so every icon lines up and
  // a checkable row can keep showing its check in the original slot.
  property string leadingIconText: ""
  property real leadingIconSlot: Style.space(16)
  property bool leadingIconSpinning: false
  // Shift the normal icon/check slot and label right to make room for the
  // leading slot without touching the shell Button's internal Row.
  leftPadding: horizontalPadding + (leadingIconText !== "" ? leadingIconSlot + Style.spacing.controlGap : 0)

  // v3.5.1: focused controls use the theme accent at full strength, from the
  // same Color singleton as the rest of the panel. The unfocused borderSpec is
  // still the shell Button's own token chain, unchanged.
  readonly property color focusColor: Commons.Color.accent
  borderSpec: activeFocus ? Border.flat(focusColor, Style.focusBorderWidth) : root._borderSpec

  Text {
    objectName: "leadingIcon"
    textFormat: Text.PlainText
    visible: root.leadingIconText !== ""
    text: root.leadingIconText
    width: visible ? root.leadingIconSlot : 0
    horizontalAlignment: Text.AlignHCenter
    color: root.selected ? root._selectedColor : root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.iconSize
    rotation: root.leadingIconSpinning ? 0 : root.iconRotation
    transformOrigin: Item.Center
    anchors.left: parent.left
    anchors.leftMargin: root._reservedBorderLeft + root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter

    RotationAnimation on rotation {
      from: 0
      to: 360
      duration: 900
      loops: Animation.Infinite
      running: root.leadingIconSpinning && !Style.reduceMotion
    }
  }

  Text {
    objectName: "trailingText"
    textFormat: Text.PlainText
    visible: root.trailingText !== ""
    text: root.trailingText
    anchors.right: parent.right
    anchors.rightMargin: root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
