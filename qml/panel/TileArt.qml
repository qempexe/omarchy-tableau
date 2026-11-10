import QtQuick

// The little picture on a tile: for "Other windows", a focused window and an unfocused
// one with the outline that option gives it.
Canvas {
    id: art

    property var ui: null
    property string key: ""
    property string opt: ""
    property bool on: false

    width: 64
    height: 40
    readonly property color ink: ui ? ui.fg : "white"
    readonly property color ac: ui ? ui.accent : "white"
    readonly property var stops: ui && ui.borderColors.length > 0 ? ui.borderColors : [ac]
    onOnChanged: requestPaint()
    onInkChanged: requestPaint()
    onAcChanged: requestPaint()
    onStopsChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        if (key !== "others") return
        function border(x, y, w, h, focused) {
            let style
            if (focused || opt === "same") {
                const g = ctx.createLinearGradient(x, y, x + w, y + h)
                for (let i = 0; i < stops.length; i++) g.addColorStop(stops.length === 1 ? 0 : i / (stops.length - 1), stops[i])
                if (stops.length === 1) g.addColorStop(1, stops[0])
                style = g
            } else if (opt === "theme") {
                style = Qt.rgba(ink.r, ink.g, ink.b, 0.35)
            } else return
            ctx.strokeStyle = style
            ctx.lineWidth = 2
            ctx.strokeRect(x + 1, y + 1, w - 2, h - 2)
        }
        // the focused window, and a smaller one beside it
        ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.16)
        ctx.fillRect(3, 3, 36, height - 6)
        ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.09)
        ctx.fillRect(43, 3, 18, (height - 9) / 2)
        ctx.fillRect(43, 6 + (height - 9) / 2, 18, (height - 9) / 2)
        border(3, 3, 36, height - 6, true)
        border(43, 3, 18, (height - 9) / 2, false)
        border(43, 6 + (height - 9) / 2, 18, (height - 9) / 2, false)
    }
}
