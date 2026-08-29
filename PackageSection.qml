import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Installed, removed and upgraded packages.
//
// Removals and installs are listed in full: they are the changes most
// likely to explain something the user notices. Upgrades are collapsed
// behind a disclosure because a system upgrade routinely moves dozens of
// them and the list is dependency noise until it is asked for.
Column {
  id: root

  property var record: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool upgradesExpanded: false

  readonly property var packages: record && record.packages ? record.packages : ({})
  readonly property var installed: packages.installed || []
  readonly property var removed: packages.removed || []
  readonly property var upgraded: packages.upgraded || []
  readonly property color dim: Qt.darker(foreground, 1.5)

  spacing: Style.space(10)
  visible: installed.length > 0 || removed.length > 0 || upgraded.length > 0

  PanelSeparator { foreground: root.foreground }

  Column {
    visible: root.removed.length > 0
    width: parent.width
    spacing: Style.space(5)

    PanelSectionHeader {
      text: "PACKAGES REMOVED"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Repeater {
      model: root.removed
      Text {
        required property var modelData
        width: root.width
        text: "− " + Model.packageLabel(modelData)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }

  Column {
    visible: root.installed.length > 0
    width: parent.width
    spacing: Style.space(5)

    PanelSectionHeader {
      text: "PACKAGES INSTALLED"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Repeater {
      model: root.installed
      Text {
        required property var modelData
        width: root.width
        text: "+ " + Model.packageLabel(modelData)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }

  Column {
    visible: root.upgraded.length > 0
    width: parent.width
    spacing: Style.space(5)

    PanelSectionHeader {
      text: "PACKAGES UPGRADED (" + root.upgraded.length + ")"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Button {
      width: Math.min(parent.width, Style.space(220))
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      text: root.upgradesExpanded ? "Hide the list" : "Show all " + root.upgraded.length
      onClicked: root.upgradesExpanded = !root.upgradesExpanded
    }

    Repeater {
      model: root.upgradesExpanded ? root.upgraded : []
      Text {
        required property var modelData
        width: root.width
        text: "↑ " + Model.packageLabel(modelData)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }
}
