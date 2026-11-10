import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
  id: root
  property string servicePath: decodeURIComponent(Qt.resolvedUrl("hypr/tableau-service.sh").toString().replace(/^file:\/\//, ""))

  Process {
    id: loadTableau
    command: ["bash", root.servicePath, "load"]
  }
  Process {
    id: stopTableau
    command: ["bash", root.servicePath, "stop"]
  }
  Process {
    id: startTableau
    command: ["bash", root.servicePath, "start"]
    onExited: function(code) { if (code !== 0) console.warn("Tableau: runtime startup did not complete") }
  }
  Timer {
    id: reloadTimer
    interval: 500
    onTriggered: loadTableau.running = true
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") reloadTimer.restart()
    }
  }
  Component.onCompleted: startTableau.running = true
  Component.onDestruction: stopTableau.running = true
}
