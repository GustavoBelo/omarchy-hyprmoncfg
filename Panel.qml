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
  property string installedVersion: ""
  property bool compatible: false
  property bool checkingInstallation: true
  property bool installationStateKnown: false
  property bool installing: false
  property bool serviceEnabled: false
  property bool serviceActive: false
  property bool serviceStateKnown: false
  property bool serviceActionPending: false
  property bool serviceTargetManaged: false
  property string serviceAction: ""
  property bool connectionGrace: false
  property bool backendConnected: backendSocket.connected
  property var document: ({ profiles: [], monitors: [], daemon: { running: false } })
  property bool documentReady: false
  property string lastError: ""
  property int requestSequence: 0
  property var pendingMethods: ({})
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property var monitorSummaries: document && document.monitors instanceof Array ? document.monitors : []
  readonly property var layoutDisplays: Model.layoutDisplays(
    root.backendConnected ? monitorSummaries : [],
    Quickshell.screens || []
  )
  readonly property var layoutBounds: Model.layoutBounds(layoutDisplays)
  readonly property string hiddenDisplays: Model.hiddenDisplays(
    root.backendConnected ? monitorSummaries : []
  )
  readonly property int monitorCount: {
    return layoutDisplays.length
  }
  readonly property string activeProfile: root.managedChecked && document && document.active_profile
    ? String(document.active_profile.name || "")
    : ""
  readonly property string recommendedProfile: root.managedChecked && document && document.recommended_profile
    ? String(document.recommended_profile.name || "")
    : ""
  readonly property string displayedProfile: activeProfile !== "" ? activeProfile : recommendedProfile
  readonly property string profileStatusTitle: {
    if (!root.managedChecked) return "Not managed by hyprmoncfg"
    if (!root.documentReady) return root.serviceActionPending ? "Starting hyprmoncfg…" : "Loading profile…"
    if (displayedProfile !== "") return displayedProfile
    return "Custom layout"
  }
  readonly property string profileStatusSubtitle: {
    if (!root.managedChecked) return "Turn on management for automatic profiles"
    if (!root.documentReady) return "Reading the active display layout"
    var displays = monitorCount === 1 ? "1 display" : monitorCount + " displays"
    if (activeProfile !== "") return displays + " · Active"
    if (recommendedProfile !== "") return displays + " · Best match, not active"
    return displays + " · No matching profile"
  }
  readonly property bool managedChecked: serviceActionPending
    ? serviceTargetManaged
    : (serviceEnabled || serviceActive || backendConnected)
  readonly property bool daemonOutdated: root.backendConnected
    && root.documentReady
    && Model.daemonNeedsRestart(root.installedVersion, root.document ? root.document.version : "")
  readonly property bool serviceBroken: serviceStateKnown
    && serviceEnabled
    && !backendConnected
    && !connectionGrace
    && !serviceActionPending
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string socketPath: root.runtimeDir + "/hyprmoncfgd.sock"
  readonly property string installFailurePath: root.runtimeDir + "/hyprmoncfg-panel-install.failed"
  readonly property string installCompletePath: root.runtimeDir + "/hyprmoncfg-panel-install.complete"
  readonly property bool barIconDimmed: root.installationStateKnown
    && root.compatible
    && root.serviceStateKnown
    && !root.managedChecked
    && !root.serviceActionPending
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
    root.cursorActive = false
    root.cursorIndex = 0
    root.checkInstallation()
    if (root.compatible) root.checkServiceState()
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
    if (!root.installationStateKnown) root.checkingInstallation = true
    whichProcess.command = [
      "sh",
      "-c",
      "if test \"$3\" = \"1\"; then if test -f \"$1\"; then cat \"$1\"; exit 2; elif ! test -f \"$2\"; then exit 3; fi; fi; if command -v hyprmoncfg >/dev/null 2>&1; then hyprmoncfg version; else exit 1; fi",
      "sh",
      root.installFailurePath,
      root.installCompletePath,
      root.installing ? "1" : "0"
    ]
    whichProcess.running = true
  }

  function checkServiceState() {
    if (!root.compatible || serviceProcess.running || enabledProcess.running || activeProcess.running) return
    enabledProcess.command = ["systemctl", "--user", "is-enabled", "--quiet", "hyprmoncfgd.service"]
    enabledProcess.running = true
  }

  function install() {
    if (root.runtimeDir === "") {
      root.lastError = "Could not find the user runtime directory."
      return
    }
    root.installing = true
    root.lastError = ""
    installPreparationProcess.command = ["rm", "-f", root.installFailurePath, root.installCompletePath]
    installPreparationProcess.running = true
  }

  function setManaged(enabled) {
    if (!root.compatible || serviceProcess.running || root.serviceActionPending) return
    root.lastError = ""
    root.serviceActionPending = true
    root.serviceTargetManaged = enabled === true
    root.serviceAction = enabled === true ? "enable" : "disable"
    serviceProcess.command = enabled === true
      ? ["systemctl", "--user", "enable", "--now", "hyprmoncfgd.service"]
      : ["systemctl", "--user", "disable", "--now", "hyprmoncfgd.service"]
    serviceProcess.running = true
  }

  function restartService() {
    if (!root.compatible || serviceProcess.running || root.serviceActionPending) return
    root.lastError = ""
    root.serviceActionPending = true
    root.serviceTargetManaged = true
    root.serviceAction = "restart"
    serviceProcess.command = ["systemctl", "--user", "restart", "hyprmoncfgd.service"]
    serviceProcess.running = true
  }

  function launchTui() {
    tuiProcess.command = ["gtk-launch", "hyprmoncfg-omarchy"]
    tuiProcess.startDetached()
    root.close()
  }

  function connectBackend() {
    if (!root.compatible || backendSocket.connected || root.socketPath === "/hyprmoncfgd.sock") return
    if (!root.serviceEnabled && !root.serviceActive && !(root.serviceActionPending && root.serviceTargetManaged)) return
    backendSocket.connected = true
  }

  function send(method, params) {
    if (!backendSocket.connected) return ""
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

  function updateDocument(value) {
    if (!value || typeof value !== "object") return
    root.document = value
    root.documentReady = true
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
      root.lastError = String(envelope.error.message || "hyprmoncfg request failed")
      return
    }
    if (method === "status" || method === "subscribe") root.updateDocument(envelope.result)
  }

  function itemCount() {
    if (!root.compatible) return 1
    return root.serviceBroken ? 3 : 2
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
    if (root.cursorIndex === 0) {
      root.setManaged(!root.managedChecked)
      return
    }
    if (root.serviceBroken && root.cursorIndex === 1) root.restartService()
    else root.launchTui()
  }

  Component.onCompleted: root.checkInstallation()

  onOpenedChanged: {
    if (opened) {
      root.cursorIndex = 0
      root.cursorActive = false
      root.checkInstallation()
      if (root.compatible) root.checkServiceState()
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
        root.connectionGrace = false
        root.lastError = ""
        root.installing = false
        root.subscribe()
      } else {
        root.pendingMethods = ({})
        if (root.compatible && (root.serviceEnabled || root.serviceActive))
          serviceRefreshTimer.restart()
      }
    }
    onError: function(error) { backendSocket.connected = false }
  }

  Process {
    id: whichProcess
    stdout: StdioCollector { id: versionOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 3 && root.installing) return

      root.checkingInstallation = false
      root.installationStateKnown = true
      var probedInstalled = exitCode === 0
      var probedCompatible = probedInstalled && Model.versionAtLeast(versionOutput.text, "1.12.0")

      if (root.installing && exitCode === 2) {
        root.installing = false
        installPoll.stop()
        installTimeout.stop()
        root.lastError = String(versionOutput.text || "").trim() === "130"
          ? "Installation was canceled."
          : "Installation did not finish. Check the Omarchy terminal and try again."
        return
      }

      if (root.installing && !probedCompatible) {
        root.installing = false
        installPoll.stop()
        installTimeout.stop()
        root.lastError = "The update finished, but hyprmoncfg 1.12.0 or newer is still required."
        return
      }

      root.installed = probedInstalled
      root.installedVersion = probedInstalled ? String(versionOutput.text || "") : ""
      root.compatible = probedCompatible
      if (root.compatible) {
        root.installing = false
        installPoll.stop()
        installTimeout.stop()
        root.checkServiceState()
      } else {
        backendSocket.connected = false
        root.serviceStateKnown = false
      }
    }
  }

  Process {
    id: enabledProcess
    onExited: function(exitCode) {
      root.serviceEnabled = exitCode === 0
      activeProcess.command = ["systemctl", "--user", "is-active", "--quiet", "hyprmoncfgd.service"]
      activeProcess.running = true
    }
  }

  Process {
    id: activeProcess
    onExited: function(exitCode) {
      var wasActive = root.serviceActive
      root.serviceActive = exitCode === 0
      root.serviceStateKnown = true
      if (root.serviceActive) {
        if (!root.backendConnected) {
          if (!wasActive) {
            root.connectionGrace = true
            connectionGraceTimer.restart()
          }
          root.connectBackend()
        }
      } else {
        root.connectionGrace = false
        backendSocket.connected = false
      }
      if (root.serviceActionPending && !serviceProcess.running) {
        var confirmed = root.serviceTargetManaged
          ? (root.serviceEnabled && root.serviceActive)
          : (!root.serviceEnabled && !root.serviceActive)
        if (confirmed) {
          root.serviceActionPending = false
          root.serviceAction = ""
          serviceConfirmationTimer.stop()
        } else {
          serviceRefreshTimer.restart()
        }
      }
    }
  }

  Process {
    id: installPreparationProcess
    onExited: function(exitCode) {
      if (!root.installing) return
      if (exitCode !== 0) {
        root.installing = false
        root.lastError = "Could not prepare the hyprmoncfg update."
        return
      }
      installerProcess.command = Model.installProcessArgs()
      installerProcess.startDetached()
      installPoll.restart()
      installTimeout.restart()
    }
  }

  Process { id: installerProcess }

  Process {
    id: serviceProcess
    stderr: StdioCollector { id: serviceStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var action = root.serviceAction
      if (exitCode !== 0) {
        root.serviceActionPending = false
        root.serviceAction = ""
        var fallback = action === "disable" ? "Could not return display management to Omarchy." : "Could not start hyprmoncfg."
        root.lastError = String(serviceStderr.text || fallback).trim()
      } else if (action === "disable") {
        backendSocket.connected = false
      } else {
        root.connectionGrace = true
        connectionGraceTimer.restart()
        reconnectTimer.restart()
      }
      if (exitCode === 0) serviceConfirmationTimer.restart()
      serviceRefreshTimer.restart()
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
    id: installTimeout
    interval: 300000
    onTriggered: {
      if (!root.installing) return
      root.installing = false
      installPoll.stop()
      root.lastError = "Installation is still waiting. Check the Omarchy terminal and try again."
    }
  }

  Timer {
    id: serviceRefreshTimer
    interval: 250
    onTriggered: root.checkServiceState()
  }

  Timer {
    id: serviceDiscoveryTimer
    interval: 2000
    repeat: true
    running: root.compatible && !root.backendConnected && !root.serviceActionPending
    onTriggered: root.checkServiceState()
  }

  Timer {
    id: connectionGraceTimer
    interval: 2000
    onTriggered: root.connectionGrace = false
  }

  Timer {
    id: serviceConfirmationTimer
    interval: 5000
    onTriggered: {
      if (!root.serviceActionPending) return
      root.serviceActionPending = false
      root.serviceAction = ""
      root.lastError = "Could not confirm the automatic switching state."
      root.checkServiceState()
    }
  }

  Timer {
    id: reconnectTimer
    interval: 1000
    repeat: true
    running: root.compatible
      && (root.serviceActive || (root.serviceActionPending && root.serviceTargetManaged))
      && !root.backendConnected
    onTriggered: {
      root.checkServiceState()
      root.connectBackend()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Column {
          id: contentColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          Item {
            visible: root.compatible || root.checkingInstallation
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Item {
              id: heroIcon
              implicitWidth: heroDisplayGlyph.implicitWidth
              implicitHeight: heroDisplayGlyph.implicitHeight
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              opacity: root.backendConnected ? 1.0 : 0.6

              Text {
                id: heroDisplayGlyph
                text: root.monitorCount > 1 ? "󰍺" : "󰍹"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              Text {
                visible: root.backendConnected
                anchors.right: heroDisplayGlyph.right
                anchors.bottom: heroDisplayGlyph.bottom
                anchors.rightMargin: -Style.space(2)
                anchors.bottomMargin: -Style.space(1)
                text: "󰄬"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "Display"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: "HYPRMONCFG"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
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
            spacing: Style.space(16)

            Item {
              width: parent.width
              implicitHeight: Style.space(64)

              Text {
                id: welcomeDisplayGlyph
                anchors.centerIn: parent
                text: root.installed ? "\uf021" : (root.monitorCount > 1 ? "󰍺" : "󰍹")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display + Style.space(12)
              }

              Text {
                visible: !root.installed
                anchors.right: welcomeDisplayGlyph.right
                anchors.bottom: welcomeDisplayGlyph.bottom
                anchors.rightMargin: -Style.space(3)
                anchors.bottomMargin: -Style.space(1)
                text: "󰄬"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width
                text: root.installed
                  ? "Bring hyprmoncfg up to date."
                  : "Build layouts visually."
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: root.installed
                  ? "Update once for live layouts and automatic switching."
                  : "hyprmoncfg switches them on hotplug and lid events."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: "This panel puts the live layout, active profile, and automatic switching right here in Omarchy."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }
            }

            Button {
              width: parent.width
              text: root.installing
                ? (root.installed ? "Updating hyprmoncfg…" : "Installing hyprmoncfg…")
                : (root.installed ? "Update hyprmoncfg" : "Install hyprmoncfg")
              iconText: root.installed ? "\uf021" : (root.installing ? "󰦖" : "󰏔")
              iconSpinning: root.installing
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              iconSize: Style.font.icon
              foreground: root.foreground
              accent: Color.accent
              verticalPadding: Style.space(14)
              bordered: true
              selected: !root.installed
              hasCursor: root.cursorActive && root.cursorIndex === 0
              enabled: !root.installing
              onHovered: function(hovered) {
                if (hovered) {
                  root.cursorActive = true
                  root.cursorIndex = 0
                }
              }
              onClicked: root.install()
            }
          }

          Column {
            visible: root.compatible
            width: parent.width
            spacing: Style.space(14)

            PanelSeparator { foreground: root.foreground }

            Column {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "MONITOR MANAGEMENT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Toggle {
                width: parent.width
                label: "Managed by hyprmoncfg"
                description: {
                  if (root.serviceActionPending)
                    return root.serviceTargetManaged ? "Starting on monitor hotplug and lid events…" : "Turning off automatic switching…"
                  if (root.serviceBroken) return "The background service could not start"
                  return "Automatic switching on monitor hotplug and lid events"
                }
                checked: root.managedChecked
                enabled: !root.serviceActionPending
                hasCursor: root.cursorActive && root.cursorIndex === 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(hovered) {
                  if (hovered) {
                    root.cursorActive = true
                    root.cursorIndex = 0
                  }
                }
                onClicked: root.setManaged(!root.managedChecked)
              }
            }

            Column {
              visible: root.serviceBroken
              width: parent.width
              spacing: Style.space(10)

              ActionRow {
                width: parent.width
                rowIndex: 1
                icon: "󰑓"
                title: "Restart hyprmoncfg"
                subtitle: "Try the background service again"
                onActivated: root.restartService()
              }
            }

            Column {
              visible: root.daemonOutdated && !root.serviceBroken
              width: parent.width
              spacing: Style.space(10)

              ActionRow {
                width: parent.width
                rowIndex: 1
                icon: "󰑓"
                title: "Restart to finish updating"
                subtitle: "hyprmoncfg was updated, but the previous version is still running"
                onActivated: root.restartService()
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(14)

              PanelSeparator { foreground: root.foreground }

              Column {
                width: parent.width
                spacing: Style.space(10)

                PanelSectionHeader {
                  text: "LAYOUT AND SETTINGS"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                CursorSurface {
                  id: layoutEditor
                  width: parent.width
                  implicitHeight: Style.space(150)
                  bordered: true
                  hasCursor: root.cursorActive && root.cursorIndex === (root.serviceBroken ? 2 : 1)
                  foreground: root.foreground

                  Text {
                    id: hiddenDisplaysLabel
                    visible: root.hiddenDisplays !== ""
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(12)
                    text: root.hiddenDisplays
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Item {
                    id: layoutCanvas
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    anchors.topMargin: Style.space(12)
                      + (hiddenDisplaysLabel.visible ? hiddenDisplaysLabel.height + Style.space(4) : 0)

                    Repeater {
                      model: root.layoutDisplays

                      Rectangle {
                        required property var modelData
                        readonly property bool compactCard: width < Style.space(190)
                        readonly property var previewRect: Model.layoutRect(
                          modelData,
                          root.layoutBounds,
                          layoutCanvas.width,
                          layoutCanvas.height,
                          0
                        )

                        x: previewRect.x
                        y: previewRect.y
                        width: previewRect.width
                        height: previewRect.height
                        radius: Math.min(Style.cornerRadius, 5)
                        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)
                        border.width: 1
                        border.color: root.foreground

                        Column {
                          anchors.centerIn: parent
                          width: Math.max(0, parent.width - Style.space(8))
                          spacing: Style.space(1)

                          Text {
                            width: parent.width
                            text: String(modelData.name || "Display")
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                          }

                          Text {
                            visible: parent.parent.height >= Style.space(58)
                            width: parent.width
                            text: Model.displayModelLabel(modelData, parent.parent.compactCard)
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: parent.parent.compactCard ? Text.WordWrap : Text.NoWrap
                            maximumLineCount: parent.parent.compactCard ? 2 : 1
                            elide: Text.ElideRight
                          }

                          Text {
                            visible: !parent.parent.compactCard && text !== "" && parent.parent.height >= Style.space(78)
                            width: parent.width
                            text: Model.displayDetailLabel(modelData)
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                          }
                        }
                      }
                    }

                    Text {
                      visible: root.layoutDisplays.length === 0
                      anchors.centerIn: parent
                      text: "Waiting for displays…"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                      root.cursorActive = true
                      root.cursorIndex = root.serviceBroken ? 2 : 1
                    }
                    onClicked: root.launchTui()
                  }
                }
              }

              PanelSeparator { foreground: root.foreground }

              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: "PROFILE"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Item {
                  id: profileInfo
                  width: parent.width
                  implicitHeight: profileContent.implicitHeight + Style.spacing.rowPaddingX

                  Row {
                    id: profileContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    spacing: Style.space(12)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.monitorCount > 1 ? "󰍺" : "󰍹"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }

                    Column {
                      width: parent.width - parent.children[0].width - parent.spacing
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        text: root.profileStatusTitle
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        text: root.profileStatusSubtitle
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                    }
                  }
                }
              }
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
}
