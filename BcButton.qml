import QtQuick
import qs.Commons
import qs.Ui

// The one button style for every control in the OmaTimeAtBandCamp window:
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
}
