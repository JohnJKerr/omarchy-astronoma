import QtQuick
import qs.Commons

// One "50 packages upgraded" row. The count is column-aligned so a stack of
// these reads as a table rather than as prose.
//
// Rows that map to a package group are navigable and route into the
// drill-down. Interaction uses pointer handlers rather than a MouseArea:
// Row positions every child *item* it contains, so an anchored MouseArea
// would be laid out as a column of the table and break the alignment.
Row {
  id: root

  property int value: 0
  property string label: ""
  property string tone: "normal"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool navigable: false

  signal activated()

  readonly property bool highlighted: navigable && hover.hovered

  readonly property color toneColor: {
    if (tone === "urgent") return Color.urgent
    if (tone === "warn") return Qt.darker(Color.accent, 1.05)
    if (tone === "accent") return Color.accent
    if (tone === "muted") return Qt.darker(foreground, 1.8)
    return foreground
  }

  spacing: Style.space(8)

  HoverHandler {
    id: hover
    enabled: root.navigable
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    enabled: root.navigable
    onTapped: root.activated()
  }

  Text {
    width: Style.space(30)
    horizontalAlignment: Text.AlignRight
    text: String(root.value)
    textFormat: Text.PlainText
    color: root.highlighted ? Color.accent : root.toneColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: root.tone === "urgent" || root.tone === "accent"
  }

  Text {
    text: root.label
    textFormat: Text.PlainText
    color: root.highlighted
      ? Color.accent
      : (root.tone === "muted" ? Qt.darker(root.foreground, 1.8)
                               : Qt.darker(root.foreground, 1.25))
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.underline: root.highlighted
  }
}
