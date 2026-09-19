import QtQuick
import Quickshell.Io

// A helper process whose output and lifetime are bounded while it runs.
Item {
  id: root

  property int maxStdoutChars: 16 * 1024 * 1024
  property int maxStderrChars: 64 * 1024
  // The Python supervisor gets 30 seconds and then needs time to terminate
  // its whole process group. Keep this outer deadline beyond that cleanup.
  property int deadlineMs: 35000
  readonly property bool running: process.running
  property string stdoutText: ""
  property string stderrText: ""
  property string failure: ""

  signal finished(int exitCode, string failure)

  function start(argv) {
    if (process.running) return false
    stdoutText = ""
    stderrText = ""
    failure = ""
    process.command = argv
    process.running = true
    return true
  }

  function append(chunk, stdout) {
    var value = String(chunk || "") + "\n"
    var current = stdout ? stdoutText : stderrText
    var limit = stdout ? maxStdoutChars : maxStderrChars
    if (current.length + value.length > limit) {
      failure = "output-limit"
      process.running = false
      return
    }
    if (stdout) stdoutText = current + value
    else stderrText = current + value
  }

  Timer {
    interval: root.deadlineMs
    running: process.running
    onTriggered: {
      root.failure = "timeout"
      process.running = false
    }
  }

  Process {
    id: process
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.append(data, true) } }
    stderr: SplitParser { onRead: function(data) { root.append(data, false) } }
    onExited: function(exitCode) { root.finished(exitCode, root.failure) }
  }
}
