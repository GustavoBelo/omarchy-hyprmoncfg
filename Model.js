function installCommand() {
  return "omarchy pkg aur add hyprmoncfg && systemctl --user enable hyprmoncfgd && systemctl --user restart hyprmoncfgd"
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

function layoutBounds(screens) {
  var list = screens || []
  if (list.length === 0) return { x: 0, y: 0, width: 1, height: 1 }

  var minX = Infinity
  var minY = Infinity
  var maxX = -Infinity
  var maxY = -Infinity
  for (var i = 0; i < list.length; i++) {
    var screen = list[i] || {}
    var x = Number(screen.x || 0)
    var y = Number(screen.y || 0)
    var width = Math.max(1, Number(screen.width || 1))
    var height = Math.max(1, Number(screen.height || 1))
    minX = Math.min(minX, x)
    minY = Math.min(minY, y)
    maxX = Math.max(maxX, x + width)
    maxY = Math.max(maxY, y + height)
  }

  return {
    x: minX,
    y: minY,
    width: Math.max(1, maxX - minX),
    height: Math.max(1, maxY - minY)
  }
}

function layoutRect(screen, bounds, canvasWidth, canvasHeight, padding) {
  var item = screen || {}
  var area = bounds || layoutBounds([])
  var inset = Math.max(0, Number(padding || 0))
  var usableWidth = Math.max(1, Number(canvasWidth || 1) - inset * 2)
  var usableHeight = Math.max(1, Number(canvasHeight || 1) - inset * 2)
  var scale = Math.min(usableWidth / area.width, usableHeight / area.height)
  var contentWidth = area.width * scale
  var contentHeight = area.height * scale
  var offsetX = inset + (usableWidth - contentWidth) / 2
  var offsetY = inset + (usableHeight - contentHeight) / 2

  return {
    x: offsetX + (Number(item.x || 0) - area.x) * scale,
    y: offsetY + (Number(item.y || 0) - area.y) * scale,
    width: Math.max(1, Number(item.width || 1) * scale),
    height: Math.max(1, Number(item.height || 1) * scale)
  }
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
    layoutBounds: layoutBounds,
    layoutRect: layoutRect,
    versionAtLeast: versionAtLeast
  }
}
