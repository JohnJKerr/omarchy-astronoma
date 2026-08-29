import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The full view: every captured update on the left, the selected one in
// full on the right — releases crossed, packages, migrations, warnings,
// errors, and the agent summary when one has been produced.
//
// Summoned with `omarchy-shell shell toggle astronoma.updates '{}'`, or
// from the bar widget's card.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property int selectedIndex: 0
  property string summaryError: ""
  property bool confirmingAgentEnable: false

  // Shares the [menu] surface tokens, so a theme that styles the Omarchy
  // menu styles the flight log to match.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 2.1)
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  readonly property var rows: service.historyRows
  readonly property bool hasRows: rows.length > 0
  readonly property var selectedRow: hasRows && selectedIndex >= 0 && selectedIndex < rows.length
    ? rows[selectedIndex] : null
  // The detail pane renders `detail` when a specific update is loaded, and
  // falls back to the report's own latest so the first paint is never empty.
  readonly property var record: detailService.record
    || (selectedIndex === 0 ? service.latest : null)
  readonly property var releases: record && record.crossed && record.crossed.length
    ? record.crossed
    : (hasRows ? [] : service.recentReleases)
  readonly property bool showingRecentFallback: !record && service.recentReleases.length > 0

  function open(payloadJson) {
    root.opened = true
    root.summaryError = ""
    service.refresh(true)
    if (!root.hasRows) root.selectedIndex = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function select(index) {
    if (index < 0 || index >= rows.length) return
    selectedIndex = index
    summaryError = ""
    detailService.load(rows[index].id)
    detailFlick.contentY = 0
  }

  function moveSelection(delta) {
    if (!hasRows) return
    select(Math.max(0, Math.min(rows.length - 1, selectedIndex + delta)))
  }

  function scrollDetail(pages) {
    if (!detailFlick) return
    var maximum = Math.max(0, detailFlick.contentHeight - detailFlick.height)
    var step = Math.max(Style.space(120), detailFlick.height * 0.85)
    detailFlick.contentY = Math.max(0, Math.min(maximum,
      detailFlick.contentY + pages * step))
  }

  function scrollDetailToEnd(end) {
    if (!detailFlick) return
    detailFlick.contentY = end
      ? Math.max(0, detailFlick.contentHeight - detailFlick.height)
      : 0
  }

  function showPackages(group) {
    if (!group) return
    packageSection.show(group)
    Qt.callLater(function() {
      if (!packageSection || !detailFlick) return
      var point = packageSection.mapToItem(detailFlick.contentItem, 0, 0)
      var maxY = Math.max(0, detailFlick.contentHeight - detailFlick.height)
      detailFlick.contentY = Math.max(0, Math.min(maxY, point.y - Style.space(12)))
    })
  }

  function requestSummary(force) {
    if (!record || !service.hasAgent || detailService.summaryRunning) return
    if (!service.agentSummariesEnabled && !root.confirmingAgentEnable) {
      root.confirmingAgentEnable = true
      return
    }
    summaryError = ""
    detailService.summarise(record.id, force === true, !service.agentSummariesEnabled)
  }

  Service {
    id: service
    onLoaded: {
      // Reading the list is what marks the newest update read, matching
      // the bar widget's card.
      if (root.opened && service.hasUnread) service.markSeen(service.unreadId)
      if (root.opened && root.hasRows && !detailService.record) root.select(root.selectedIndex)
    }
  }

  // A second helper instance owns the selected update, so switching rows
  // never disturbs the list the left pane is drawing.
  Service {
    id: detailService
    property var record: null
    property string loadedId: ""
    property string requestedId: ""
    property string activeId: ""

    function load(id) {
      if (!id) return
      requestedId = String(id)
      if (detailProcess.running) return
      activeId = requestedId
      detailProcess.command = [detailService.helper, "show", activeId]
      detailProcess.running = true
    }

    Process {
      id: detailProcess
      running: false
      command: []
      stdout: StdioCollector { id: detailOut; waitForEnd: true }
      onExited: function(exitCode) {
        if (detailService.activeId === detailService.requestedId) {
          if (exitCode !== 0) detailService.record = null
          else try {
            var parsed = JSON.parse(String(detailOut.text || ""))
            detailService.record = parsed && parsed.ok ? parsed : null
            if (detailService.record) detailService.loadedId = detailService.activeId
          } catch (error) {
            detailService.record = null
          }
        }
        if (detailService.requestedId !== detailService.activeId)
          Qt.callLater(function() { detailService.load(detailService.requestedId) })
      }
    }

    onSummaryFinished: function(payload) {
      if (payload && payload.ok) {
        root.confirmingAgentEnable = false
        // Consent is exposed by the list service while the summary runs on
        // the detail service. Refresh both so the button changes immediately
        // without waiting for the shell to restart.
        service.refresh(false)
        detailService.load(detailService.loadedId)
      }
      else root.summaryError = payload && payload.error ? payload.error : "The agent did not return a summary"
    }
  }

  IpcHandler {
    target: "astronoma"
    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(true); return "ok" }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "astronoma-flightlog"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(980), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(660), window.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding + Style.space(6)

      MouseArea { anchors.fill: parent; onClicked: {} }

      FocusScope {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
          else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) { root.moveSelection(1); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) { root.moveSelection(-1); event.accepted = true }
          else if (event.key === Qt.Key_PageDown) { root.scrollDetail(1); event.accepted = true }
          else if (event.key === Qt.Key_PageUp) { root.scrollDetail(-1); event.accepted = true }
          else if (event.key === Qt.Key_Space) {
            root.scrollDetail((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          }
          else if (event.key === Qt.Key_Home) { root.scrollDetailToEnd(false); event.accepted = true }
          else if (event.key === Qt.Key_End) { root.scrollDetailToEnd(true); event.accepted = true }
          else if (event.key === Qt.Key_R) { service.refresh(true); event.accepted = true }
          else if (event.key === Qt.Key_P) { root.showPackages(packageSection.group); event.accepted = true }
          // Summarising deliberately has no single-key shortcut. This surface
          // takes exclusive keyboard focus, so one stray key would otherwise
          // spend an agent run the user never asked for.
        }

        // ---------------------------------------------------- header
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: Math.max(rocketMark.implicitHeight, titleColumn.implicitHeight)

            Rocket {
              id: rocketMark
              anchors.left: parent.left
              // The widest row of the art runs the full grid, so it needs a
              // little air or it sits right on the card border.
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              foreground: Color.accent
              cellSize: Style.font.bodySmall
            }

            Column {
              id: titleColumn
              anchors.left: rocketMark.right
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Astronoma"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                text: {
                  var suffix = service.installed ? " · Omarchy " + service.installed : ""
                  return "The flight log" + suffix
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

        PanelSeparator {
            id: headerRule
            anchors.top: header.bottom
            anchors.topMargin: Style.space(12)
            anchors.left: parent.left
            anchors.right: parent.right
            foreground: root.foreground
        }

        // ---------------------------------------------------- footer
        Text {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            text: "↑↓ select · pgup/pgdn or space scroll · home/end jump · p packages · r refresh · esc close"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
        }

        // ------------------------------------------- list + detail
        Item {
            anchors.top: headerRule.bottom
            anchors.topMargin: Style.space(12)
            anchors.bottom: footer.top
            anchors.bottomMargin: Style.space(10)
            anchors.left: parent.left
            anchors.right: parent.right

            // ------------------------------------------- history list
            Item {
              id: listPane
              width: Math.round(parent.width * 0.32)
              height: parent.height
              visible: root.hasRows

              Column {
                anchors.fill: parent
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: "UPDATE HISTORY"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Flickable {
                  width: parent.width
                  height: parent.height - Style.space(26)
                  contentWidth: width
                  contentHeight: listColumn.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  Column {
                    id: listColumn
                    width: parent.width
                    spacing: Style.space(2)

                    Repeater {
                      model: root.rows
                      HistoryRow {
                        required property var modelData
                        required property int index
                        width: listColumn.width
                        row: modelData
                        selected: index === root.selectedIndex
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onActivated: root.select(index)
                      }
                    }
                  }
                }
              }
            }

            PanelSeparator {
              visible: root.hasRows
              x: listPane.width + Style.space(14)
              width: 1
              height: parent.height
              foreground: root.foreground
            }

            // ------------------------------------------------ detail
            Flickable {
              id: detailFlick
              x: root.hasRows ? listPane.width + Style.space(30) : 0
              width: parent.width - x
              height: parent.height
              contentWidth: width
              contentHeight: detailColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: detailColumn
                width: detailFlick.width - Style.space(10)
                spacing: Style.space(14)

                // -------------------------------------- headline
                Column {
                  width: parent.width
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    text: root.record
                      ? Model.versionHeadline(root.record.omarchy, service.installed)
                      : (root.showingRecentFallback ? "Recent Omarchy changes" : "No updates captured yet")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    visible: !!root.record
                    text: root.record ? Model.longDate(root.record.startedAt) : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    visible: !root.record
                    width: parent.width
                    text: service.everLoaded
                      ? "Astronoma has not captured an update on this machine yet. It will record the next one automatically — here is what changed in Omarchy recently."
                      : "Reading update history…"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                }

                // Says plainly that this update was reconstructed from
                // package history alone, so nothing here reads as a
                // complete account when it isn't.
                Text {
                  visible: !!root.record && root.record.partial === true
                  width: parent.width
                  text: "Reconstructed from package history — the update log for this run was not available, so migrations are inferred and any warnings were not recorded."
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                // The update finished, but a whole class of package went
                // untouched. Worth saying plainly: it is the reason an
                // expected AUR upgrade is missing from the lists below.
                Text {
                  visible: !!root.record && root.record.aurSkipped === true
                  width: parent.width
                  text: "The AUR was unavailable during this update, so AUR packages were skipped. Re-run the update to pick them up."
                  color: Qt.darker(Color.accent, 1.05)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                // -------------------------------------- stat block
                Column {
                  visible: !!root.record
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: root.record ? Model.statLines(root.record) : []
                    StatLine {
                      required property var modelData
                      value: modelData.value
                      label: modelData.label
                      tone: modelData.tone
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      navigable: !!modelData.group
                      onActivated: root.showPackages(modelData.group)
                    }
                  }
                }

                // An explicit route to the breakdown at the foot of the page.
                // The counts above are clickable too, but a link is the part
                // people actually see.
                Text {
                  id: packagesLink
                  visible: !!root.record && packageSection.total > 0
                  text: "See all " + packageSection.total + " package changes ↓"
                  color: packagesLinkHover.hovered ? Color.accent : Qt.darker(Color.accent, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.underline: packagesLinkHover.hovered

                  HoverHandler {
                    id: packagesLinkHover
                    cursorShape: Qt.PointingHandCursor
                  }

                  TapHandler {
                    onTapped: root.showPackages(packageSection.group)
                  }
                }

                // -------------------------------------- errors first
                Section {
                  visible: !!root.record && (root.record.errors || []).length > 0
                  width: parent.width
                  title: "ERRORS"
                  titleColor: Color.urgent
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  model: root.record ? (root.record.errors || []) : []
                  entryColor: Color.urgent
                }

                Section {
                  visible: !!root.record && (root.record.warnings || []).length > 0
                  width: parent.width
                  title: "WARNINGS"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  model: root.record ? (root.record.warnings || []) : []
                  entryColor: root.dim
                }

                // -------------------------------------- agent summary
                Column {
                  visible: service.hasAgent && !!root.record
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { foreground: root.foreground }

                  PanelSectionHeader {
                    text: "WHAT THIS MEANS FOR YOU"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Text {
                    visible: !!summaryText
                    readonly property string summaryText:
                      root.record && root.record.summary && root.record.summary.text
                        ? Model.neutraliseCode(String(root.record.summary.text)) : ""
                    width: parent.width
                    text: summaryText
                    color: Qt.darker(root.foreground, 1.15)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    textFormat: Text.MarkdownText
                    wrapMode: Text.WordWrap
                    onLinkActivated: function(link) {
                      var safe = Model.safeExternalUrl(link)
                      if (safe) Qt.openUrlExternally(safe)
                    }
                  }

                  Text {
                    visible: root.summaryError !== ""
                    width: parent.width
                    text: root.summaryError
                    color: Color.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Button {
                    width: Math.min(parent.width, Style.space(320))
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    enabled: !detailService.summaryRunning
                    text: {
                      if (detailService.summaryRunning) return "Summarising…"
                      if (!service.agentSummariesEnabled)
                        return root.confirmingAgentEnable ? "Enable and summarise" : "Enable agent summaries"
                      var has = root.record && root.record.summary && root.record.summary.text
                      return has ? "Summarise again" : "Summarise what changed for me"
                    }
                    onClicked: root.requestSummary(
                      !!(root.record && root.record.summary && root.record.summary.text))
                  }

                  Text {
                    visible: root.confirmingAgentEnable && !service.agentSummariesEnabled
                    width: parent.width
                    text: "This sends the update record and GitHub release notes to your installed agent. Agent tools are disabled and it runs from an empty temporary directory."
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    visible: detailService.summaryRunning
                    width: parent.width
                    text: "Running "
                      + (service.agents.length ? service.agents[0].name : "the agent")
                      + " over this update. This can take a minute."
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }

                // -------------------------------------- release notes
                Column {
                  visible: root.releases.length > 0
                  width: parent.width
                  spacing: Style.space(10)

                  PanelSeparator { foreground: root.foreground }

                  PanelSectionHeader {
                    text: root.showingRecentFallback ? "RECENT RELEASES" : "RELEASES CROSSED"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Repeater {
                    model: root.releases
                    Column {
                      required property var modelData
                      width: detailColumn.width
                      spacing: Style.space(4)

                      Text {
                        width: parent.width
                        text: Model.releaseHeading(modelData)
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                        wrapMode: Text.WordWrap
                      }

                      Text {
                        visible: text !== ""
                        width: parent.width
                        text: Model.cleanReleaseBody(modelData.body)
                        color: Qt.darker(root.foreground, 1.15)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        textFormat: Text.MarkdownText
                        wrapMode: Text.WordWrap
                        onLinkActivated: function(link) {
                          var safe = Model.safeExternalUrl(link)
                          if (safe) Qt.openUrlExternally(safe)
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: Model.statusNote(service.releaseStatus) !== ""
                  width: parent.width
                  text: Model.statusNote(service.releaseStatus)
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                // -------------------------------------- packages
                Section {
                  visible: !!root.record && (root.record.migrations || []).length > 0
                  width: parent.width
                  title: "MIGRATIONS THAT RAN"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  model: root.record ? (root.record.migrations || []) : []
                  entryColor: root.dim
                }

                PackageSection {
                  id: packageSection
                  visible: !!root.record
                  width: parent.width
                  record: root.record
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
              }
            }
          }

      }
    }
  }
}
