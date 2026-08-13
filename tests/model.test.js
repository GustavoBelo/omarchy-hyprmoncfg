const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Model = require("../Model.js")

test("installation uses Omarchy's presented AUR flow and enables the daemon", () => {
  assert.deepEqual(Model.installProcessArgs(), [
    "omarchy",
    "launch",
    "floating",
    "terminal",
    "with",
    "presentation",
    "omarchy pkg aur add hyprmoncfg && systemctl --user enable hyprmoncfgd && systemctl --user restart hyprmoncfgd"
  ])
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

test("profile summaries stay compact", () => {
  assert.equal(Model.profileSummary({ enabled_outputs: 1, output_count: 1 }), "1 display")
  assert.equal(Model.profileSummary({ enabled_outputs: 2, output_count: 3 }), "2 of 3 displays")
})

test("confirmation countdown rounds up and clamps at zero", () => {
  const deadline = "2026-08-13T12:00:10.000Z"
  assert.equal(Model.secondsRemaining(deadline, Date.parse("2026-08-13T12:00:00.250Z")), 10)
  assert.equal(Model.secondsRemaining(deadline, Date.parse("2026-08-13T12:00:11.000Z")), 0)
})

test("layout bounds contain offset displays", () => {
  assert.deepEqual(Model.layoutBounds([
    { x: 0, y: 0, width: 2880, height: 1620 },
    { x: 2887, y: 546, width: 1728, height: 1080 }
  ]), {
    x: 0,
    y: 0,
    width: 4615,
    height: 1626
  })
})

test("layout preview preserves relative placement and centers the group", () => {
  const bounds = Model.layoutBounds([
    { x: 0, y: 0, width: 200, height: 100 },
    { x: 200, y: 50, width: 100, height: 100 }
  ])
  const left = Model.layoutRect({ x: 0, y: 0, width: 200, height: 100 }, bounds, 330, 140, 10)
  const right = Model.layoutRect({ x: 200, y: 50, width: 100, height: 100 }, bounds, 330, 140, 10)

  assert.equal(left.x, 45)
  assert.equal(left.y, 10)
  assert.equal(left.width, 160)
  assert.equal(left.height, 80)
  assert.equal(right.x, 205)
  assert.equal(right.y, 50)
  assert.equal(right.width, 80)
  assert.equal(right.height, 80)
})

test("version compatibility accepts the IPC release and development builds", () => {
  assert.equal(Model.versionAtLeast("hyprmoncfg 1.11.0 (abc)", "1.11.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg v1.12.3", "1.11.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg dev", "1.11.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg 1.10.1", "1.11.0"), false)
  assert.equal(Model.versionAtLeast("not installed", "1.11.0"), false)
})

test("bar icon follows Omarchy's display glyph with a quiet automatic-state mark", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "BarWidget.qml"), "utf8")
  assert.match(qml, /󰍹/)
  assert.match(qml, /󰍺/)
  assert.doesNotMatch(qml, /text: "H"/)
  assert.match(qml, /visible: root\.backendConnected/)
})
