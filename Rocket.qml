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
  // The flight log can ignite the exhaust for a launch without having to
  // synthesize a hover over the rocket.
  property bool ignited: false
  // Nearby navigation targets can spin the engine up before their click
  // triggers the full launch effect.
  property bool engineWarm: false

  readonly property bool hovered: hover.hovered
  readonly property bool warming: (hovered || engineWarm) && !ignited
  readonly property bool firing: ignited
  property int exhaustFrame: 0

  onWarmingChanged: {
    if (warming) exhaustFrame = 0
  }
  onFiringChanged: exhaustFrame = 0

  readonly property var exhaustFrames: [
    "   \\/   \n  .**.  \n .    . ",
    "   **   \n  \\||/  \n    .   ",
    "  .\\/   \n   **.  \n .   .  ",
    "   ||   \n  .\\/   \n    . . "
  ]
  readonly property var warmupFrames: [
    "   ..   \n        \n        ",
    "   ::   \n    .   \n        ",
    "   ..   \n   . .  \n        "
  ]

  implicitWidth: Math.max(hull.implicitWidth, exhaust.implicitWidth)
  implicitHeight: hull.implicitHeight + exhaust.implicitHeight
  width: implicitWidth
  height: implicitHeight

  HoverHandler {
    id: hover
  }

  Timer {
    interval: root.firing ? 110 : 180
    running: root.firing || root.warming
    repeat: true
    onTriggered: {
      var frames = root.firing ? root.exhaustFrames : root.warmupFrames
      root.exhaustFrame = (root.exhaustFrame + 1) % frames.length
    }
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
    opacity: root.firing ? 1 : (root.warming ? 0.78 : 0.55)
    font.family: Style.font.family
    font.pixelSize: root.cellSize
    lineHeight: 0.95
    lineHeightMode: Text.ProportionalHeight
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignLeft
    text: root.firing
      ? root.exhaustFrames[root.exhaustFrame]
      : (root.warming
          ? root.warmupFrames[root.exhaustFrame]
          : "   ..   \n        \n        ")

    Behavior on opacity {
      NumberAnimation { duration: 90 }
    }
  }

}
