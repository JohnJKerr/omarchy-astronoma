import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Flickable {
  id: root

  property var releases: []
  property bool earlier: false
  property string boundary: ""
  property string installed: ""
  property bool versionUnknown: false
  property bool isDev: false
  property bool loading: false
  property var status: ({})
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color faint: Qt.darker(foreground, 2.1)
  property string fontFamily: Style.font.family

  readonly property bool fullyUpToDate: !earlier
    && releases.length === 0
    && !loading
    && !isDev
    && !versionUnknown
    && !(status.error && !status.fetchedAt)

  signal back()

  contentWidth: width
  contentHeight: page.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

  Column {
    id: page
    width: root.width - Style.space(10)
    spacing: Style.space(14)

    Text {
      text: "← Flight log"
      color: backHover.hovered ? Color.accent : Qt.darker(Color.accent, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.underline: backHover.hovered

      HoverHandler {
        id: backHover
        cursorShape: Qt.PointingHandCursor
      }

      TapHandler { onTapped: root.back() }
    }

    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.earlier ? "Before your flight log" : "Beyond your release"
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        text: root.earlier
          ? (root.boundary
              ? "Published by Omarchy before the earliest recorded version, " + root.boundary
              : "Published Omarchy releases before this machine's recorded history")
          : (root.installed
              ? "Published by Omarchy after " + root.installed
              : "Published Omarchy releases not yet on this machine")
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }

    Column {
      visible: root.releases.length === 0
      width: parent.width
      spacing: Style.space(5)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Image {
          visible: root.fullyUpToDate
          width: Style.space(48)
          height: width
          anchors.verticalCenter: parent.verticalCenter
          source: "assets/release-planets.png"
          // The fourth sprite is the fog-of-war world: the next release exists
          // only as an unknown horizon until Omarchy publishes it.
          sourceClipRect: Qt.rect(272 * 3, 0, 272, 320)
          fillMode: Image.PreserveAspectFit
          // Preserve the dithered detail when the 272x320 sprite is reduced.
          smooth: true
          mipmap: true
        }

        Text {
          width: parent.width - (root.fullyUpToDate ? Style.space(58) : 0)
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (root.loading) return root.earlier
              ? "Consulting the astrolabe…" : "Looking through the telescope…"
            if (root.earlier && !root.boundary) return "No starting version recorded"
            if (root.earlier && root.status.error && !root.status.fetchedAt) return "Release list unavailable"
            if (root.earlier) return "No earlier releases found"
            if (root.isDev) return "You are running a development checkout"
            if (root.versionUnknown) return "Installed version unavailable"
            if (root.status.error && !root.status.fetchedAt) return "Release list unavailable"
            return "You are up to date"
          }
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.WordWrap
        }
      }

      Text {
        visible: !root.loading
        width: parent.width
        text: {
          if (root.isDev) return "A development checkout cannot be compared safely with published releases."
          if (root.earlier && !root.boundary) return "Astronoma needs a recorded Omarchy upgrade before it can identify releases this machine did not run."
          if (root.earlier && root.status.error && !root.status.fetchedAt) return "Astronoma could not load Omarchy's published releases yet. Try refreshing when you are online."
          if (root.earlier) return "The published catalogue contains nothing older than the first version in this flight log."
          if (root.versionUnknown) return "Astronoma could not compare this machine with the published release list."
          if (root.status.error && !root.status.fetchedAt) return "Astronoma could not load Omarchy's published releases yet. Try refreshing when you are online."
          return "There are no published Omarchy releases newer than the one installed."
        }
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }

    Repeater {
      model: root.releases

      Column {
        id: releaseCard
        required property var modelData
        width: page.width
        spacing: Style.space(5)

        PanelSeparator { foreground: root.foreground }

        Row {
          width: parent.width
          spacing: Style.space(10)

          Item {
            id: planetSlot
            // Patch, minor, and major planets use different artwork sizes,
            // but every release title starts at the same horizontal point.
            width: Style.space(64)
            height: Style.space(64)
            anchors.verticalCenter: parent.verticalCenter

            ReleasePlanet {
              anchors.centerIn: parent
              release: releaseCard.modelData
            }
          }

          Text {
            width: parent.width - planetSlot.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: Model.releaseHeading(releaseCard.modelData)
            textFormat: Text.PlainText
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.WordWrap
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          text: Model.cleanReleaseBody(releaseCard.modelData.body)
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.15)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }

    Text {
      visible: Model.statusNote(root.status) !== ""
      width: parent.width
      text: Model.statusNote(root.status)
      textFormat: Text.PlainText
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
