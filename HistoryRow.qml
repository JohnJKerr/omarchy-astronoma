import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One line in the update history: "28 Aug  4.0.0 → 4.0.1  59 packages".
CursorSurface {
  id: root

  property var row: null
  property bool selected: false
  property string fontFamily: Style.font.family

  signal activated()

  readonly property string dateText: row ? Model.shortDate(row.at) : ""
  readonly property string versionText: {
    if (!row || !row.omarchy) return ""
    var from = row.omarchy.from
    var to = row.omarchy.to
    if (from && to && from !== to) return from + " → " + to
    if (to) return to
    return "packages only"
  }
  readonly property string countText: {
    if (!row) return ""
    var total = row.packageTotal || 0
    return total + " " + Model.plural(total, "package")
  }

  hasCursor: selected
  implicitHeight: content.implicitHeight + Style.spacing.controlPaddingY * 2

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.sm
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: root.dateText
        textFormat: Text.PlainText
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width - x
        text: root.versionText
        textFormat: Text.PlainText
        color: root.selected ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: root.selected
        elide: Text.ElideRight
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: root.countText
        textFormat: Text.PlainText
        color: Qt.darker(root.foreground, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Only ever drawn when this update actually recorded a problem, so
      // its presence in the list means something.
      Text {
        visible: !!root.row && (root.row.errors || 0) > 0
        text: "· " + (root.row ? root.row.errors : 0) + " "
        textFormat: Text.PlainText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
