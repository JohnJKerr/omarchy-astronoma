import QtQuick
import qs.Commons

// The ASCII rocket, in the spirit of Omarchy's own logo.txt / icon.txt.
//
// Its exhaust occupies a fixed three-row bay so hovering can ignite it
// without making the surrounding header jump. Cycling text frames keeps the
// effect crisp at every scale: these are still terminal glyphs, not shapes
// pretending to be ASCII.
Item {
  id: root

  property color foreground: Color.foreground
  property real cellSize: Style.font.body

  readonly property bool hovered: hover.hovered
  property int exhaustFrame: 0

  readonly property var exhaustFrames: [
    "   \\/   \n  .**.  \n .    . ",
    "   **   \n  \\||/  \n    .   ",
    "  .\\/   \n   **.  \n .   .  ",
    "   ||   \n  .\\/   \n    . . "
  ]

  implicitWidth: Math.max(hull.implicitWidth, exhaust.implicitWidth)
  implicitHeight: hull.implicitHeight + exhaust.implicitHeight
  width: implicitWidth
  height: implicitHeight

  HoverHandler {
    id: hover
  }

  Timer {
    interval: 110
    running: root.hovered
    repeat: true
    onTriggered: root.exhaustFrame = (root.exhaustFrame + 1) % root.exhaustFrames.length
    onRunningChanged: {
      if (!running) root.exhaustFrame = 0
    }
  }

  Text {
    id: hull
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter

    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: root.cellSize
    lineHeight: 0.95
    lineHeightMode: Text.ProportionalHeight
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignLeft

    text: "   /\\   \n"
        + "  /  \\  \n"
        + "  |==|  \n"
        + "  |  |  \n"
        + " /|  |\\ \n"
        + "/_|__|_\\"
  }

  Text {
    id: exhaust
    anchors.top: hull.bottom
    anchors.horizontalCenter: parent.horizontalCenter

    color: root.foreground
    opacity: root.hovered ? 1 : 0.55
    font.family: Style.font.family
    font.pixelSize: root.cellSize
    lineHeight: 0.95
    lineHeightMode: Text.ProportionalHeight
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignLeft
    text: root.hovered
      ? root.exhaustFrames[root.exhaustFrame]
      : "   ..   \n        \n        "

    Behavior on opacity {
      NumberAnimation { duration: 90 }
    }
  }
}
