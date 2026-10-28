import QtQuick
import QtQuick.Shapes
import qs.Commons

// v3.5.1 live-look: the cat-and-flute settings mark.
//
// This is a vector trace of docs/cat-and-flute-reference.jpg (kept in the
// repository as design provenance), not an embedded bitmap. The path uses the
// same 508 x 346 coordinate space as the reference's trimmed drawing box, so
// the proportions can be compared directly. Every stroke is bound to
// root.strokeColor, which the panel binds to the theme accent token.
Item {
  id: root
  objectName: "catMark"

  property color strokeColor: Color.accent
  property real strokeThickness: 4.2

  implicitWidth: 508
  implicitHeight: 346

  Shape {
    id: mark
    objectName: "catMarkShape"
    anchors.fill: parent
    antialiasing: true

    // Head: left ear, inner ear, brow, right ear, then both cheeks.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathMove { x: 36; y: 1 }
      PathQuad { x: 26; y: 72; controlX: 31; controlY: 40 }
      PathQuad { x: 28; y: 112; controlX: 22; controlY: 95 }
      PathQuad { x: 31; y: 145; controlX: 34; controlY: 129 }
      PathQuad { x: 42; y: 166; controlX: 29; controlY: 158 }
      PathMove { x: 36; y: 1 }
      PathQuad { x: 90; y: 43; controlX: 60; controlY: 28 }
      PathQuad { x: 146; y: 51; controlX: 120; controlY: 54 }
      PathQuad { x: 173; y: 42; controlX: 170; controlY: 48 }
      PathLine { x: 214; y: 1 }
      PathQuad { x: 236; y: 78; controlX: 228; controlY: 35 }
      PathQuad { x: 228; y: 108; controlX: 240; controlY: 93 }
      PathQuad { x: 219; y: 142; controlX: 224; controlY: 128 }
      PathQuad { x: 203; y: 168; controlX: 215; controlY: 158 }
    }

    // Body: the left flank and belly.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathMove { x: 27; y: 132 }
      PathQuad { x: 25; y: 260; controlX: 18; controlY: 200 }
      PathQuad { x: 95; y: 340; controlX: 35; controlY: 310 }
      PathQuad { x: 168; y: 335; controlX: 130; controlY: 350 }
      PathQuad { x: 225; y: 205; controlX: 195; controlY: 320 }
    }

    // Body: the right flank under the flute.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathMove { x: 218; y: 150 }
      PathQuad { x: 220; y: 195; controlX: 215; controlY: 175 }
      PathQuad { x: 260; y: 215; controlX: 235; controlY: 210 }
      PathQuad { x: 300; y: 255; controlX: 285; controlY: 225 }
      PathQuad { x: 310; y: 325; controlX: 315; controlY: 290 }
      PathQuad { x: 280; y: 346; controlX: 305; controlY: 345 }
    }

    // Paws holding the flute: one curling over the top, one hanging below.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathMove { x: 184; y: 262 }
      PathQuad { x: 226; y: 211; controlX: 212; controlY: 238 }
      PathQuad { x: 240; y: 184; controlX: 235; controlY: 193 }
      PathQuad { x: 253; y: 181; controlX: 245; controlY: 175 }
      PathQuad { x: 255; y: 198; controlX: 259; controlY: 187 }
      PathQuad { x: 240; y: 223; controlX: 250; controlY: 211 }
      PathQuad { x: 208; y: 262; controlX: 225; controlY: 242 }
      PathMove { x: 248; y: 191 }
      PathQuad { x: 270; y: 240; controlX: 260; controlY: 215 }
      PathQuad { x: 274; y: 272; controlX: 278; controlY: 258 }
      PathQuad { x: 258; y: 274; controlX: 270; controlY: 284 }
      PathQuad { x: 256; y: 252; controlX: 250; controlY: 265 }
      PathQuad { x: 272; y: 252; controlX: 262; controlY: 240 }
      PathQuad { x: 292; y: 292; controlX: 284; controlY: 268 }
      PathQuad { x: 296; y: 340; controlX: 300; controlY: 318 }
    }

    // Whiskers, symmetric left and right.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      PathMove { x: 31; y: 134 }
      PathQuad { x: 0; y: 126; controlX: 12; controlY: 130 }
      PathMove { x: 30; y: 145 }
      PathQuad { x: 0; y: 142; controlX: 10; controlY: 143 }
      PathMove { x: 33; y: 156 }
      PathQuad { x: 3; y: 164; controlX: 16; controlY: 160 }
      PathMove { x: 218; y: 134 }
      PathQuad { x: 252; y: 126; controlX: 238; controlY: 130 }
      PathMove { x: 220; y: 145 }
      PathQuad { x: 254; y: 142; controlX: 240; controlY: 143 }
      PathMove { x: 216; y: 156 }
      PathQuad { x: 250; y: 164; controlX: 234; controlY: 160 }
    }

    // Ring eyes, triangle nose and the small muzzle.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathMove { x: 82; y: 111 }
      PathArc { x: 94; y: 111; radiusX: 6; radiusY: 6; direction: PathArc.Clockwise }
      PathArc { x: 82; y: 111; radiusX: 6; radiusY: 6; direction: PathArc.Clockwise }
      PathMove { x: 169; y: 109 }
      PathArc { x: 181; y: 109; radiusX: 6; radiusY: 6; direction: PathArc.Clockwise }
      PathArc { x: 169; y: 109; radiusX: 6; radiusY: 6; direction: PathArc.Clockwise }
      PathMove { x: 111; y: 142 }
      PathLine { x: 139; y: 142 }
      PathLine { x: 125; y: 157 }
      PathLine { x: 111; y: 142 }
      PathMove { x: 125; y: 157 }
      PathLine { x: 125; y: 165 }
      PathQuad { x: 111; y: 172; controlX: 118; controlY: 172 }
      PathMove { x: 125; y: 165 }
      PathQuad { x: 139; y: 172; controlX: 132; controlY: 172 }
    }

    // The horizontal flute at the mouth line.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathMove { x: 8; y: 179 }
      PathLine { x: 501; y: 179 }
      PathQuad { x: 505; y: 183; controlX: 505; controlY: 179 }
      PathLine { x: 505; y: 187 }
      PathQuad { x: 501; y: 191; controlX: 505; controlY: 191 }
      PathLine { x: 8; y: 191 }
      PathLine { x: 8; y: 179 }
    }

    // Finger-hole rings.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeThickness
      capStyle: ShapePath.RoundCap
      PathMove { x: 144; y: 185 }
      PathArc { x: 153; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathArc { x: 144; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathMove { x: 252; y: 185 }
      PathArc { x: 261; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathArc { x: 252; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathMove { x: 286; y: 185 }
      PathArc { x: 295; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathArc { x: 286; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathMove { x: 320; y: 185 }
      PathArc { x: 329; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathArc { x: 320; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathMove { x: 354; y: 185 }
      PathArc { x: 363; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
      PathArc { x: 354; y: 185; radiusX: 4.5; radiusY: 4.5; direction: PathArc.Clockwise }
    }
  }
}
