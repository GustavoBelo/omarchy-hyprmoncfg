import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "crmne.hyprmoncfg"
  ipcTarget: "crmne.hyprmoncfg"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property bool installed: false
  property bool compatible: false
  property bool checkingInstallation: true
  property bool installing: false
  property bool backendConnected: backendSocket.connected
  property var document: ({ profiles: [], monitors: [], daemon: { running: false } })
  property string lastError: ""
  property int requestSequence: 0
  property var pendingMethods: ({})
  property string pendingTransaction: ""
  property string pendingProfile: ""
  property string pendingDeadline: ""
  property int pendingSeconds: 0
  property bool applying: false
  property bool transactionActionPending: false
  property bool overwritePrompt: false
  property string overwriteProfile: ""
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property var profiles: document && document.profiles instanceof Array ? document.profiles : []
  readonly property int monitorCount: document && document.monitors instanceof Array ? document.monitors.length : Quickshell.screens.length
  readonly property string activeProfile: document && document.active_profile ? String(document.active_profile.name || "") : ""
  readonly property string socketPath: String(Quickshell.env("XDG_RUNTIME_DIR") || "") + "/hyprmoncfgd.sock"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
    root.cursorActive = false
    root.cursorIndex = 0
    root.checkInstallation()
    if (root.compatible) root.connectBackend()
  }

  function openFromHotkey() { root.open() }

  function close() { root.controller.hide() }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function checkInstallation() {
    if (whichProcess.running) return
    root.checkingInstallation = true
    whichProcess.command = ["sh", "-c", "command -v hyprmoncfg >/dev/null 2>&1 && hyprmoncfg version"]
    whichProcess.running = true
  }

  function install() {
    root.installing = true
    root.lastError = ""
    installerProcess.command = Model.installProcessArgs()
    installerProcess.startDetached()
    installPoll.restart()
  }

  function startDaemon() {
    if (daemonProcess.running) return
    root.lastError = ""
    daemonProcess.command = ["systemctl", "--user", "enable", "--now", "hyprmoncfgd.service"]
    daemonProcess.running = true
  }

  function launchTui() {
    tuiProcess.command = ["omarchy", "launch", "tui", "--app-id=hyprmoncfg", "hyprmoncfg"]
    tuiProcess.startDetached()
    root.close()
  }

  function connectBackend() {
    if (!root.compatible || backendSocket.connected || root.socketPath === "/hyprmoncfgd.sock") return
    backendSocket.connected = true
  }

  function send(method, params) {
    if (!backendSocket.connected) {
      root.lastError = "The hyprmoncfg background service is unavailable."
      return ""
    }
    root.requestSequence++
    var id = String(root.requestSequence)
    var request = {
      type: "request",
      protocol_version: 1,
      id: id,
      method: method
    }
    if (params !== undefined && params !== null) request.params = params
    root.pendingMethods[id] = method
    backendSocket.write(JSON.stringify(request) + "\n")
    backendSocket.flush()
    return id
  }

  function subscribe() { root.send("subscribe", {}) }

  function applyProfile(name, allowOverwrite) {
    if (!name || root.applying || root.pendingTransaction !== "") return
    root.applying = true
    root.lastError = ""
    root.overwritePrompt = false
    root.overwriteProfile = String(name)
    var requestId = root.send("preview", {
      profile_name: String(name),
      allow_unmanaged_overwrite: allowOverwrite === true,
      timeout_seconds: 10
    })
    if (!requestId) root.applying = false
  }

  function confirmProfile() {
    if (!root.pendingTransaction || root.transactionActionPending) return
    root.transactionActionPending = true
    if (!root.send("confirm", { transaction_id: root.pendingTransaction }))
      root.transactionActionPending = false
  }

  function revertProfile() {
    if (!root.pendingTransaction || root.transactionActionPending) return
    root.transactionActionPending = true
    if (!root.send("revert", { transaction_id: root.pendingTransaction }))
      root.transactionActionPending = false
  }

  function clearPending() {
    root.pendingTransaction = ""
    root.pendingProfile = ""
    root.pendingDeadline = ""
    root.pendingSeconds = 0
    root.applying = false
    root.transactionActionPending = false
  }

  function updateDocument(value) {
    if (!value || typeof value !== "object") return
    root.document = value
    if (root.cursorIndex >= root.itemCount()) root.cursorIndex = Math.max(0, root.itemCount() - 1)
  }

  function handleMessage(line) {
    var envelope = Model.parseEnvelope(line)
    if (!envelope) {
      root.lastError = "hyprmoncfg returned an invalid IPC message."
      return
    }
    if (envelope.type === "event") {
      if (envelope.event === "status") root.updateDocument(envelope.data)
      return
    }

    var method = root.pendingMethods[String(envelope.id)] || ""
    delete root.pendingMethods[String(envelope.id)]
    if (envelope.error) {
      root.applying = false
      root.transactionActionPending = false
      if (method === "preview" && envelope.error.code === "unmanaged_monitor_config") {
        root.overwritePrompt = true
        root.lastError = "Omarchy’s monitor config must be replaced before this profile can be applied."
      } else if ((method === "confirm" || method === "revert")
                 && envelope.error.code === "transaction_unavailable") {
        root.clearPending()
        root.lastError = method === "confirm"
          ? "The confirmation window expired. The previous layout was restored."
          : ""
        root.send("status", {})
      } else {
        root.lastError = String(envelope.error.message || "hyprmoncfg request failed")
      }
      return
    }

    if (method === "status" || method === "subscribe") {
      root.updateDocument(envelope.result)
    } else if (method === "preview") {
      var transaction = envelope.result || {}
      root.pendingTransaction = String(transaction.id || "")
      root.pendingProfile = transaction.profile ? String(transaction.profile.name || root.overwriteProfile) : root.overwriteProfile
      root.pendingDeadline = String(transaction.deadline || "")
      root.pendingSeconds = Model.secondsRemaining(root.pendingDeadline)
      root.applying = false
      root.transactionActionPending = false
      root.overwritePrompt = false
      root.cursorIndex = 0
    } else if (method === "confirm" || method === "revert") {
      root.clearPending()
      root.send("status", {})
    }
  }

  function itemCount() {
    if (!root.compatible || !root.backendConnected) return 1
    if (root.overwritePrompt || root.pendingTransaction !== "") return 2
    return root.profiles.length + 1
  }

  function moveCursor(delta) {
    root.cursorActive = true
    root.cursorIndex = Math.max(0, Math.min(root.itemCount() - 1, root.cursorIndex + delta))
  }

  function activateCursor() {
    if (!root.compatible) {
      root.install()
      return
    }
    if (!root.backendConnected) {
      root.startDaemon()
      return
    }
    if (root.overwritePrompt) {
      if (root.cursorIndex === 0) root.applyProfile(root.overwriteProfile, true)
      else root.overwritePrompt = false
      return
    }
    if (root.pendingTransaction !== "") {
      if (root.cursorIndex === 0) root.confirmProfile()
      else root.revertProfile()
      return
    }
    if (root.cursorIndex < root.profiles.length) root.applyProfile(root.profiles[root.cursorIndex].name, false)
    else root.launchTui()
  }

  Component.onCompleted: root.checkInstallation()

  onOpenedChanged: {
    if (opened) {
      root.cursorIndex = 0
      root.cursorActive = false
      root.checkInstallation()
      if (root.compatible) root.connectBackend()
    }
  }

  Socket {
    id: backendSocket
    path: root.socketPath
    connected: false
    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleMessage(line) }
    }
    onConnectedChanged: {
      if (connected) {
        root.lastError = ""
        root.installing = false
        root.subscribe()
      } else {
        root.clearPending()
      }
    }
    onError: function(error) {
      backendSocket.connected = false
    }
  }

  Process {
    id: whichProcess
    stdout: StdioCollector { id: versionOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.checkingInstallation = false
      root.installed = exitCode === 0
      root.compatible = root.installed && Model.versionAtLeast(versionOutput.text, "1.11.0")
      if (root.compatible) {
        root.installing = false
        root.connectBackend()
      }
    }
  }

  Process { id: installerProcess }

  Process {
    id: daemonProcess
    stderr: StdioCollector { id: daemonStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = String(daemonStderr.text || "Could not start hyprmoncfg.").trim()
      reconnectTimer.restart()
    }
  }

  Process { id: tuiProcess }

  Timer {
    id: installPoll
    interval: 1000
    repeat: true
    running: root.installing && !root.compatible
    onTriggered: root.checkInstallation()
  }

  Timer {
    id: reconnectTimer
    interval: 1200
    repeat: true
    running: root.compatible && !root.backendConnected
    onTriggered: root.connectBackend()
  }

  Timer {
    interval: 250
    repeat: true
    running: root.pendingTransaction !== ""
    onTriggered: {
      root.pendingSeconds = Model.secondsRemaining(root.pendingDeadline)
      if (root.pendingSeconds <= 0) {
        root.clearPending()
        root.send("status", {})
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "hyprmoncfg"
            meta: root.backendConnected ? "Automatic switching on monitor hotplug" : "Monitor profiles for Hyprland"
            detail: root.backendConnected ? "ON" : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                implicitWidth: Style.space(42)
                implicitHeight: Style.space(42)

                Text {
                  anchors.centerIn: parent
                  text: root.monitorCount > 1 ? "󰍺" : "󰍹"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }

                Rectangle {
                  width: Style.space(15)
                  height: width
                  radius: width / 2
                  anchors.top: parent.top
                  anchors.right: parent.right
                  color: root.backendConnected ? Color.accent : Color.background
                  border.width: 1
                  border.color: root.backendConnected ? Color.accent : root.foreground

                  Text {
                    anchors.centerIn: parent
                    text: "H"
                    color: root.backendConnected ? Color.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: !root.compatible && !root.checkingInstallation
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: root.installed
                ? "Update hyprmoncfg to switch profiles from this panel."
                : "Install hyprmoncfg to switch profiles automatically when monitors connect or disconnect."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            ActionRow {
              width: parent.width
              rowIndex: 0
              icon: root.installing ? "󰦖" : "󰏔"
              title: root.installing
                ? (root.installed ? "Updating hyprmoncfg…" : "Installing hyprmoncfg…")
                : (root.installed ? "Update hyprmoncfg" : "Install hyprmoncfg")
              subtitle: "Automatic switching on monitor hotplug"
              enabled: !root.installing
              onActivated: root.install()
            }
          }

          Column {
            visible: root.compatible && !root.backendConnected
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: "The hyprmoncfg background service is off. Start it to manage monitor profiles."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            ActionRow {
              width: parent.width
              rowIndex: 0
              icon: "󰐊"
              title: "Start hyprmoncfg"
              subtitle: "Enable automatic switching on monitor hotplug"
              onActivated: root.startDaemon()
            }
          }

          Column {
            visible: root.backendConnected && root.overwritePrompt
            width: parent.width
            spacing: Style.space(6)

            ActionRow {
              width: parent.width
              rowIndex: 0
              icon: "󰆴"
              title: "Replace Omarchy’s monitor config"
              subtitle: "hyprmoncfg will own this file from now on"
              onActivated: root.applyProfile(root.overwriteProfile, true)
            }

            ActionRow {
              width: parent.width
              rowIndex: 1
              icon: "󰜺"
              title: "Cancel"
              subtitle: "Leave the existing config unchanged"
              onActivated: root.overwritePrompt = false
            }
          }

          Column {
            visible: root.backendConnected && root.pendingTransaction !== ""
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: "Keep “" + root.pendingProfile + "”? Reverting in " + root.pendingSeconds + "s."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            ActionRow {
              width: parent.width
              rowIndex: 0
              icon: "󰄬"
              title: "Keep this layout"
              subtitle: root.pendingProfile
              enabled: !root.transactionActionPending
              onActivated: root.confirmProfile()
            }

            ActionRow {
              width: parent.width
              rowIndex: 1
              icon: "󰜺"
              title: "Revert"
              subtitle: "Restore the previous layout"
              enabled: !root.transactionActionPending
              onActivated: root.revertProfile()
            }
          }

          Column {
            visible: root.backendConnected && !root.overwritePrompt && root.pendingTransaction === ""
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "PROFILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.profiles.length === 0
              width: parent.width
              text: "No monitor profiles yet. Open the layout editor to create one."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.profiles

              ProfileRow {
                required property var modelData
                required property int index
                width: parent.width
                rowIndex: index
                profile: modelData
                onActivated: root.applyProfile(modelData.name, false)
              }
            }

            PanelSeparator {
              foreground: root.foreground
            }

            ActionRow {
              width: parent.width
              rowIndex: root.profiles.length
              icon: "󰆍"
              title: "Open layout editor"
              subtitle: "Arrange displays and manage profiles"
              onActivated: root.launchTui()
            }
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property int rowIndex: 0
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    signal activated()

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: actionRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: actionRow.enabled
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = actionRow.rowIndex
      }
      onClicked: actionRow.activated()
    }

    Row {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(12)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: actionRow.icon
        color: actionRow.enabled ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Column {
        width: parent.width - parent.children[0].width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: actionRow.title
          color: actionRow.enabled ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: actionRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    required property var profile
    property int rowIndex: 0
    signal activated()

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: profile.active === true
    foreground: root.foreground
    implicitHeight: profileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.applying ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !root.applying
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = profileRow.rowIndex
      }
      onClicked: profileRow.activated()
    }

    Row {
      id: profileContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: profile.active === true ? "󰄬" : "󰍹"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Column {
        width: parent.width - parent.children[0].width - autoLabel.implicitWidth - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: String(profile.name || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: profile.active === true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: Model.profileSummary(profile)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Text {
        id: autoLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: profile.recommended === true
        text: "AUTO"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}
