import QtQuick
import qs.Commons

// A deliberately typographic little release map. Releases are laid out in
// chronological space (older left, newer right), while the selected release
// occupies the centre. Moving the selection animates the same planet glyphs
// through the system instead of replacing three static labels.
Item {
  id: root
  clip: true

  property var releases: []
  property int selectedIndex: 0
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal releaseActivated(int index)
  signal futureActivated()

  implicitWidth: Style.space(510)
  implicitHeight: Style.space(132)

  readonly property real orbitSpacing: Math.min(Style.space(165), width * 0.31)

  Repeater {
    model: root.releases

    Item {
      id: planet
      required property var modelData
      required property int index

      readonly property int distance: Math.abs(index - root.selectedIndex)
      readonly property bool selected: index === root.selectedIndex

      width: Style.space(130)
      height: root.height
      x: root.width / 2 - width / 2 + (root.selectedIndex - index) * root.orbitSpacing
      opacity: distance <= 1 ? 1 : 0
      visible: opacity > 0
      z: selected ? 2 : 1

      Behavior on x { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }
      Behavior on opacity { NumberAnimation { duration: 180 } }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(2)

        Item {
          width: Style.space(122)
          height: Style.space(102)
          anchors.horizontalCenter: parent.horizontalCenter

          ReleasePlanet {
            anchors.centerIn: parent
            release: planet.modelData
            patchSize: Style.space(58)
            minorSize: Style.space(78)
            majorSize: Style.space(98)
            artOpacity: planet.selected ? 1 : 0.72

            Behavior on artOpacity { NumberAnimation { duration: 180 } }
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: String(planet.modelData.version || planet.modelData.tag || "")
          textFormat: Text.PlainText
          color: planet.selected ? root.accent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: planet.selected
        }
      }

      HoverHandler {
        id: planetHover
        enabled: !planet.selected
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      }

      TapHandler {
        enabled: !planet.selected
        onTapped: root.releaseActivated(planet.index)
      }
    }
  }

  // The fog occupies the missing chronological neighbour, so the map never
  // misleadingly suggests that the known release list continues forever.
  component UnchartedPlanet: Item {
    id: uncharted
    // A fog world lives one index beyond an end of the real catalogue. That
    // makes it travel through the same orbit coordinates as every release
    // instead of popping into an already-settled side slot.
    property int virtualIndex: 0
    property bool telescope: false
    readonly property int distance: Math.abs(virtualIndex - root.selectedIndex)
    width: Style.space(130)
    height: root.height
    x: root.width / 2 - width / 2
      + (root.selectedIndex - virtualIndex) * root.orbitSpacing
    opacity: distance <= 1 ? 0.55 : 0
    visible: opacity > 0

    Behavior on x { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180 } }

    Image {
      anchors.centerIn: parent
      width: Style.space(84)
      height: width
      source: uncharted.telescope ? "assets/release-telescope.png" : "assets/release-planets.png"
      sourceClipRect: uncharted.telescope ? Qt.rect(0, 0, 272, 320) : Qt.rect(3 * 272, 0, 272, 320)
      fillMode: Image.PreserveAspectFit
      smooth: false
      mipmap: false
    }

    HoverHandler {
      enabled: uncharted.telescope
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      enabled: uncharted.telescope
      onTapped: root.futureActivated()
    }
  }

  UnchartedPlanet {
    // Releases are newest-first; the older unknown lies after the last one.
    virtualIndex: root.releases.length
  }

  UnchartedPlanet {
    // The newer unknown lies immediately before index zero.
    virtualIndex: -1
    telescope: true
  }
}
