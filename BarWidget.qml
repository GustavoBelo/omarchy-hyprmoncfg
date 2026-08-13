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
  readonly property string activeProfile: panelLoader.item ? panelLoader.item.activeProfile : ""

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
    tooltipText: root.activeProfile !== "" ? "Display · " + root.activeProfile : "Display · hyprmoncfg"
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
          visible: root.backendConnected
          width: Math.max(3, Style.space(3))
          height: width
          radius: width / 2
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -1
          color: Color.accent
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
