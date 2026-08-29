import QtQuick
import qs.Commons
import qs.Ui

// A titled list of plain strings — errors, warnings, migration names.
Column {
  id: root

  property string title: ""
  property color titleColor: Color.foreground
  property color foreground: Color.foreground
  property color entryColor: Color.foreground
  property string fontFamily: Style.font.family
  property var model: []

  spacing: Style.space(5)

  PanelSectionHeader {
    text: root.title
    foreground: root.titleColor
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.model
    Text {
      required property var modelData
      width: root.width
      text: "• " + modelData
      color: root.entryColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }
}
