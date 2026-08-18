const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Model = require("../Model.js")

test("installation uses Omarchy's presented AUR flow, restarts the daemon, and opens a centered TUI", () => {
  assert.deepEqual(Model.installProcessArgs(), [
    "omarchy",
    "launch",
    "floating",
    "terminal",
    "with",
    "presentation",
    "rm -f \"$XDG_RUNTIME_DIR/hyprmoncfg-panel-install.failed\" \"$XDG_RUNTIME_DIR/hyprmoncfg-panel-install.complete\"; status=0; omarchy pkg aur add hyprmoncfg && systemctl --user enable hyprmoncfgd.service && systemctl --user restart hyprmoncfgd.service && setsid -f gtk-launch hyprmoncfg-omarchy >/dev/null 2>&1 || status=$?; if (( status == 0 )); then : > \"$XDG_RUNTIME_DIR/hyprmoncfg-panel-install.complete\"; else printf '%s\\n' \"$status\" > \"$XDG_RUNTIME_DIR/hyprmoncfg-panel-install.failed\"; fi; (exit \"$status\")"
  ])
})

test("installation completion and failure are observable and cannot leave the panel spinning forever", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /hyprmoncfg-panel-install\.failed/)
  assert.match(qml, /hyprmoncfg-panel-install\.complete/)
  assert.match(qml, /id: installPreparationProcess/)
  assert.match(qml, /root\.installing && exitCode === 2/)
  assert.match(qml, /exitCode === 3 && root\.installing/)
  assert.match(qml, /id: installTimeout/)
  assert.match(qml, /interval: 300000/)
  assert.doesNotMatch(Model.installCommand(), /&\s*$/)
})

test("background installation probes keep the resolved update screen stable", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /property bool installationStateKnown: false/)
  assert.match(qml, /if \(!root\.installationStateKnown\) root\.checkingInstallation = true/)
  assert.match(qml, /if \(exitCode === 3 && root\.installing\) return/)
  assert.match(qml, /root\.installed = probedInstalled/)
  assert.ok(qml.indexOf("root.installed = probedInstalled") > qml.indexOf("if (root.installing && !probedCompatible)"))
})

test("missing hyprmoncfg gets a focused onboarding screen", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /Build layouts visually\./)
  assert.match(qml, /hyprmoncfg switches them on hotplug and lid events\./)
  assert.match(qml, /This panel puts the live layout, active profile, and automatic switching right here in Omarchy\./)
  assert.match(qml, /visible: root\.compatible \|\| root\.checkingInstallation/)
  assert.match(qml, /selected: !root\.installed/)
})

test("the layout editor delegates window behavior to the packaged desktop launcher", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /\["gtk-launch", "hyprmoncfg-omarchy"\]/)
  assert.doesNotMatch(qml, /TUI\.float/)
  assert.doesNotMatch(qml, /--app-id=hyprmoncfg/)
})

test("IPC envelopes require protocol version one", () => {
  assert.deepEqual(Model.parseEnvelope('{"type":"event","protocol_version":1,"event":"status"}'), {
    type: "event",
    protocol_version: 1,
    event: "status"
  })
  assert.equal(Model.parseEnvelope('{"type":"event","protocol_version":2}'), null)
  assert.equal(Model.parseEnvelope("nope"), null)
})

test("version compatibility accepts the IPC release and development builds", () => {
  assert.equal(Model.versionAtLeast("hyprmoncfg 1.12.0 (abc)", "1.12.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg v1.12.3", "1.12.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg dev", "1.12.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg 1.11.1", "1.12.0"), false)
  assert.equal(Model.versionAtLeast("not installed", "1.12.0"), false)
})

test("layout display data comes from daemon status and matches TUI labels", () => {
  const displays = Model.layoutDisplays([{
    name: "eDP-1",
    description: "Samsung Display Corp. ATNA60CL10-0",
    make: "Samsung Display Corp.",
    model: "ATNA60CL10-0",
    mode: "2880x1800@120.00Hz",
    scale: 1.5,
    internal: true,
    focused: true,
    enabled: true,
    x: 3840,
    y: 0,
    logical_width: 1920,
    logical_height: 1200
  }], [{ name: "fallback" }])

  assert.equal(displays.length, 1)
  assert.equal(Model.displayModelLabel(displays[0]), "Internal · Samsung Display Corp. ATNA60CL10-0")
  assert.equal(Model.displayModelLabel(displays[0], true), "Internal · ATNA60CL10-0")
  assert.equal(Model.displayDetailLabel(displays[0]), "2880×1800 · 120 Hz · 1.5x")
})

test("layout preview preserves relative placement", () => {
  const bounds = Model.layoutBounds([
    { x: 0, y: 0, width: 200, height: 100 },
    { x: 200, y: 50, width: 100, height: 100 }
  ])
  const left = Model.layoutRect({ x: 0, y: 0, width: 200, height: 100 }, bounds, 330, 140, 10)
  const right = Model.layoutRect({ x: 200, y: 50, width: 100, height: 100 }, bounds, 330, 140, 10)

  assert.equal(left.x, 45)
  assert.equal(left.width, 160)
  assert.equal(right.x, 205)
  assert.equal(right.y, 50)
})

test("bar icon stays legible through transient daemon restarts", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "BarWidget.qml"), "utf8")
  assert.doesNotMatch(qml, /text: "H"/)
  assert.doesNotMatch(qml, /slotSize: Style\.bar\.statusSlot/)
  assert.match(qml, /text: root\.monitorCount > 1 \? "󰍺" : "󰍹"/)
  assert.match(qml, /dimmed: root\.barIconDimmed/)
  assert.doesNotMatch(qml, /dimmed: !root\.backendConnected/)
  assert.match(qml, /id: barDisplayGlyph/)
  assert.match(qml, /visible: root\.backendConnected/)
  assert.match(qml, /text: "󰄬"/)
  assert.match(qml, /color: Color\.accent/)
})

test("the update call to action uses a plain refresh icon", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /text: root\.installed \? "\\uf021"/)
  assert.match(qml, /iconText: root\.installed \? "\\uf021"/)
  assert.match(qml, /visible: !root\.installed/)
  assert.match(qml, /selected: !root\.installed/)
})

test("the panel header uses the clear managed check at hero scale", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /id: heroDisplayGlyph/)
  assert.match(qml, /visible: root\.backendConnected/)
  assert.match(qml, /text: "󰄬"/)
  assert.match(qml, /color: Color\.accent/)
})

test("the panel treats the user service as the management boundary", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /text: "MONITOR MANAGEMENT"/)
  assert.match(qml, /label: "Managed by hyprmoncfg"/)
  assert.match(qml, /Automatic switching on monitor hotplug and lid events/)
  assert.match(qml, /\["systemctl", "--user", "enable", "--now", "hyprmoncfgd\.service"\]/)
  assert.match(qml, /\["systemctl", "--user", "disable", "--now", "hyprmoncfgd\.service"\]/)
  assert.match(qml, /\["systemctl", "--user", "is-enabled", "--quiet", "hyprmoncfgd\.service"\]/)
  assert.match(qml, /\["systemctl", "--user", "is-active", "--quiet", "hyprmoncfgd\.service"\]/)
  assert.doesNotMatch(qml, /set_automation/)
  assert.doesNotMatch(qml, /automaticSwitching/)
  assert.doesNotMatch(qml, /settings\.json/)
  assert.match(qml, /serviceActionPending && !serviceProcess\.running/)
  assert.match(qml, /root\.serviceTargetManaged\s*\? \(root\.serviceEnabled && root\.serviceActive\)/)
})

test("each monitor discovers management started from another panel", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /id: serviceDiscoveryTimer/)
  assert.match(qml, /interval: 2000/)
  assert.match(qml, /running: root\.compatible && !root\.backendConnected && !root\.serviceActionPending/)
  assert.match(qml, /onTriggered: root\.checkServiceState\(\)/)
})

test("the managed panel leads with the live layout", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /Style\.space\(560\)/)
  assert.match(qml, /ScrollView \{/)
  assert.ok(qml.indexOf('text: "LAYOUT AND SETTINGS"') < qml.indexOf('text: "PROFILE"'))
  assert.match(qml, /id: layoutCanvas/)
  assert.match(qml, /Model\.displayModelLabel\(modelData, parent\.parent\.compactCard\)/)
  assert.match(qml, /Model\.displayDetailLabel\(modelData\)/)
  assert.match(qml, /onClicked: root\.launchTui\(\)/)
  assert.match(qml, /text: "PROFILE"/)
  assert.match(qml, /centerOnBar: false/)
  assert.doesNotMatch(qml, /ProfileRow/)
  assert.doesNotMatch(qml, /match_score/)
})

test("the active profile is informational rather than a button", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /Item \{\s+id: profileInfo/)
  assert.doesNotMatch(qml, /current: root\.displayedProfile/)
})

test("layout and settings stays live when management is off", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /root\.backendConnected \? monitorSummaries : \[\]/)
  assert.match(qml, /Quickshell\.screens \|\| \[\]/)
  assert.match(qml, /else root\.launchTui\(\)/)
  assert.match(qml, /hasCursor: root\.cursorActive && root\.cursorIndex === \(root\.serviceBroken \? 2 : 1\)/)
})

test("the profile explains the unmanaged state", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /if \(!root\.managedChecked\) return "Not managed by hyprmoncfg"/)
  assert.match(qml, /if \(!root\.managedChecked\) return "Turn on management for automatic profiles"/)
})

test("the active profile falls back to the daemon recommendation while switching, and says so", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /displayedProfile: activeProfile !== "" \? activeProfile : recommendedProfile/)
  assert.match(qml, /if \(displayedProfile !== ""\) return displayedProfile/)
  // A recommendation must never read like a profile that is already applied.
  assert.match(qml, /if \(activeProfile !== ""\) return displays \+ " · Active"/)
  assert.match(qml, /if \(recommendedProfile !== ""\) return displays \+ " · Best match, not active"/)
})

test("the layout draws only displays that own their image and names the rest", () => {
  const monitors = [
    { name: "DP-1", enabled: true, x: 0, y: 0, logical_width: 2880, logical_height: 1620 },
    { name: "HDMI-A-1", enabled: true, mirror_of: "DP-1", x: 0, y: 0, logical_width: 2560, logical_height: 1440 },
    { name: "eDP-1", enabled: false, x: 0, y: 1620, logical_width: 1920, logical_height: 1200 }
  ]

  const displays = Model.layoutDisplays(monitors, [{ name: "fallback" }])
  assert.deepEqual(displays.map(function(display) { return display.name }), ["DP-1"])
  assert.equal(Model.hiddenDisplays(monitors), "Off: eDP-1   Mirrored: HDMI-A-1 → DP-1")
  assert.equal(Model.hiddenDisplays([monitors[0]]), "")

  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /id: hiddenDisplaysLabel/)
  assert.match(qml, /visible: root\.hiddenDisplays !== ""/)
})

test("the panel waits for daemon status before calling a layout custom", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /property bool documentReady: false/)
  assert.match(qml, /if \(!root\.documentReady\) return root\.serviceActionPending \? "Starting hyprmoncfg…" : "Loading profile…"/)
  assert.match(qml, /root\.documentReady = true/)
})

test("an enabled service without IPC is a recoverable failure", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /readonly property bool serviceBroken:/)
  assert.match(qml, /title: "Restart hyprmoncfg"/)
  assert.match(qml, /\["systemctl", "--user", "restart", "hyprmoncfgd\.service"\]/)
})
