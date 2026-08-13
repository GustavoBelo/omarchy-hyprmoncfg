import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "crmne.hyprmoncfg"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool backendConnected: panelLoader.item ? panelLoader.item.backendConnected === true : false
  readonly property int monitorCount: panelLoader.item ? panelLoader.item.monitorCount : Quickshell.screens.length

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    tooltipText: "hyprmoncfg"
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.monitorCount > 1 ? "󰍺" : "󰍹"
          color: root.backendConnected ? button.foreground : Qt.darker(button.foreground, 1.55)
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
        }

        Rectangle {
          width: Math.max(9, Style.space(10))
          height: width
          radius: width / 2
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: -1
          anchors.rightMargin: -1
          color: root.backendConnected ? Color.accent : Color.background
          border.width: 1
          border.color: root.backendConnected ? Color.accent : button.foreground

          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -0.5
            text: "H"
            color: root.backendConnected ? Color.background : button.foreground
            font.family: button.fontFamily
            font.pixelSize: Math.max(7, parent.height * 0.68)
            font.bold: true
          }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
