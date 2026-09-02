import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Drill-down into the packages an update moved.
//
// One update can move a thousand packages, so this is a filtered, recycling
// list rather than a wall of text: pick a group, optionally type to narrow
// it, and read `name  old → new`. A ListView (not a Repeater in a Column)
// keeps a 1000-row update scrolling smoothly, since only visible delegates
// are ever built.
Column {
  id: root

  property var record: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // "upgraded" | "installed" | "removed"
  property string group: "upgraded"
  // The field owns the filter text. Binding `text` to a property and
  // writing back from onTextChanged is a two-way binding, which is exactly
  // the shape that bites in QML; reading it here keeps one source of truth.
  readonly property string filter: filterField.text

  function clearFilter() { filterField.text = "" }

  readonly property var packages: record && record.packages ? record.packages : ({})
  readonly property var installed: packages.installed || []
  readonly property var removed: packages.removed || []
  readonly property var upgraded: packages.upgraded || []
  // Packages a helper built locally. These also appear under upgraded or
  // installed, so they are a lens over the same update rather than a fourth
  // group, and deliberately do not count towards the total.
  readonly property var aur: record && record.aur ? record.aur : []
  readonly property int total: installed.length + removed.length + upgraded.length
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color faint: Qt.darker(foreground, 2.0)

  readonly property var activeList: {
    if (group === "installed") return installed
    if (group === "removed") return removed
    if (group === "aur") return aur
    return upgraded
  }

  readonly property var visibleList: {
    var needle = String(filter).toLowerCase().replace(/^\s+|\s+$/g, "")
    if (!needle) return activeList
    var out = []
    for (var i = 0; i < activeList.length; i++) {
      var item = activeList[i]
      if (String(item.name || "").toLowerCase().indexOf(needle) !== -1) out.push(item)
    }
    return out
  }

  // Enough to browse, few enough that a 1000-package update still lays out
  // instantly. Anything beyond this is reached by filtering.
  readonly property int renderCap: 150
  readonly property var renderedList: visibleList.length > renderCap
    ? visibleList.slice(0, renderCap)
    : visibleList

  // The AUR list mixes actions, so its rows are marked from the entry rather
  // than from the group the way the single-action lists are.
  function prefixFor(item) {
    var action = group === "aur" ? String((item && item.action) || "") : group
    if (action === "installed") return "+ "
    if (action === "removed") return "− "
    return "↑ "
  }

  // Jumped to from the stat lines above, so "50 packages upgraded" is a
  // route into the list rather than just a number.
  function show(which) {
    if (which === "upgraded" && upgraded.length === 0) return
    if (which === "installed" && installed.length === 0) return
    if (which === "removed" && removed.length === 0) return
    if (which === "aur" && aur.length === 0) return
    group = which
    clearFilter()
  }

  // Default to whichever group actually has something in it, so an update
  // that only removed a package does not open on an empty list.
  function pickDefaultGroup() {
    if (upgraded.length > 0) group = "upgraded"
    else if (installed.length > 0) group = "installed"
    else if (removed.length > 0) group = "removed"
  }

  onRecordChanged: {
    clearFilter()
    pickDefaultGroup()
  }
  Component.onCompleted: pickDefaultGroup()

  spacing: Style.space(8)
  visible: total > 0

  PanelSeparator { foreground: root.foreground }

  PanelSectionHeader {
    text: "PACKAGES"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Row {
    id: chips
    width: parent.width
    spacing: Style.space(6)

    GroupChip { which: "upgraded"; label: "Upgraded"; count: root.upgraded.length }
    GroupChip { which: "installed"; label: "Installed"; count: root.installed.length }
    GroupChip { which: "removed"; label: "Removed"; count: root.removed.length }
    GroupChip { which: "aur"; label: "AUR"; count: root.aur.length }
  }

  TextField {
    id: filterField
    width: parent.width
    // Filtering only earns its place once the list is long enough that
    // scanning it stops being practical.
    visible: root.activeList.length > 12
    foreground: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: Style.space(4)
    placeholderText: "Filter " + root.activeList.length + " packages…"
  }

  Text {
    visible: root.filter !== ""
    text: root.visibleList.length === 0
      ? "No package matches “" + root.filter + "”"
      : root.visibleList.length + " of " + root.activeList.length + " shown"
    textFormat: Text.PlainText
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Laid out inline, with no scroll region of its own. A nested scrollable
  // in the middle of a page traps the wheel, so the page is the only thing
  // that scrolls and this simply grows. The render cap keeps that honest on
  // a thousand-package update — the filter is how you reach the rest.
  Column {
    id: rows
    width: parent.width
    spacing: Style.space(2)

    Repeater {
      model: root.renderedList
      Text {
        required property var modelData
        width: rows.width
        text: root.prefixFor(modelData) + Model.packageLabel(modelData)
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  Text {
    visible: root.visibleList.length > root.renderCap
    width: parent.width
    text: "…and " + (root.visibleList.length - root.renderCap)
      + " more. Type in the filter to narrow the list."
    textFormat: Text.PlainText
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component GroupChip: Button {
    id: chip

    property string which: ""
    property string label: ""
    property int count: 0

    visible: count > 0
    selected: root.group === which
    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    text: label + " " + count
    onClicked: {
      root.group = which
      root.clearFilter()
    }
  }
}
