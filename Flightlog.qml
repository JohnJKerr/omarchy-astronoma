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
// Summoned with `omarchy-shell shell toggle io.github.johnjkerr.astronoma '{}'`, or
// from the bar widget's card.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property int selectedIndex: 0
  property int selectedReleaseIndex: 0
  property string summaryError: ""
  property bool confirmingAgentEnable: false
  property bool choosingAgent: false
  property string chosenAgentKey: ""
  property bool showingUpcoming: false
  property bool showingEarlier: false
  property int hoveredHistoryIndex: -1
  readonly property bool showingReleaseCatalogue: showingUpcoming || showingEarlier

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
  readonly property bool initialLoading: root.opened && service.loading && !service.everLoaded
  readonly property bool detailLoading: !root.initialLoading
    && !root.showingReleaseCatalogue && detailService.loading
  readonly property var selectedRow: hasRows && selectedIndex >= 0 && selectedIndex < rows.length
    ? rows[selectedIndex] : null
  // The detail pane renders `detail` when a specific update is loaded, and
  // falls back to the report's own latest so the first paint is never empty.
  readonly property var record: detailService.record
    || (selectedIndex === 0 ? service.latest : null)
  readonly property var releases: record && record.crossed && record.crossed.length
    ? record.crossed
    : (hasRows ? [] : service.recentReleases)
  // The header is a release navigator, not merely a summary of the selected
  // update. Keep its catalogue global even when the detail pane shows only
  // the releases crossed by one historical update.
  readonly property var solarReleases: navigableReleaseCatalogue()
  readonly property bool showingRecentFallback: !record && service.recentReleases.length > 0

  function open(payloadJson) {
    root.opened = true
    root.showingUpcoming = false
    root.showingEarlier = false
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
    var landed = rows[index].omarchy && rows[index].omarchy.to
      ? String(rows[index].omarchy.to) : ""
    var releaseIndex = releaseIndexForVersion(landed)
    if (releaseIndex >= 0) selectedReleaseIndex = releaseIndex
    summaryError = ""
    detailService.load(rows[index].id)
    detailFlick.contentY = 0
  }

  function releaseIndexForVersion(version) {
    for (var i = 0; i < solarReleases.length; ++i) {
      if (String(solarReleases[i].version || "") === String(version || "")) return i
    }
    return -1
  }

  function navigableReleaseCatalogue() {
    var out = []
    for (var releaseIndex = 0; releaseIndex < service.recentReleases.length; ++releaseIndex) {
      var release = service.recentReleases[releaseIndex]
      var version = String(release.version || "")
      for (var rowIndex = 0; rowIndex < rows.length; ++rowIndex) {
        var landed = rows[rowIndex].omarchy && rows[rowIndex].omarchy.to
          ? String(rows[rowIndex].omarchy.to) : ""
        if (landed === version) {
          out.push(release)
          break
        }
      }
    }
    return out
  }

  function selectRelease(index) {
    if (index < 0 || index >= solarReleases.length) return
    // A planet is also the route back from either catalogue. Do this before
    // the same-index guard: the currently selected release is still a valid
    // navigation target when the telescope or astrolabe page is open.
    showingUpcoming = false
    showingEarlier = false
    if (index === selectedReleaseIndex) return
    selectedReleaseIndex = index
    igniteRocket()
    var version = String(solarReleases[index].version || "")
    for (var i = 0; i < rows.length; ++i) {
      var landed = rows[i].omarchy && rows[i].omarchy.to
        ? String(rows[i].omarchy.to) : ""
      if (landed === version) {
        select(i)
        return
      }
    }
  }

  function igniteRocket() {
    rocketMark.ignited = true
    launchTimer.restart()
  }

  function launchToHistory(index) {
    if (index < 0 || index >= rows.length) return
    igniteRocket()
    select(index)
  }

  function moveSelection(delta) {
    if (!hasRows) return
    select(Math.max(0, Math.min(rows.length - 1, selectedIndex + delta)))
  }

  function scrollDetail(amount) {
    var view = root.showingReleaseCatalogue
      ? (root.showingEarlier ? earlierPage : futurePage) : detailFlick
    if (!view) return
    var maximum = Math.max(0, view.contentHeight - view.height)
    view.contentY = Math.max(0, Math.min(maximum, view.contentY + amount))
  }

  function scrollDetailLine(direction) {
    scrollDetail(direction * Style.space(40))
  }

  function scrollDetailPage(direction) {
    var view = root.showingReleaseCatalogue
      ? (root.showingEarlier ? earlierPage : futurePage) : detailFlick
    if (!view) return
    scrollDetail(direction * view.height)
  }

  function scrollDetailToEnd(end) {
    var view = root.showingReleaseCatalogue
      ? (root.showingEarlier ? earlierPage : futurePage) : detailFlick
    if (!view) return
    view.contentY = end
      ? Math.max(0, view.contentHeight - view.height)
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
    if (!root.chosenAgentKey) {
      root.choosingAgent = true
      return
    }
    if (!service.agentSummariesEnabled && !root.confirmingAgentEnable) {
      root.confirmingAgentEnable = true
      return
    }
    summaryError = ""
    detailService.summarise(record.id, force === true,
                            !service.agentSummariesEnabled, root.chosenAgentKey)
  }

  Service {
    id: service
    onLoaded: {
      if (service.selectedAgent) root.chosenAgentKey = String(service.selectedAgent.key)
      else if (service.agentSelectionMissing) root.chosenAgentKey = ""
      // Reading the list is what marks the newest update read, matching
      // the bar widget's card.
      if (root.opened && service.hasUnread) service.markSeen(service.unreadId)
      if (root.opened && root.hasRows && !detailService.record) root.select(root.selectedIndex)
    }
  }

  Timer {
    id: launchTimer
    interval: 850
    repeat: false
    onTriggered: rocketMark.ignited = false
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
      if (requestedId !== loadedId) {
        detailService.loading = true
        // The loading surface covers the previous update. Keep its detail
        // tree alive underneath until the replacement is ready: tearing down
        // a large release synchronously here can prevent the solar-system
        // selection animation from painting its first frame.
      }
      if (detailProcess.running) return
      activeId = requestedId
      detailProcess.start([detailService.helper, "show", activeId, "--pretty"])
    }

    BoundedProcess {
      id: detailProcess
      onFinished: function(exitCode, failure) {
        if (failure) detailService.record = null
        else if (detailService.activeId === detailService.requestedId) {
          if (exitCode !== 0) detailService.record = null
          else try {
            var parsed = JSON.parse(detailProcess.stdoutText)
            detailService.record = parsed && parsed.ok ? parsed : null
            if (detailService.record) detailService.loadedId = detailService.activeId
          } catch (error) {
            detailService.record = null
          }
        }
        if (detailService.requestedId !== detailService.activeId)
          Qt.callLater(function() { detailService.load(detailService.requestedId) })
        else detailService.loading = false
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
          if (event.key === Qt.Key_Escape) {
            if (root.showingReleaseCatalogue) {
              root.showingUpcoming = false
              root.showingEarlier = false
            }
            else root.close()
            event.accepted = true
          }
          else if (event.key === Qt.Key_Down) { root.scrollDetailLine(1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { root.scrollDetailLine(-1); event.accepted = true }
          else if (!root.showingReleaseCatalogue && event.key === Qt.Key_J) { root.moveSelection(1); event.accepted = true }
          else if (!root.showingReleaseCatalogue && event.key === Qt.Key_K) { root.moveSelection(-1); event.accepted = true }
          else if (event.key === Qt.Key_PageDown) { root.scrollDetailPage(1); event.accepted = true }
          else if (event.key === Qt.Key_PageUp) { root.scrollDetailPage(-1); event.accepted = true }
          else if (event.key === Qt.Key_Space) {
            root.scrollDetailPage((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          }
          else if (event.key === Qt.Key_Home) { root.scrollDetailToEnd(false); event.accepted = true }
          else if (event.key === Qt.Key_End) { root.scrollDetailToEnd(true); event.accepted = true }
          else if (event.key === Qt.Key_R) { service.refresh(true); event.accepted = true }
          else if (!root.showingReleaseCatalogue && event.key === Qt.Key_P) { root.showPackages(packageSection.group); event.accepted = true }
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
            clip: true
            implicitHeight: Math.max(rocketMark.implicitHeight, titleColumn.implicitHeight,
                                     releaseSystem.visible ? releaseSystem.implicitHeight : 0)

            // A quiet star field gives the flight-deck header some depth
            // without competing with the release navigator. Fixed positions
            // keep the scene stable; varied cycles stop the twinkle from
            // looking synchronized.
            Item {
              id: starField
              anchors.fill: parent
              z: -1

              readonly property var stars: [
                { x: 0.02, y: 0.16, size: 2, low: 0.10, high: 0.48, rise: 920, fall: 1380 },
                { x: 0.09, y: 0.72, size: 1, low: 0.14, high: 0.56, rise: 1450, fall: 980 },
                { x: 0.18, y: 0.24, size: 1, low: 0.08, high: 0.42, rise: 1180, fall: 1720 },
                { x: 0.27, y: 0.82, size: 2, low: 0.10, high: 0.38, rise: 1740, fall: 1120 },
                { x: 0.34, y: 0.12, size: 1, low: 0.12, high: 0.58, rise: 1040, fall: 1510 },
                { x: 0.41, y: 0.58, size: 1, low: 0.08, high: 0.44, rise: 1580, fall: 1240 },
                { x: 0.48, y: 0.30, size: 2, low: 0.10, high: 0.50, rise: 1320, fall: 1860 },
                { x: 0.55, y: 0.76, size: 1, low: 0.12, high: 0.54, rise: 1880, fall: 1050 },
                { x: 0.62, y: 0.10, size: 1, low: 0.08, high: 0.40, rise: 1260, fall: 1580 },
                { x: 0.68, y: 0.48, size: 2, low: 0.10, high: 0.46, rise: 1520, fall: 1180 },
                { x: 0.74, y: 0.86, size: 1, low: 0.14, high: 0.52, rise: 980, fall: 1690 },
                { x: 0.80, y: 0.20, size: 1, low: 0.08, high: 0.48, rise: 1640, fall: 1360 },
                { x: 0.86, y: 0.64, size: 2, low: 0.10, high: 0.42, rise: 1120, fall: 1780 },
                { x: 0.92, y: 0.08, size: 1, low: 0.12, high: 0.56, rise: 1820, fall: 1080 },
                { x: 0.97, y: 0.78, size: 1, low: 0.08, high: 0.44, rise: 1380, fall: 1480 }
              ]

              Repeater {
                model: starField.stars

                Rectangle {
                  id: star
                  required property var modelData
                  x: Math.round(modelData.x * (starField.width - width))
                  y: Math.round(modelData.y * (starField.height - height))
                  width: Style.space(modelData.size)
                  height: width
                  radius: width / 2
                  color: root.foreground
                  opacity: modelData.low

                  SequentialAnimation on opacity {
                    running: window.visible
                    loops: Animation.Infinite
                    NumberAnimation {
                      from: star.modelData.low
                      to: star.modelData.high
                      duration: star.modelData.rise
                      easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                      from: star.modelData.high
                      to: star.modelData.low
                      duration: star.modelData.fall
                      easing.type: Easing.InOutSine
                    }
                  }
                }
              }
            }

            Rocket {
              id: rocketMark
              anchors.left: parent.left
              // The widest row of the art runs the full grid, so it needs a
              // little air or it sits right on the card border.
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              foreground: Color.accent
              cellSize: Style.font.bodySmall
              engineWarm: root.hoveredHistoryIndex >= 0
                || releaseSystem.actionableHovered
            }

            Column {
              id: titleColumn
              anchors.left: rocketMark.right
              anchors.leftMargin: Style.space(16)
              anchors.right: releaseSystem.visible ? releaseSystem.left : parent.right
              anchors.rightMargin: releaseSystem.visible ? Style.space(10) : 0
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

            SolarSystem {
              id: releaseSystem
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.55)
              height: implicitHeight
              releases: root.solarReleases
              selectedIndex: Math.min(root.selectedReleaseIndex, Math.max(0, root.solarReleases.length - 1))
              futureSelected: root.showingUpcoming
              earlierSelected: root.showingEarlier
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              visible: root.solarReleases.length > 0
              onReleaseActivated: function(index) { root.selectRelease(index) }
              onFutureActivated: {
                root.igniteRocket()
                root.showingEarlier = false
                root.showingUpcoming = true
                futurePage.contentY = 0
              }
              onEarlierActivated: {
                root.igniteRocket()
                root.showingUpcoming = false
                root.showingEarlier = true
                earlierPage.contentY = 0
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
            text: root.showingReleaseCatalogue
              ? "↑↓ scroll · pgup/pgdn or space scroll page · home/end jump · r refresh · esc flight log"
              : "↑↓ scroll · j/k select · pgup/pgdn or space scroll page · home/end jump · p packages · r refresh · esc close"
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
              visible: root.hasRows && !root.showingReleaseCatalogue

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
                      Row {
                        id: historyEntry
                        required property var modelData
                        required property int index
                        width: listColumn.width
                        spacing: Style.space(8)

                        HoverHandler {
                          cursorShape: Qt.PointingHandCursor
                          onHoveredChanged: {
                            if (hovered) root.hoveredHistoryIndex = historyEntry.index
                            else if (root.hoveredHistoryIndex === historyEntry.index) {
                              root.hoveredHistoryIndex = -1
                            }
                          }
                        }

                        HistoryRow {
                          width: parent.width - historyPlanetSlot.width - parent.spacing
                          anchors.verticalCenter: parent.verticalCenter
                          row: historyEntry.modelData
                          selected: historyEntry.index === root.selectedIndex
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onActivated: root.launchToHistory(historyEntry.index)
                        }

                        Item {
                          id: historyPlanetSlot
                          readonly property bool hasRelease: !!historyEntry.modelData.omarchy
                            && !!historyEntry.modelData.omarchy.to
                          width: Style.space(64)
                          height: Style.space(64)

                          ReleasePlanet {
                            anchors.centerIn: parent
                            visible: historyPlanetSlot.hasRelease
                            release: ({
                              version: visible
                                ? String(historyEntry.modelData.omarchy.to) : ""
                            })
                          }

                          MouseArea {
                            anchors.fill: parent
                            enabled: historyPlanetSlot.hasRelease
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launchToHistory(historyEntry.index)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            PanelSeparator {
              visible: root.hasRows && !root.showingReleaseCatalogue
              x: listPane.width + Style.space(14)
              width: 1
              height: parent.height
              foreground: root.foreground
            }

            // ------------------------------------------------ detail
            Flickable {
              id: detailFlick
              visible: !root.showingReleaseCatalogue
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
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    visible: !!root.record
                    text: root.record ? Model.longDate(root.record.startedAt) : ""
                    textFormat: Text.PlainText
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
                    text: "YOUR PERSONALISED SUMMARY"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Text {
                    visible: !!summaryText
                    readonly property string summaryText:
                      root.record && root.record.summary && root.record.summary.text
                        ? Model.cleanPlainText(String(root.record.summary.text)) : ""
                    width: parent.width
                    text: summaryText
                    color: Qt.darker(root.foreground, 1.15)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    visible: root.summaryError !== ""
                    width: parent.width
                    text: root.summaryError
                    textFormat: Text.PlainText
                    color: Color.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Row {
                    width: Math.min(parent.width, Style.space(460))
                    spacing: Style.space(8)

                    Button {
                      width: parent.width - agentChoice.width - parent.spacing
                      bordered: true
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: !detailService.summaryRunning && root.chosenAgentKey !== ""
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

                    Button {
                      id: agentChoice
                      width: Style.space(160)
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      text: root.chosenAgentKey
                        ? (service.agents.find(function(item) { return item.key === root.chosenAgentKey }) || {name: "Choose AI provider"}).name + " ▾"
                        : "Choose AI provider ▾"
                      onClicked: root.choosingAgent = !root.choosingAgent
                    }
                  }

                  Column {
                    visible: root.choosingAgent
                    width: Math.min(parent.width, Style.space(460))
                    spacing: Style.space(4)

                    Repeater {
                      model: service.agents
                      Button {
                        required property var modelData
                        width: parent.width
                        bordered: String(modelData.key) === root.chosenAgentKey
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        text: String(modelData.name)
                        onClicked: {
                          root.chosenAgentKey = String(modelData.key)
                          root.choosingAgent = false
                          service.selectAgent(root.chosenAgentKey)
                        }
                      }
                    }
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
                      + (service.agents.find(function(item) { return item.key === root.chosenAgentKey }) || {name: "the agent"}).name
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
                    id: releaseRepeater
                    model: root.releases
                    Column {
                      required property var modelData
                      width: detailColumn.width
                      spacing: Style.space(4)

                      Text {
                        width: parent.width
                        text: Model.releaseHeading(modelData)
                        textFormat: Text.PlainText
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                        wrapMode: Text.WordWrap
                      }

                      Loader {
                        id: releaseBodyLoader
                        width: parent.width
                        active: String(modelData.body || "") !== ""
                        asynchronous: true

                        sourceComponent: Text {
                          width: releaseBodyLoader.width
                          text: Model.cleanReleaseBody(modelData.body)
                          color: Qt.darker(root.foreground, 1.15)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          textFormat: Text.PlainText
                          wrapMode: Text.WordWrap
                        }
                      }

                      Text {
                        visible: releaseBodyLoader.status === Loader.Loading
                        text: "Rendering release notes…"
                        textFormat: Text.PlainText
                        color: root.faint
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                Text {
                  visible: Model.statusNote(service.releaseStatus) !== ""
                  width: parent.width
                  text: Model.statusNote(service.releaseStatus)
                  textFormat: Text.PlainText
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

            FutureReleases {
              id: futurePage
              visible: root.showingUpcoming
              anchors.fill: parent
              releases: service.upcomingReleases
              installed: service.installed
              versionUnknown: service.report && service.report.omarchy
                ? service.report.omarchy.versionUnknown === true : false
              isDev: service.report && service.report.omarchy
                ? service.report.omarchy.isDev === true : false
              loading: service.loading && !service.everLoaded
              status: service.releaseStatus
              foreground: root.foreground
              dim: root.dim
              faint: root.faint
              fontFamily: root.fontFamily
              onBack: root.showingUpcoming = false
            }

            FutureReleases {
              id: earlierPage
              visible: root.showingEarlier
              anchors.fill: parent
              releases: service.earlierReleases
              earlier: true
              boundary: service.earliestRecorded
              loading: service.loading && !service.everLoaded
              status: service.releaseStatus
              foreground: root.foreground
              dim: root.dim
              faint: root.faint
              fontFamily: root.fontFamily
              onBack: root.showingEarlier = false
            }

            // Cover only the main body while its matching payload is read.
            // The history menu and planet navigator stay visible and update
            // immediately, so moving between releases still feels direct.
            Rectangle {
              x: detailFlick.x
              width: detailFlick.width
              height: parent.height
              visible: root.initialLoading || root.detailLoading
              z: 20
              color: root.background

              Column {
                anchors.centerIn: parent
                spacing: Style.space(8)

                BusyIndicator {
                  anchors.horizontalCenter: parent.horizontalCenter
                  running: parent.parent.visible
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.initialLoading
                    ? "Reading flight log…" : "Loading update…"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

      }
    }
  }
}
