import QtQuick
import Quickshell

// The panel as a normal window, titled "Tableau" so it can have window rules
FloatingWindow {
    id: win

    property var svc: null
    readonly property var ui: svc ? svc.ui : null

    title: "Tableau"
    visible: false
    color: "transparent"
    implicitWidth: ui ? ui.cfgSafe.windowWidth : 580
    implicitHeight: ui ? ui.cfgSafe.windowHeight : 660

    Loader {
        anchors.fill: parent
        active: win.svc !== null
        sourceComponent: Component { PanelView { svc: win.svc; shown: win.visible; focus: true } }
    }
}
