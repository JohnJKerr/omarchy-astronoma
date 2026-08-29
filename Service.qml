import QtQuick
import Quickshell.Io

// Runs the `astronoma` helper and holds the result.
//
// Everything that reads the machine happens in the helper; this only
// decides when to ask and keeps the last good answer. The last good answer
// matters: a refresh that fails must leave the panel showing what it had
// rather than blanking it.
Item {
  id: root

  // Absolute path to this plugin's directory, so the bundled helper is
  // found wherever the plugin was installed.
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string helper: pluginDir + "/bin/astronoma"

  // Release bodies run to tens of thousands of characters. The bar popup
  // shows a few bullets, so it asks for a truncated payload; the flight
  // log renders whole releases and asks for all of it.
  property int notesLimit: 0

  property var report: ({})
  property bool loading: false
  property bool everLoaded: false
  property string lastError: ""

  readonly property var latest: report && report.latest ? report.latest : null
  readonly property var historyRows: report && report.history ? report.history : []
  readonly property var recentReleases: report && report.releases ? (report.releases.recent || []) : []
  readonly property var releaseStatus: report && report.releases ? (report.releases.status || ({})) : ({})
  readonly property var agents: report && report.agents ? report.agents : []
  readonly property bool hasAgent: agents.length > 0
  readonly property bool agentSummariesEnabled: report && report.agentSummariesEnabled === true
  readonly property string installed: report && report.omarchy ? (report.omarchy.installed || "") : ""
  readonly property string unreadId: report && report.unread ? String(report.unread) : ""
  readonly property bool hasUnread: unreadId !== ""
  // Something worth putting in front of the user: a captured update, or
  // failing that, release notes we can still show.
  readonly property bool hasAnything: !!latest || recentReleases.length > 0

  signal loaded()
  signal summaryFinished(var payload)

  // Set while a refresh is dropped because one was already in flight, so the
  // request can be honoured on the way out. Opening the panel during the
  // background timer's tick used to lose exactly the refresh the user asked
  // for, leaving the network fetch until the next tick.
  property bool refreshQueued: false
  property bool queuedWantsReleases: false

  function refresh(refreshReleases) {
    if (reportProcess.running) {
      refreshQueued = true
      queuedWantsReleases = queuedWantsReleases || refreshReleases === true
      return
    }
    lastError = ""
    loading = true
    var argv = [helper, "report"]
    if (refreshReleases) argv.push("--refresh")
    if (notesLimit > 0) { argv.push("--notes-limit"); argv.push(String(notesLimit)) }
    reportProcess.command = argv
    reportProcess.running = true
  }

  function runQueuedRefresh() {
    if (!refreshQueued) return
    var wanted = queuedWantsReleases
    refreshQueued = false
    queuedWantsReleases = false
    Qt.callLater(function() { root.refresh(wanted) })
  }

  function markSeen(id) {
    if (seenProcess.running) return
    seenProcess.command = id ? [helper, "seen", String(id)] : [helper, "seen"]
    seenProcess.running = true
  }

  function summarise(id, refresh, enable) {
    if (summaryProcess.running) return
    summaryRunning = true
    var argv = [helper, "summarise"]
    if (id) argv.push(String(id))
    if (refresh) argv.push("--refresh")
    if (enable) argv.push("--enable")
    summaryProcess.command = argv
    summaryProcess.running = true
  }

  property bool summaryRunning: false

  function applyReport(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      lastError = "Could not read the update report"
      return
    }
    if (!parsed || typeof parsed !== "object") {
      lastError = "Could not read the update report"
      return
    }
    report = parsed
    everLoaded = true
    root.loaded()
  }

  Process {
    id: reportProcess
    running: false
    command: []
    stdout: StdioCollector { id: reportOut; waitForEnd: true }
    stderr: StdioCollector { id: reportErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) root.applyReport(String(reportOut.text || ""))
      else {
        var detail = String(reportErr.text || "").split("\n").filter(function(l) { return l !== "" })
        root.lastError = detail.length ? detail[detail.length - 1].substring(0, 200)
                                       : "astronoma exited with " + exitCode
      }
      root.runQueuedRefresh()
    }
  }

  Process {
    id: seenProcess
    running: false
    command: []
    // Re-read so the bar drops its unread state as soon as it is recorded.
    onExited: root.refresh(false)
  }

  Process {
    id: summaryProcess
    running: false
    command: []
    stdout: StdioCollector { id: summaryOut; waitForEnd: true }
    stderr: StdioCollector { id: summaryErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.summaryRunning = false
      var payload = null
      try {
        payload = JSON.parse(String(summaryOut.text || ""))
      } catch (error) {
        payload = null
      }
      if (!payload) {
        var detail = String(summaryErr.text || "").split("\n").filter(function(l) { return l !== "" })
        payload = {
          ok: false,
          error: detail.length ? detail[detail.length - 1].substring(0, 200)
                               : "The agent did not return a summary"
        }
      }
      root.summaryFinished(payload)
      // Fold a successful summary back into the report so reopening the
      // panel shows it without another agent run.
      if (payload.ok) root.refresh(false)
    }
  }
}
