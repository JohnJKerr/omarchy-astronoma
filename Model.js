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
  if (c.upgraded) lines.push({ value: c.upgraded, label: plural(c.upgraded, "package") + " upgraded", tone: "normal" })
  if (c.installed) lines.push({ value: c.installed, label: plural(c.installed, "package") + " installed", tone: "normal" })
  if (c.removed) lines.push({ value: c.removed, label: plural(c.removed, "package") + " removed", tone: "normal" })
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

// Qt renders Markdown natively, but GitHub release bodies carry noise that
// reads badly in a narrow panel: the credit suffix on every bullet, and
// bare issue URLs. Stripping them keeps the notes about the changes.
function cleanReleaseBody(body) {
  var text = String(body || "")
  text = text.replace(/\s+by\s+@([\w-]+)\s+in\s+(https:\/\/\S+|#\d+)/g, "")
  text = text.replace(/\*\*Full Changelog\*\*:\s*\S+/g, "")
  // The release name is already drawn as this section's heading, and an H1
  // inside a narrow panel dwarfs everything under it. Demote every heading
  // two levels so the notes keep their structure at a readable size.
  text = text.replace(/^(#{1,6})\s+/gm, function(match, hashes) {
    return "#".repeat(Math.min(6, hashes.length + 2)) + " "
  })
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
