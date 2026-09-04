import QtQuick
import qs.Commons

// A deliberately typographic little release map. Releases are laid out in
// chronological space (older left, newer right), while the selected release
// occupies the centre. Selection snaps into place so navigation feedback is
// immediate even while a large release body is still loading.
Item {
  id: root
  clip: true

  property var releases: []
  property int selectedIndex: 0
  property bool futureSelected: false
  property bool earlierSelected: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string hoveredTarget: ""
  readonly property bool actionableHovered: hoveredTarget !== ""

  signal releaseActivated(int index)
  signal futureActivated()
  signal earlierActivated()

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
        && !root.futureSelected && !root.earlierSelected

      width: Style.space(130)
      height: root.height
      x: root.width / 2 - width / 2 + (root.selectedIndex - index) * root.orbitSpacing
      opacity: distance <= 1 ? 1 : 0
      visible: opacity > 0
      z: selected ? 2 : 1

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
            spinning: planet.visible
            // Keep neighbouring worlds subtly out of sync while each rotates
            // in place around its own centre.
            spinDuration: 11000 + (planet.index % 5) * 700

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
        onHoveredChanged: {
          var target = "release:" + planet.index
          if (hovered) root.hoveredTarget = target
          else if (root.hoveredTarget === target) root.hoveredTarget = ""
        }
      }

      TapHandler {
        enabled: !planet.selected
        onTapped: root.releaseActivated(planet.index)
      }
    }
  }

  // Instruments occupy the missing chronological neighbours: an astrolabe
  // looks into history and a telescope looks beyond the installed release.
  component UnchartedPlanet: Item {
    id: uncharted
    // A fog world lives one index beyond an end of the real catalogue. That
    // makes it travel through the same orbit coordinates as every release
    // instead of popping into an already-settled side slot.
    property int virtualIndex: 0
    property string instrument: ""
    property real instrumentAngle: 0
    readonly property bool selected: instrument === "telescope"
      ? root.futureSelected : root.earlierSelected
    readonly property int distance: Math.abs(virtualIndex - root.selectedIndex)
    width: Style.space(130)
    height: root.height
    x: root.width / 2 - width / 2
      + (root.selectedIndex - virtualIndex) * root.orbitSpacing
    opacity: distance <= 1 ? (selected ? 1 : 0.55) : 0
    visible: opacity > 0
    z: selected ? 2 : 1

    Image {
      anchors.centerIn: parent
      width: Style.space(84)
      height: width
      source: uncharted.instrument === "telescope"
        ? "assets/release-telescope-stand.png"
        : "assets/release-astrolabe-body.png"
      sourceClipRect: Qt.rect(0, 0, 272, 320)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    Image {
      id: movingInstrument
      anchors.centerIn: parent
      width: Style.space(84)
      height: width
      source: uncharted.instrument === "telescope"
        ? "assets/release-telescope-tube.png"
        : "assets/release-astrolabe-dial.png"
      sourceClipRect: Qt.rect(0, 0, 272, 320)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true

      transform: Rotation {
        // Both layers retain the source canvas, so these origins are the
        // instrument pivots after PreserveAspectFit scales 272x320 into 84px.
        origin.x: uncharted.instrument === "telescope"
          ? Style.space(30.2) : Style.space(42)
        origin.y: uncharted.instrument === "telescope"
          ? Style.space(40.4) : Style.space(44.1)
        angle: uncharted.instrumentAngle
      }
    }

    NumberAnimation on instrumentAngle {
      running: uncharted.visible && uncharted.instrument === "astrolabe"
      loops: Animation.Infinite
      from: 0
      to: 360
      duration: 16000
      easing.type: Easing.Linear
    }

    SequentialAnimation on instrumentAngle {
      running: uncharted.visible && uncharted.instrument === "telescope"
      loops: Animation.Infinite
      NumberAnimation {
        from: -4
        to: 5
        duration: 1800
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        from: 5
        to: -4
        duration: 1800
        easing.type: Easing.InOutSine
      }
    }

    HoverHandler {
      id: unchartedHover
      enabled: uncharted.instrument !== ""
      cursorShape: Qt.PointingHandCursor
      onHoveredChanged: {
        var target = "instrument:" + uncharted.instrument
        if (hovered) root.hoveredTarget = target
        else if (root.hoveredTarget === target) root.hoveredTarget = ""
      }
    }

    TapHandler {
      enabled: uncharted.instrument !== ""
      onTapped: {
        if (uncharted.instrument === "telescope") root.futureActivated()
        else root.earlierActivated()
      }
    }
  }

  UnchartedPlanet {
    // Releases are newest-first; the older unknown lies after the last one.
    virtualIndex: root.releases.length
    instrument: "astrolabe"
  }

  UnchartedPlanet {
    // The newer unknown lies immediately before index zero.
    virtualIndex: -1
    instrument: "telescope"
  }
}
