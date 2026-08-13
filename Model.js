function installCommand() {
  return "omarchy pkg aur add hyprmoncfg && systemctl --user enable --now hyprmoncfgd"
}

function installProcessArgs() {
  return [
    "omarchy",
    "launch",
    "floating",
    "terminal",
    "with",
    "presentation",
    installCommand()
  ]
}

function parseEnvelope(raw) {
  try {
    var value = JSON.parse(String(raw || ""))
    if (!value || typeof value !== "object") return null
    if (value.protocol_version !== 1) return null
    if (value.type !== "response" && value.type !== "event") return null
    return value
  } catch (e) {
    return null
  }
}

function profileSummary(profile) {
  if (!profile) return ""
  var enabled = Number(profile.enabled_outputs || 0)
  var total = Number(profile.output_count || 0)
  var displays = enabled === 1 ? "display" : "displays"
  if (enabled === total || total === 0) return enabled + " " + displays
  return enabled + " of " + total + " displays"
}

function secondsRemaining(deadline, now) {
  var end = Date.parse(String(deadline || ""))
  var current = now === undefined ? Date.now() : Number(now)
  if (!isFinite(end) || !isFinite(current)) return 0
  return Math.max(0, Math.ceil((end - current) / 1000))
}

function versionAtLeast(output, minimum) {
  var text = String(output || "")
  if (/\bdev\b/.test(text)) return true

  function parts(value) {
    var match = String(value || "").match(/v?(\d+)\.(\d+)\.(\d+)/)
    return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null
  }

  var current = parts(text)
  var wanted = parts(minimum)
  if (!current || !wanted) return false
  for (var i = 0; i < 3; i++) {
    if (current[i] > wanted[i]) return true
    if (current[i] < wanted[i]) return false
  }
  return true
}

if (typeof module !== "undefined") {
  module.exports = {
    installCommand: installCommand,
    installProcessArgs: installProcessArgs,
    parseEnvelope: parseEnvelope,
    profileSummary: profileSummary,
    secondsRemaining: secondsRemaining,
    versionAtLeast: versionAtLeast
  }
}
