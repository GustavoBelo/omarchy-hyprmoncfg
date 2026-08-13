function installCommand() {
  return "rm -f \"$XDG_RUNTIME_DIR/hyprmoncfg-panel-install.failed\"; status=0; omarchy pkg aur add hyprmoncfg && systemctl --user enable --now hyprmoncfgd.service && setsid -f gtk-launch hyprmoncfg-omarchy >/dev/null 2>&1 || status=$?; if (( status != 0 )); then printf '%s\\n' \"$status\" > \"$XDG_RUNTIME_DIR/hyprmoncfg-panel-install.failed\"; fi; (exit \"$status\")"
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

function layoutDisplays(monitors, screens) {
  var summaries = monitors instanceof Array ? monitors : []
  var enriched = summaries.filter(function(monitor) {
    return monitor && monitor.enabled !== false
      && Number(monitor.logical_width || 0) > 0
      && Number(monitor.logical_height || 0) > 0
  }).map(function(monitor) {
    return {
      name: String(monitor.name || "Display"),
      description: String(monitor.description || ""),
      make: String(monitor.make || ""),
      model: String(monitor.model || ""),
      mode: String(monitor.mode || ""),
      scale: Number(monitor.scale || 1),
      internal: monitor.internal === true,
      focused: monitor.focused === true,
      x: Number(monitor.x || 0),
      y: Number(monitor.y || 0),
      width: Number(monitor.logical_width),
      height: Number(monitor.logical_height)
    }
  })
  return enriched.length > 0 ? enriched : (screens || [])
}

function displayModelLabel(display, compact) {
  var monitor = display || {}
  var makeModel = compact === true
    ? String(monitor.model || "").trim()
    : (String(monitor.make || "") + " " + String(monitor.model || "")).trim()
  var label = makeModel || String(monitor.description || "").trim() || "Unknown display"
  return monitor.internal === true ? "Internal · " + label : label
}

function displayDetailLabel(display) {
  var monitor = display || {}
  var mode = String(monitor.mode || "").trim()
  var match = mode.match(/^(\d+)x(\d+)(?:@([\d.]+)Hz)?$/)
  var parts = []
  if (match) {
    parts.push(match[1] + "×" + match[2])
    if (match[3]) parts.push(Math.round(Number(match[3])) + " Hz")
  } else if (mode !== "") {
    parts.push(mode)
  }
  var scale = Number(monitor.scale || 1)
  if (!isFinite(scale) || scale <= 0) scale = 1
  parts.push(String(Math.round(scale * 100) / 100) + "x")
  return parts.join(" · ")
}

function layoutBounds(displays) {
  var list = displays || []
  if (list.length === 0) return { x: 0, y: 0, width: 1, height: 1 }

  var minX = Infinity
  var minY = Infinity
  var maxX = -Infinity
  var maxY = -Infinity
  for (var i = 0; i < list.length; i++) {
    var display = list[i] || {}
    var x = Number(display.x || 0)
    var y = Number(display.y || 0)
    var width = Math.max(1, Number(display.width || 1))
    var height = Math.max(1, Number(display.height || 1))
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

function layoutRect(display, bounds, canvasWidth, canvasHeight, padding) {
  var item = display || {}
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
    layoutDisplays: layoutDisplays,
    displayModelLabel: displayModelLabel,
    displayDetailLabel: displayDetailLabel,
    layoutBounds: layoutBounds,
    layoutRect: layoutRect,
    versionAtLeast: versionAtLeast
  }
}
