import QtQuick
import qs.Commons
import qs.Commons as Commons
// Qualified: qs.Services has names of its own (Notifications, Weather...)
// and this file only needs the IPC router.
import qs.Services as Services

// Base item for plugin popup widgets. Many first-party plugins expose a bar
// button plus a popup from one QML entry point; this base owns the shared
// IPC-backed open/close lifecycle while implementations own button behavior,
// keyboard navigation, and content.
//
// The IPC handler itself is not here. Every monitor's bar builds its own copy
// of a panel, and a handler per copy meant one target registered once per
// screen with Quickshell keeping the first -- so `pshell network toggle`
// opened on whichever bar loaded first, not the focused one. Each panel
// registers with Services/PanelIpc.qml instead, which holds one handler per
// target and routes the call to the copy on the focused monitor.
Item {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property alias controller: panelController
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false

  readonly property bool opened: panelController.open
  readonly property color barForeground: bar ? bar.barForeground : Commons.Color.foreground

  function open() { panelController.show() }
  function close() { panelController.hide() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }
  function toggle() { opened ? close() : open() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(root, direction)
    return false
  }

  // Read a single value from this panel's inline shell.json entry, with a
  // fallback for missing/null values. Matches BarWidget.setting().
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  PanelController {
    id: panelController
  }

  // The target as registered, kept so destruction unregisters the same name
  // even if ipcTarget were rebound in between.
  property string _registeredTarget: ""

  Component.onCompleted: {
    if (manageIpc && ipcTarget !== "") {
      _registeredTarget = ipcTarget
      Services.PanelIpc.register(_registeredTarget, root)
    }
  }
  Component.onDestruction: if (_registeredTarget !== "") Services.PanelIpc.unregister(_registeredTarget, root)

}
