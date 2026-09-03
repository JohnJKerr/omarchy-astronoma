import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var release: null
  property real patchSize: Style.space(28)
  property real minorSize: Style.space(38)
  property real majorSize: Style.space(48)
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
    smooth: false
    mipmap: false
    opacity: root.artOpacity
  }
}
