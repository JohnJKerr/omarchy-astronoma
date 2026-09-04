import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var release: null
  property real patchSize: Style.space(40)
  property real minorSize: Style.space(52)
  property real majorSize: Style.space(64)
  property real artOpacity: 1
  property bool spinning: false
  property int spinDuration: 12000
  property int spinFrame: 0
  property real spinBlend: 0

  readonly property int spinFrameCount: 64
  readonly property int spinFrameColumns: 32
  readonly property int spinFrameWidth: 272
  readonly property int spinFrameHeight: 320

  readonly property int kind: Model.planetKind(release)
  readonly property real planetSize: [patchSize, minorSize, majorSize][kind]
  readonly property bool spinActive: spinning
  readonly property string spinSource: [
    "assets/release-planet-patch-spinning.png",
    "assets/release-planet-minor-spinning.png",
    "assets/release-planet-major-spinning.png"
  ][kind]

  implicitWidth: planetSize
  implicitHeight: planetSize

  Image {
    anchors.centerIn: parent
    width: root.planetSize
    height: width
    visible: !root.spinActive
    source: "assets/release-planets.png"
    sourceClipRect: Qt.rect(root.kind * 272, 0, 272, 320)
    fillMode: Image.PreserveAspectFit
    // The source art is 1-bit dithered at 272x320. Filter it when reducing it
    // to icon size so the sparse highlights do not disappear between pixels.
    smooth: true
    mipmap: true
    opacity: root.artOpacity
  }

  Item {
    anchors.centerIn: parent
    width: root.planetSize
    height: width
    visible: root.spinActive
    opacity: root.artOpacity
    // Flatten the full-opacity frame blend before applying artOpacity. Without
    // a layer, dimmed planets composite each frame separately and pulse.
    layer.enabled: true

    Image {
      anchors.fill: parent
      visible: root.kind === 1
      source: "assets/release-planet-minor-rings.png"
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    Image {
      anchors.fill: parent
      source: root.spinSource
      sourceClipRect: Qt.rect(
        (root.spinFrame % root.spinFrameColumns) * root.spinFrameWidth,
        Math.floor(root.spinFrame / root.spinFrameColumns) * root.spinFrameHeight,
        root.spinFrameWidth, root.spinFrameHeight)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    Image {
      anchors.fill: parent
      source: root.spinSource
      sourceClipRect: Qt.rect(
        ((root.spinFrame + 1) % root.spinFrameColumns) * root.spinFrameWidth,
        Math.floor(((root.spinFrame + 1) % root.spinFrameCount)
          / root.spinFrameColumns) * root.spinFrameHeight,
        root.spinFrameWidth, root.spinFrameHeight)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
      opacity: root.spinBlend
    }
  }

  SequentialAnimation {
    running: root.spinActive
    loops: Animation.Infinite

    NumberAnimation {
      target: root
      property: "spinBlend"
      from: 0
      to: 1
      duration: Math.max(1, root.spinDuration / root.spinFrameCount)
      easing.type: Easing.Linear
    }

    ScriptAction {
      script: {
        root.spinFrame = (root.spinFrame + 1) % root.spinFrameCount
        root.spinBlend = 0
      }
    }
  }
}
