import QtQuick
import qs.Commons

// One "83 packages upgraded" row. The count is column-aligned so a stack
// of these reads as a table rather than as prose.
Row {
  id: root

  property int value: 0
  property string label: ""
  property string tone: "normal"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color toneColor: {
    if (tone === "urgent") return Color.urgent
    if (tone === "warn") return Qt.darker(Color.accent, 1.05)
    if (tone === "accent") return Color.accent
    if (tone === "muted") return Qt.darker(foreground, 1.8)
    return foreground
  }

  spacing: Style.space(8)

  Text {
    width: Style.space(30)
    horizontalAlignment: Text.AlignRight
    text: String(root.value)
    color: root.toneColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: root.tone === "urgent" || root.tone === "accent"
  }

  Text {
    text: root.label
    color: root.tone === "muted" ? Qt.darker(root.foreground, 1.8)
                                 : Qt.darker(root.foreground, 1.25)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
