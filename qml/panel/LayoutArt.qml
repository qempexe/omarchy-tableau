import QtQuick
import "../js/Layouts.js" as Layouts

// A layout as a little picture: its windows as boxes, the one you use in the accent.
Canvas {
    id: art

    property var ui: null
    property string layout: ""
    property bool on: false

    implicitWidth: 64
    implicitHeight: 38
    readonly property color ink: ui ? ui.fg : "white"
    readonly property color ac: ui ? ui.accent : "white"
    onLayoutChanged: requestPaint()
    onOnChanged: requestPaint()
    onInkChanged: requestPaint()
    onAcChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        if (width < 4 || height < 4) return
        // the screen
        ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.22)
        ctx.lineWidth = 1
        ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
        ctx.save()
        ctx.beginPath()
        ctx.rect(1, 1, width - 2, height - 2)
        ctx.clip()
        const boxes = Layouts.art(layout)
        const pad = 2.5, gap = 1.5
        const w = width - 2 * pad, h = height - 2 * pad
        for (let i = boxes.length - 1; i >= 0; i--) {
            const b = boxes[i]
            const x = pad + b.x * w + gap / 2, y = pad + b.y * h + gap / 2
            const bw = Math.max(1, b.w * w - gap), bh = Math.max(1, b.h * h - gap)
            const c = b.main ? (on ? ac : Qt.rgba(ink.r, ink.g, ink.b, 0.85)) : ink
            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, b.main ? (on ? 0.55 : 0.32) : 0.14)
            ctx.fillRect(x, y, bw, bh)
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, b.main ? 0.95 : 0.45)
            ctx.strokeRect(x + 0.5, y + 0.5, bw - 1, bh - 1)
        }
        ctx.restore()
    }
}
