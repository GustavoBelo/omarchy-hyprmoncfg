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
    "omarchy pkg aur add hyprmoncfg && systemctl --user enable --now hyprmoncfgd"
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

test("version compatibility accepts the IPC release and development builds", () => {
  assert.equal(Model.versionAtLeast("hyprmoncfg 1.11.0 (abc)", "1.11.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg v1.12.3", "1.11.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg dev", "1.11.0"), true)
  assert.equal(Model.versionAtLeast("hyprmoncfg 1.10.1", "1.11.0"), false)
  assert.equal(Model.versionAtLeast("not installed", "1.11.0"), false)
})

test("bar icon follows Omarchy's display glyph with an H badge", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "BarWidget.qml"), "utf8")
  assert.match(qml, /󰍹/)
  assert.match(qml, /󰍺/)
  assert.match(qml, /text: "H"/)
})
