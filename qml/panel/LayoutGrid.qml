import QtQuick
import QtQuick.Layouts
import "../js/Layouts.js" as Layouts
import "../controls"

// The Layouts tab: a tile per layout, with a picture of it. Clicking a tile gives the
// focused workspace that layout; the dot in its corner keeps it in Super + L or not.
ColumnLayout {
    id: root

    property var svc: null
    readonly property var ui: svc ? svc.ui : null
    property string hint: ""
    spacing: ui.px(10)

    readonly property string current: svc ? svc.activeMode : ""

    RowLayout {
        Layout.fillWidth: true
        spacing: ui.px(10)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Txt {
                ui: root.ui
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: !root.svc || root.svc.activeId <= 0 ? "Layouts"
                    : "Workspace " + root.svc.activeId + (root.svc.activeLabel !== "" ? ": " + root.svc.activeLabel : "")
                font.pixelSize: ui.fs(13)
                font.weight: Font.DemiBold
            }
            Txt {
                ui: root.ui
                Layout.fillWidth: true
                visible: root.hint !== ""
                text: root.hint
                wrapMode: Text.WordWrap
                font.pixelSize: ui.fs(10)
                opacity: 0.55
            }
        }
        Txt {
            ui: root.ui
            Layout.alignment: Qt.AlignTop
            text: root.svc ? root.svc.cfg.cycle.length + " in Super + L" : ""
            font.pixelSize: ui.fs(10)
            opacity: 0.55
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 4
        columnSpacing: ui.px(8)
        rowSpacing: ui.px(8)

        Repeater {
            model: Layouts.list
            delegate: Rectangle {
                id: tile
                required property var modelData
                readonly property bool on: root.current === modelData.id
                readonly property bool cycled: root.svc !== null && root.svc.cfg.cycle.indexOf(modelData.id) !== -1
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: ui.px(78)
                radius: ui.r(1.4)
                color: on ? ui.accentTint(0.16) : ui.tint(area.containsMouse ? 0.09 : 0.04)
                border.width: on ? 1.5 : 1
                border.color: on ? ui.accent : ui.tint(0.08)
                Behavior on color { enabled: ui.animations; ColorAnimation { duration: 100 } }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.svc.setLayout(tile.modelData.id)
                }

                LayoutArt {
                    ui: root.ui
                    layout: tile.modelData.id
                    on: tile.on
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: ui.px(10)
                    width: Math.min(parent.width - ui.px(28), ui.px(66))
                    height: Math.round(width * 9 / 16)
                }
                Txt {
                    ui: root.ui
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: ui.px(7)
                    width: parent.width - ui.px(8)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    font.pixelSize: ui.fs(10)
                    font.weight: tile.on ? Font.DemiBold : Font.Normal
                    opacity: tile.on ? 1 : 0.85
                }

                // in Super + L or not
                Rectangle {
                    id: dot
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: ui.px(5)
                    width: ui.px(11)
                    height: width
                    radius: width / 2
                    color: tile.cycled ? ui.accent : "transparent"
                    border.width: 1
                    border.color: tile.cycled ? ui.accent : ui.tint(dotArea.containsMouse ? 0.6 : 0.3)
                    MouseArea {
                        id: dotArea
                        anchors.fill: parent
                        anchors.margins: -5
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.svc.toggleCycle(tile.modelData.id)
                    }
                }
            }
        }
    }

    Txt {
        ui: root.ui
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: {
            const hover = Layouts.byId[root.current]
            return hover ? hover.name + ": " + hover.hint + "." : ""
        }
        font.pixelSize: ui.fs(10)
        opacity: 0.55
    }
}
