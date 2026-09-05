.pragma library

// Formatting shared by the bar popup and the flight log. Pure functions
// over the helper's JSON so both surfaces phrase the same update the same
// way.

function pad(value) {
  return value < 10 ? "0" + value : String(value)
}

function parseDate(iso) {
  if (!iso) return null
  var date = new Date(String(iso))
  return isNaN(date.getTime()) ? null : date
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// "28 Aug" — the history list's leading column.
function shortDate(iso) {
  var date = parseDate(iso)
  if (!date) return ""
  return pad(date.getDate()) + " " + MONTHS[date.getMonth()]
}

function longDate(iso) {
  var date = parseDate(iso)
  if (!date) return ""
  return date.getDate() + " " + MONTHS[date.getMonth()] + " " + date.getFullYear()
    + " at " + pad(date.getHours()) + ":" + pad(date.getMinutes())
}

// "Updated yesterday" reads better than a date for the most recent update,
// which is the one the user is usually asking about.
function relativeDay(iso) {
  var date = parseDate(iso)
  if (!date) return ""
  var startOfDay = function(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() }
  var days = Math.round((startOfDay(new Date()) - startOfDay(date)) / 86400000)
  if (days <= 0) return "today"
  if (days === 1) return "yesterday"
  if (days < 7) return days + " days ago"
  if (days < 14) return "last week"
  if (days < 60) return Math.round(days / 7) + " weeks ago"
  return "on " + shortDate(iso)
}

function plural(count, singular, pluralForm) {
  return count === 1 ? singular : (pluralForm || singular + "s")
}

// The release's semantic shape chooses both the planet artwork and scale:
// x.0.0 is major, x.y.0 is minor, and x.y.z is patch.
function planetKind(release) {
  var version = String((release && (release.version || release.tag)) || "")
  var match = version.match(/v?(\d+)\.(\d+)\.(\d+)/i)
  if (!match) return 0
  if (Number(match[3]) !== 0) return 0
  if (Number(match[2]) !== 0) return 1
  return 2
}

// "Omarchy 4.0.0 → 4.0.1", or an honest alternative when a version is
// unknown or the update never touched Omarchy itself.
function versionHeadline(omarchy, installed) {
  var from = omarchy && omarchy.from ? omarchy.from : null
  var to = omarchy && omarchy.to ? omarchy.to : null
  if (from && to && from !== to) return "Omarchy " + from + " → " + to
  if (to) return "Omarchy " + to
  if (installed) return "Omarchy " + installed
  return "Omarchy"
}

function counts(record) {
  var packages = (record && record.packages) || {}
  var count = function(key) { return (packages[key] || []).length }
  return {
    upgraded: count("upgraded"),
    installed: count("installed"),
    removed: count("removed"),
    // A cross-cutting subset of the three above rather than a fourth total:
    // an AUR package is still upgraded or installed like any other.
    aur: ((record && record.aur) || []).length,
    migrations: ((record && record.migrations) || []).length,
    errors: ((record && record.errors) || []).length,
    warnings: ((record && record.warnings) || []).length,
    releases: ((record && record.crossed) || []).length
  }
}

// The stat lines under the headline. Zero-valued rows are dropped, except
// errors, which are worth stating as zero because their absence is the
// reassurance the user is looking for.
function statLines(record) {
  var c = counts(record)
  var lines = []
  if (c.releases) lines.push({ value: c.releases, label: "Omarchy " + plural(c.releases, "release"), tone: "accent" })
  if (c.upgraded) lines.push({ value: c.upgraded, label: plural(c.upgraded, "package") + " upgraded", tone: "normal", group: "upgraded" })
  if (c.installed) lines.push({ value: c.installed, label: plural(c.installed, "package") + " installed", tone: "normal", group: "installed" })
  if (c.removed) lines.push({ value: c.removed, label: plural(c.removed, "package") + " removed", tone: "normal", group: "removed" })
  if (c.aur) lines.push({ value: c.aur, label: "from the AUR", tone: "normal", group: "aur" })
  if (c.migrations) lines.push({ value: c.migrations, label: plural(c.migrations, "migration"), tone: "normal" })
  if (c.warnings) lines.push({ value: c.warnings, label: plural(c.warnings, "warning"), tone: "warn" })
  lines.push({ value: c.errors, label: plural(c.errors, "error"), tone: c.errors ? "urgent" : "muted" })
  return lines
}

function packageLabel(item) {
  if (!item) return ""
  if (item.from && item.to) return item.name + "  " + item.from + " → " + item.to
  return item.name + (item.to || item.from ? "  " + (item.to || item.from) : "")
}

// Pull the headline bullets out of a release body for the compact popup,
// which has room for a handful of lines rather than a whole release.
//
// Omarchy releases open with install boilerplate — the ISO link and its
// checksum — before the first "## Security" / "## Fixes" heading. Those
// bullets are the first in the file and the least interesting, so
// collection only starts once a section heading has been passed.
function highlights(releases, limit) {
  var out = []
  var max = limit || 4
  for (var i = 0; i < releases.length && out.length < max; i++) {
    var body = String((releases[i] && releases[i].body) || "")
    var lines = body.split("\n")
    var inSection = false
    for (var j = 0; j < lines.length && out.length < max; j++) {
      var line = lines[j].replace(/^\s+|\s+$/g, "")
      if (/^#{2,}\s+/.test(line)) { inSection = true; continue }
      if (!inSection || !/^[*-]\s+/.test(line)) continue
      var text = line.replace(/^[*-]\s+/, "")
      text = text.replace(/\s+by\s+@[\w-]+\s+in\s+#\d+\s*$/, "")   // trailing credit
      text = text.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")          // markdown links
      text = text.replace(/[`*_]/g, "")
      if (isBoilerplate(text)) continue
      if (text.length > 2) out.push(text)
    }
  }
  return out
}

// Release metadata that says nothing about what changed.
function isBoilerplate(text) {
  if (/^(download|sha256|checksum|torrent)\b/i.test(text)) return true
  // A line that is essentially just a URL.
  return /^https?:\/\/\S+$/.test(text)
}

// Remote release notes and model output are rendered as inert plain text.
// Preserve their useful structure while removing Markdown control syntax.
function cleanPlainText(text) {
  var out = String(text || "")

  out = out.replace(/```[^\n]*\n([\s\S]*?)```/g, function(match, body) {
    return String(body).replace(/\n+$/, "")
  })
  out = out.replace(/``([^`]+)``/g, "$1")
  out = out.replace(/`([^`\n]+)`/g, "$1")
  out = out.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
  out = out.replace(/^#{1,6}\s+/gm, "")
  out = out.replace(/\*\*([^*]+)\*\*/g, "$1")
  return out
}

// GitHub release bodies carry credit suffixes and changelog links that read
// badly in a narrow panel. Strip them before the remaining plain-text pass.
function cleanReleaseBody(body) {
  var text = String(body || "")
  text = text.replace(/\s+by\s+@([\w-]+)\s+in\s+(https:\/\/\S+|#\d+)/g, "")
  text = text.replace(/\*\*Full Changelog\*\*:\s*\S+/g, "")
  text = cleanPlainText(text)
  return text.replace(/\n{3,}/g, "\n\n").replace(/^\s+|\s+$/g, "")
}

function releaseHeading(release) {
  if (!release) return ""
  var name = String(release.name || release.tag || "")
  var version = String(release.version || "")
  // Most Omarchy releases name themselves "v4.0.1", which would read twice.
  if (name === release.tag || name === "v" + version) return "Omarchy " + version
  return "Omarchy " + version + " — " + name
}

function statusNote(status) {
  if (!status) return ""
  if (status.error) return status.error
  if (status.stale) return "Showing cached release notes"
  return ""
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function boundedText(value, limit, optional) {
  return (optional && (value === null || value === undefined))
    || (typeof value === "string" && value.length <= limit)
}

function validChange(value) {
  return isObject(value)
    && boundedText(value.name, 1024, false)
    && ["upgraded", "installed", "removed"].indexOf(value.action) >= 0
    && boundedText(value.from, 1024, true)
    && boundedText(value.to, 1024, true)
    && (value.aur === undefined || typeof value.aur === "boolean")
}

function validChanges(value) {
  return Array.isArray(value) && value.length <= 5000 && value.every(validChange)
}

function validRecord(value, expectedId) {
  if (!isObject(value) || value.schema !== 1 || !boundedText(value.id, 32, false)) return false
  if (expectedId && value.id !== String(expectedId)) return false
  if (!isObject(value.omarchy) || !isObject(value.packages)) return false
  if (!boundedText(value.startedAt, 1024, false)
      || !boundedText(value.finishedAt, 1024, false)
      || !boundedText(value.omarchy.from, 1024, true)
      || !boundedText(value.omarchy.to, 1024, true)
      || typeof value.omarchy.changed !== "boolean") return false
  if (!["upgraded", "installed", "removed"].every(function(key) {
    return validChanges(value.packages[key])
  })) return false
  if (!validChanges(value.aur) || !Array.isArray(value.migrations)
      || !Array.isArray(value.warnings) || !Array.isArray(value.errors)) return false
  if (value.migrations.length > 1000 || value.warnings.length > 1000
      || value.errors.length > 1000) return false
  if (["failed", "aurSkipped", "partial"].some(function(key) {
    return typeof value[key] !== "boolean"
  }) || !isObject(value.sources)) return false
  return value.migrations.every(function(item) { return boundedText(item, 65536, false) })
    && value.warnings.every(function(item) { return boundedText(item, 65536, false) })
    && value.errors.every(function(item) { return boundedText(item, 65536, false) })
}

function validRelease(value) {
  return isObject(value)
    && boundedText(value.tag, 2048, false)
    && boundedText(value.version, 2048, false)
    && boundedText(value.name, 2048, false)
    && boundedText(value.publishedAt, 2048, false)
    && boundedText(value.body, 262144, false)
    && boundedText(value.url, 2048, false)
}

function validReleases(value) {
  return Array.isArray(value) && value.length <= 30 && value.every(validRelease)
}

function validAgent(value) {
  return isObject(value) && boundedText(value.key, 32, false)
    && boundedText(value.name, 80, false) && boundedText(value.command, 128, false)
}

function validHistoryRow(value) {
  return isObject(value) && boundedText(value.id, 32, false)
    && boundedText(value.at, 1024, false) && isObject(value.omarchy)
    && isObject(value.counts) && typeof value.packageTotal === "number"
    && typeof value.migrations === "number" && typeof value.errors === "number"
    && typeof value.warnings === "number" && typeof value.partial === "boolean"
}

function validSummary(value) {
  return value === null || value === undefined || (isObject(value) && value.ok === true
    && boundedText(value.id, 32, false) && boundedText(value.agent, 32, false)
    && boundedText(value.agentName, 80, false)
    && typeof value.evidenceHash === "string" && /^[0-9a-f]{64}$/.test(value.evidenceHash)
    && boundedText(value.text, 131072, false))
}

function validReport(value) {
  if (!isObject(value) || value.schema !== 1 || !isObject(value.plugin)
      || !isObject(value.omarchy) || !isObject(value.releases)) return false
  if (!boundedText(value.plugin.version, 32, false)
      || !boundedText(value.omarchy.installed, 128, true)
      || !boundedText(value.omarchy.installedRaw, 128, true)
      || typeof value.omarchy.isDev !== "boolean"
      || typeof value.omarchy.versionUnknown !== "boolean") return false
  if (!Array.isArray(value.history) || value.history.length > 4096
      || !Array.isArray(value.agents) || value.agents.length > 8) return false
  if (!value.history.every(validHistoryRow) || !value.agents.every(validAgent)) return false
  if (!validReleases(value.releases.recent)
      || !validReleases(value.releases.upcoming)
      || !validReleases(value.releases.earlier)) return false
  if (value.latest !== null && value.latest !== undefined && !validRecord(value.latest)) return false
  if (!boundedText(value.unread, 32, true)
      || (value.selectedAgent !== null && value.selectedAgent !== undefined
          && !validAgent(value.selectedAgent))
      || typeof value.agentSelectionMissing !== "boolean"
      || typeof value.agentSummariesEnabled !== "boolean") return false
  if (value.latest && (!validReleases(value.latest.crossed)
                       || !validSummary(value.latest.summary))) return false
  return boundedText(value.captureError, 200, true)
    && boundedText(value.historyError, 200, true)
}

function validDetail(value, expectedId) {
  return isObject(value) && value.ok === true && validRecord(value, expectedId)
    && validReleases(value.crossed)
    && validSummary(value.summary)
    && Array.isArray(value.agents) && value.agents.length <= 8
    && value.agents.every(validAgent)
}
