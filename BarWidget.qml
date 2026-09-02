import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar surface: a rocket that sits in the bar and goes accent-coloured
// when an update has landed, and a compact card answering "what changed,
// and does it matter?".
//
// Anything longer than the card — whole release notes, older updates — is
// the flight log's job, which this opens rather than duplicates.
Panel {
  id: root
  moduleName: "io.github.johnjkerr.astronoma"
  // The base Panel would claim `ipcTarget` for its own handler, which then
  // collides with the richer one registered below. Leaving it empty hands
  // the target to that handler cleanly.
  ipcTarget: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string visibility: setting("visibility", "always")
  readonly property int refreshIntervalSec: Math.max(60, Number(setting("refreshIntervalSec", 900)) || 900)

  // "always" is the default: the rocket behaves like every other bar widget,
  // sitting in the bar and going accent-coloured when an update is waiting.
  // It means always — not "whenever there is something to say" — because a
  // widget that silently removes itself reads as a broken install, which is
  // exactly how this looked before the default changed. The card explains an
  // empty state far better than an absent icon does.
  //
  // "unread" is the quieter option: the rocket appears when an update lands
  // and stands down once it has been read.
  readonly property bool shouldShow: {
    if (!service.everLoaded) return false
    if (visibility === "always") return true
    return service.hasUnread
  }

  readonly property var latest: service.latest
  readonly property string headline: latest
    ? Model.versionHeadline(latest.omarchy, service.installed)
    : (service.installed ? "Omarchy " + service.installed : "Omarchy")
  readonly property string whenText: latest ? "Updated " + Model.relativeDay(latest.startedAt) : ""
  readonly property var bullets: latest
    ? Model.highlights(latest.crossed || [], 4)
    : Model.highlights(service.recentReleases, 4)
  readonly property string statusNote: Model.statusNote(service.releaseStatus)
  readonly property bool hasSummary: !!(latest && latest.summary && latest.summary.text)
  property bool confirmingAgentEnable: false
  property string summaryError: ""

  function openFlightlog() {
    root.close()
    if (bar) bar.run("omarchy-shell shell toggle io.github.johnjkerr.astronoma '{}'")
  }

  function markRead() {
    if (service.hasUnread) service.markSeen(service.unreadId)
  }

  implicitWidth: shouldShow ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight
  visible: shouldShow

  onOpenedChanged: {
    if (!opened) return
    service.refresh(true)
    // Opening the card is what "reading" an update means.
    markRead()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    // Enough of each release to reach its first real section, but nowhere
    // near a whole release — the card only shows a few bullets.
    notesLimit: 4000
    onLoaded: {}
  }

  Component.onCompleted: service.refresh(false)

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    // Only the cheap local pass on a timer; the network refresh happens
    // when the card is actually opened.
    onTriggered: service.refresh(false)
  }

  IpcHandler {
    target: "astronoma.bar"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(true); return "ok" }
    function status(): string {
      return root.latest ? root.headline + " — " + root.whenText : "No captured updates"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontSize: Style.font.icon
    // Accent while unread, muted once read. An update landing is news, not a
    // fault, so this deliberately avoids the bar's urgent colour and leaves
    // red to mean what it means everywhere else here: the errors section,
    // which has its own claim on the reader's alarm.
    //
    // Muting the read state is also what makes a plain `Color.accent` safe.
    // Accent falls back to the same value as foreground on a theme that never
    // sets it, so accent-against-foreground could be two identical colours;
    // accent-against-muted separates either way — 2.78:1 unthemed, 1.78:1 on
    // a theme that sets both.
    active: service.hasUnread
    useActiveColor: true
    activeColor: Color.accent
    foreground: Color.muted
    tooltipText: root.latest ? root.headline : "Astronoma"
    onPressed: function(pressedButton) {
      if (pressedButton === Qt.RightButton) root.openFlightlog()
      else if (pressedButton === Qt.MiddleButton) service.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.openFlightlog()
      onTextKey: function(character) {
        // No summarise shortcut on purpose: it costs a real agent run, so
        // the button is the only way to start one.
        if (character === "f" || character === "F") root.openFlightlog()
        else if (character === "r" || character === "R") service.refresh(true)
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: root.headline
            meta: root.whenText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Rocket {
                foreground: Color.accent
                cellSize: Style.font.caption
              }
            }
          }

          // Nothing captured yet: say so plainly, and let the recent
          // releases below carry the panel.
          Text {
            visible: !root.latest
            width: parent.width
            text: service.everLoaded
              ? "No update has been captured on this machine yet. Here is what changed in Omarchy recently."
              : "Reading update history…"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { visible: !!root.latest; foreground: root.foreground }

          Column {
            visible: !!root.latest
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.latest ? Model.statLines(root.latest) : []
              StatLine {
                required property var modelData
                value: modelData.value
                label: modelData.label
                tone: modelData.tone
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }
          }

          // Errors are the one thing that must never be buried, so they
          // sit above the release notes rather than below them.
          Column {
            visible: !!root.latest && (root.latest.errors || []).length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "NEEDS ATTENTION"
              foreground: Color.urgent
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.latest ? (root.latest.errors || []).slice(0, 3) : []
              Text {
                required property var modelData
                width: column.width
                text: "• " + modelData
                textFormat: Text.PlainText
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }

          Column {
            visible: root.bullets.length > 0
            width: parent.width
            spacing: Style.space(5)

            PanelSectionHeader {
              text: root.latest ? "WHAT'S NEW" : "RECENT CHANGES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.bullets
              Text {
                required property var modelData
                width: column.width
                text: "• " + modelData
                textFormat: Text.PlainText
                color: Qt.darker(root.foreground, 1.2)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: root.statusNote !== ""
            width: parent.width
            text: root.statusNote
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

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

          // Present only when an agent is actually installed — the panel must
          // not advertise something this machine cannot do — and only while
          // pressing it would do something: produce a summary, or take the
          // consent needed to. Once one exists, reading it is what the flight
          // log button below already does, and a second button pointing at the
          // same place is just a duplicate link.
          Button {
            id: summariseAction
            visible: service.hasAgent && !!root.latest && !root.hasSummary
            width: parent.width
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            text: service.summaryRunning
              ? "Summarising…"
              : (!service.agentSummariesEnabled
                  ? (root.confirmingAgentEnable ? "Enable and summarise" : "Enable agent summaries")
                  : "Summarise what changed for me")
            enabled: !service.summaryRunning
            function trigger() {
              if (!visible || service.summaryRunning) return
              root.summaryError = ""
              if (!service.agentSummariesEnabled) {
                if (!root.confirmingAgentEnable) {
                  root.confirmingAgentEnable = true
                  return
                }
                service.summarise(root.latest ? root.latest.id : "", false, true)
                return
              }
              service.summarise(root.latest ? root.latest.id : "", false, false)
            }
            onClicked: trigger()
          }

          Text {
            visible: root.confirmingAgentEnable && !service.agentSummariesEnabled
            width: parent.width
            text: "This sends the update record and GitHub release notes to your installed agent. Agent tools are disabled and it runs from an empty temporary directory."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            text: service.historyRows.length > 1 ? "Flight log ›" : "Open flight log ›"
            onClicked: root.openFlightlog()
          }
        }
      }
    }
  }

  Connections {
    target: service
    function onSummaryFinished(payload) {
      if (payload && payload.ok) {
        // The card does not render summaries, so the flight log is where the
        // thing just produced can actually be read.
        root.confirmingAgentEnable = false
        root.summaryError = ""
        root.openFlightlog()
      } else {
        // Previously silent: a failed summarise closed nothing, showed
        // nothing, and left the button looking untouched.
        root.summaryError = payload && payload.error
          ? payload.error : "The agent did not return a summary"
      }
    }
  }
}
