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

  readonly property int kind: Model.planetKind(release)
  readonly property real planetSize: [patchSize, minorSize, majorSize][kind]

  implicitWidth: planetSize
  implicitHeight: planetSize

  Image {
    anchors.centerIn: parent
    width: root.planetSize
    height: width
    source: "assets/release-planets.png"
    sourceClipRect: Qt.rect(root.kind * 272, 0, 272, 320)
    fillMode: Image.PreserveAspectFit
    // The source art is 1-bit dithered at 272x320. Filter it when reducing it
    // to icon size so the sparse highlights do not disappear between pixels.
    smooth: true
    mipmap: true
    opacity: root.artOpacity
  }
}
