import QtQuick
import qs.Commons

// v3.5.2: the cat-and-flute settings mark, rendered from the reference drawing
// itself as a tintable stencil.
//
// `assets/cat-flute-mask.png` is a tight crop of docs/cat-and-flute-reference.jpg
// with a transparent background and the full drawing (face, whiskers, flute,
// paws and body) kept as white-with-alpha. This canvas draws that stencil and
// then fills it with the theme accent using source-in compositing, so the RGB
// is one flat theme colour and the alpha (including the reference's soft
// antialiased edges) is preserved. There is no vector trace and no image
// embedded in QML.
Item {
  id: root
  objectName: "catStencil"

  // Same theme source as every other accent in the panel.
  property color tintColor: Color.accent

  // The shipped stencil. Its implicit size is the ink bounding box.
  readonly property url maskFile: Qt.resolvedUrl("assets/cat-flute-mask.png")
  readonly property real artAspect: 509 / 346
  // The rendered mark is the tint itself: one flat theme colour, alpha from the
  // stencil. Exposed so the harness can assert the rendered colour source.
  readonly property color renderedColor: tintColor

  implicitWidth: 509
  implicitHeight: 346

  // Hidden loader: Canvas needs the decoded image before it can composite it.
  // Decode at physical display size so Qt does the high-quality downscale once,
  // instead of the Canvas sampler point-sampling the 509 px source and breaking
  // thin strokes into dots.
  Image {
    id: maskSourceImage
    objectName: "catMaskImage"
    source: root.maskFile
    readonly property real dpr: (typeof Screen !== "undefined" && Screen.devicePixelRatio > 0)
      ? Screen.devicePixelRatio : 1
    sourceSize.width: Math.max(1, Math.round(root.width * dpr))
    sourceSize.height: Math.max(1, Math.round(root.height * dpr))
    smooth: true
    mipmap: true
    visible: false
    onStatusChanged: if (status === Image.Ready) maskCanvas.requestPaint()
  }

  // The source re-decodes when sourceSize changes (first layout, DPR change).
  // Repaint in a short burst so the Canvas never keeps a blank first pass; it
  // stops itself once the header has settled and restarts on a size change.
  Timer {
    id: repaintTimer
    interval: 50
    repeat: true
    running: true
    property int ticks: 0
    onTriggered: {
      maskCanvas.requestPaint()
      ticks += 1
      if (ticks >= 20) stop()
    }
  }

  function repaintBurst() {
    repaintTimer.ticks = 0
    repaintTimer.restart()
  }
  onWidthChanged: repaintBurst()
  onHeightChanged: repaintBurst()

  Canvas {
    id: maskCanvas
    objectName: "catMaskCanvas"
    anchors.fill: parent
    // Raster target so the mask is captured reliably by grabToImage as well as
    // drawn in the live shell.
    renderTarget: Canvas.Image
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (maskSourceImage.status !== Image.Ready) return
      ctx.globalCompositeOperation = "source-over"
      ctx.drawImage(maskSourceImage, 0, 0, width, height)
      // Replace the stencil's white RGB with the theme accent while keeping its
      // alpha. This is the opacity-mask step.
      ctx.globalCompositeOperation = "source-in"
      ctx.fillStyle = root.tintColor
      ctx.fillRect(0, 0, width, height)
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()
  }

  onTintColorChanged: maskCanvas.requestPaint()
}
