import QtQuick
import QtQuick.Layouts
import "../js/Layouts.js" as Layouts
import "../controls"

// The Rules tab: every workspace there is, and the empty ones with a saved layout, each
// with its layout. ‹ and › step through the layouts for that workspace.
Item {
    id: root

    property var svc: null
    readonly property var ui: svc ? svc.ui : null
    // the height to fill: the whole tab when this is the only thing on show
    property real fill: 0

    readonly property var rows: svc ? svc.workspaces : []
    implicitHeight: Math.max(col.implicitHeight, fill)

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: ui.px(6)

        Txt { ui: root.ui; Layout.fillWidth: true; text: "Layout per workspace"; font.pixelSize: ui.fs(13); font.weight: Font.DemiBold }
        Txt {
            ui: root.ui
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Each workspace keeps its own layout, also across restarts. ‹ and › change it, the focused one is marked."
            font.pixelSize: ui.fs(10)
            opacity: 0.55
        }

        Txt {
            ui: root.ui
            visible: root.rows.length === 0
            Layout.topMargin: ui.px(10)
            text: root.svc && root.svc.statusError !== "" ? "Hyprland didn't answer: " + root.svc.statusError : "No workspaces yet"
            font.pixelSize: ui.fs(11)
            opacity: 0.6
        }

        Repeater {
            model: root.rows
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool active: root.svc !== null && modelData.id === root.svc.activeId
                Layout.fillWidth: true
                Layout.topMargin: ui.px(2)
                implicitHeight: ui.px(50)
                radius: ui.r(1.4)
                color: active ? ui.accentTint(0.12) : ui.tint(0.04)
                border.width: 1
                border.color: active ? ui.accentTint(0.6) : ui.tint(0.07)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: ui.px(10)
                    anchors.rightMargin: ui.px(10)
                    spacing: ui.px(10)

                    LayoutArt {
                        ui: root.ui
                        layout: row.modelData.mode
                        on: row.active
                        Layout.preferredWidth: ui.px(52)
                        Layout.preferredHeight: ui.px(30)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Txt {
                            ui: root.ui
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "Workspace " + row.modelData.name + (row.modelData.monitor !== "" ? "  ·  " + row.modelData.monitor : "")
                            font.pixelSize: ui.fs(12)
                            font.weight: row.active ? Font.DemiBold : Font.Normal
                        }
                        Txt {
                            ui: root.ui
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Layouts.nameOf(row.modelData.mode) + "  ·  "
                                + (row.modelData.windows === 1 ? "1 window" : row.modelData.windows + " windows")
                            font.pixelSize: ui.fs(10)
                            opacity: 0.6
                        }
                    }
                    Btn {
                        ui: root.ui
                        text: "‹"
                        implicitWidth: ui.px(26)
                        onClicked: root.svc.setLayout(Layouts.step(row.modelData.mode, -1), row.modelData.id)
                    }
                    Btn {
                        ui: root.ui
                        text: "›"
                        implicitWidth: ui.px(26)
                        onClicked: root.svc.setLayout(Layouts.step(row.modelData.mode, 1), row.modelData.id)
                    }
                }
            }
        }
    }
}
