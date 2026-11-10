import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "js/Schema.js" as Schema
import "js/Layouts.js" as Layouts
import "js/Theme.js" as Theme
import "js/Util.js" as Util
import "core"

// The always-loaded part: it registers the layouts with Hyprland, keeps the settings,
// hands the layouts their part of them, and knows which layout every workspace has.
// It runs once, however many bars and screens there are; every bar button only shows
// what is here.
Item {
    id: root

    visible: false

    property var shell: null
    property var manifest: null

    readonly property string pluginId: "io.github.qempexe.tableau"
    readonly property string version: manifest && manifest.version ? String(manifest.version) : "1.0.0"

    readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
    readonly property string servicePath: pluginDir + "/hypr/tableau-service.sh"
    readonly property string cyclePath: pluginDir + "/cycle_layout.py"
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state")) + "/hypr-tableau"

    // ---- settings ----------------------------------------------------------------------
    SettingsStore { id: settingsStore }
    property alias store: settingsStore
    readonly property var cfg: Schema.resolve(settingsStore.values)

    function setValue(key, value) {
        const v = Schema.clean(key, value)
        if (v !== undefined) settingsStore.set(key, v)
    }
    function resetAll() { settingsStore.resetAll(Schema.defaults) }

    // the dot on a layout tile: in Super + L or not (at least two stay in)
    function inCycle(id) { return root.cfg.cycle.indexOf(id) !== -1 }
    function toggleCycle(id) {
        if (!Layouts.isLayout(id)) return
        const list = root.cfg.cycle.slice()
        const at = list.indexOf(id)
        if (at >= 0) {
            if (list.length <= 2) return
            list.splice(at, 1)
        } else list.push(id)
        root.setValue("cycle", list)
    }
    function toggleFullSize(cls) {
        const c = Schema.className(cls)
        if (c === "") return
        const list = root.cfg.fullSize.slice()
        const i = list.indexOf(c)
        if (i >= 0) list.splice(i, 1)
        else list.push(c)
        root.setValue("fullSize", list)
    }

    UiState {
        id: ux
        cfg: root.cfg
        barFg: Color.bar.text
        barBg: Color.bar.background
        themeAccent: Color.accent
        themeUrgent: Color.urgent
        fontName: Style.font.family
        borderColors: root.borderColors
        borderAngle: root.borderAngle
    }
    property alias ui: ux

    // ---- the theme's window border, for the Window borders colors ------------------------
    property var luaBorder: ({ colors: [], angle: 0 })
    property var confBorder: ({ colors: [], angle: 0 })
    property bool luaMissing: false
    readonly property var borderColors: luaBorder.colors.length > 0 ? luaBorder.colors : confBorder.colors
    readonly property real borderAngle: luaBorder.colors.length > 0 ? luaBorder.angle : confBorder.angle
    readonly property string themeDir: {
        try { return Color.currentThemePath ? String(Color.currentThemePath) : "" } catch (e) { return "" }
    }
    function fileText(fv) {
        try { const t = typeof fv.text === "function" ? fv.text() : fv.text; return typeof t === "string" ? t : "" } catch (e) { return "" }
    }
    FileView {
        id: borderLua
        path: root.themeDir !== "" ? root.themeDir + "/hyprland.lua" : ""
        watchChanges: true
        printErrors: false                  // a theme switch removes it for a moment
        onFileChanged: reload()
        onLoaded: { root.luaMissing = false; root.luaBorder = Theme.parseBorder(root.fileText(borderLua)) }
        onLoadFailed: { root.luaBorder = ({ colors: [], angle: 0 }); root.luaMissing = true; root.retryTheme() }
    }
    FileView {
        id: borderConf
        path: root.themeDir !== "" && root.luaMissing ? root.themeDir + "/hyprland.conf" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onPathChanged: if (path === "") root.confBorder = ({ colors: [], angle: 0 })
        onLoaded: root.confBorder = Theme.parseBorder(root.fileText(borderConf))
        onLoadFailed: root.confBorder = ({ colors: [], angle: 0 })
    }
    property int themeTries: 0
    function retryTheme() { if (root.themeTries < 3) { root.themeTries++; themeRetry.restart() } }
    Timer { id: themeRetry; interval: 800; onTriggered: { borderLua.reload(); borderConf.reload() } }
    Connections {
        target: Color
        ignoreUnknownSignals: true
        function onAccentChanged() { root.themeTries = 0; themeRetry.restart() }
    }

    // ---- the layouts in Hyprland -------------------------------------------------------
    // tableau-service.sh registers the Lua layouts and the thumbnail helper (start), loads
    // them again after a config reload (load), and gives Hyprland its own config back (stop)
    Process {
        id: startTableau
        command: ["bash", root.servicePath, "start"]
        onExited: function(code) {
            if (code !== 0) console.warn("Tableau: runtime startup did not complete")
            root.layoutsLoaded = true
            root.pushSettings(true)
            root.refreshSoon()
        }
    }
    Process {
        id: loadTableau
        command: ["bash", root.servicePath, "load"]
        onExited: { root.pushSettings(true); root.refreshSoon() }
    }
    Process {
        id: stopTableau
        command: ["bash", root.servicePath, "stop"]
    }
    property bool layoutsLoaded: false
    Timer {
        id: reloadTimer
        interval: 500
        onTriggered: { loadTableau.running = false; loadTableau.running = true }
    }

    // ---- settings.conf, the part of the settings the layouts read ----------------------
    // Written only when one of those settings changes, then the layouts are told to read
    // it again. Written through stdin to a temp file and moved into place, so a half
    // written file is never read.
    property string layoutSig: ""
    property string confPending: ""
    onCfgChanged: {
        if (!settingsStore.loaded) return
        const sig = Schema.layoutKey(root.cfg)
        if (sig === root.layoutSig) return
        root.layoutSig = sig
        root.pushSettings(false)
    }
    Connections {
        target: settingsStore
        function onLoadedChanged() { if (settingsStore.loaded) { root.layoutSig = Schema.layoutKey(root.cfg); root.pushSettings(false) } }
    }
    function pushSettings(now) {
        if (!settingsStore.loaded) return
        root.confPending = Schema.confText(root.cfg)
        if (now) confTimer.triggered()
        else confTimer.restart()
    }
    Timer {
        id: confTimer
        interval: 120
        onTriggered: {
            if (root.confPending === "") return
            if (confWriter.running) { confTimer.restart(); return }
            confWriter.payload = root.confPending
            root.confPending = ""
            confWriter.running = true
        }
    }
    Process {
        id: confWriter
        property string payload: ""
        command: ["sh", "-c", 'umask 077; mkdir -p "$1" && cat > "$2.tmp" && mv -f "$2.tmp" "$2"',
                  "sh", root.stateDir, root.stateDir + "/settings.conf"]
        stdinEnabled: true
        onStarted: { write(payload); payload = ""; stdinEnabled = false }
        onExited: function(code) {
            stdinEnabled = true
            if (code !== 0) { console.warn("Tableau: could not write settings.conf"); return }
            if (root.layoutsLoaded) { reloadLua.running = false; reloadLua.running = true }
        }
    }
    Process {
        id: reloadLua
        command: ["hyprctl", "eval", "local t = _G.omarchy_tableau; if t and t.reload_settings then t.reload_settings() end"]
    }

    // ---- which layout each workspace has -----------------------------------------------
    property int activeId: 0
    property string activeMode: ""
    property string activeLabel: ""
    property string activeMonitor: ""
    property var workspaces: []
    property string statusError: ""

    function refreshSoon() { statusTimer.restart() }
    Timer {
        id: statusTimer
        interval: 150
        onTriggered: {
            if (statusProc.running) { statusProc.again = true; return }
            statusProc.running = true
        }
    }
    Process {
        id: statusProc
        property bool again: false
        command: ["python3", root.cyclePath, "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = null
                try { s = JSON.parse(text) } catch (e) { s = null }
                if (!s || typeof s !== "object") return
                if (typeof s.error === "string") { root.statusError = s.error; return }
                root.statusError = ""
                root.activeId = typeof s.active === "number" ? s.active : 0
                root.activeMode = Util.toText(s.mode)
                root.activeLabel = Layouts.isLayout(root.activeMode) ? Layouts.nameOf(root.activeMode) : Util.toText(s.label)
                root.activeMonitor = Util.toText(s.monitor)
                root.workspaces = Array.isArray(s.workspaces) ? s.workspaces.filter(w => w && typeof w.id === "number") : []
            }
        }
        onExited: if (again) { again = false; root.refreshSoon() }
    }

    // a layout for a workspace (the focused one when no id is given)
    function setLayout(mode, workspaceId) {
        if (!Layouts.isLayout(mode)) return
        const cmd = ["python3", root.cyclePath, mode]
        if (typeof workspaceId === "number" && workspaceId >= 1 && workspaceId !== root.activeId)
            cmd.push("--workspace", String(Math.floor(workspaceId)))
        if (workspaceId === undefined || workspaceId === root.activeId) {
            root.activeMode = mode
            root.activeLabel = Layouts.nameOf(mode)
        }
        changer.queue.push(cmd)
        changer.next()
    }
    function cycle(dir) {
        changer.queue.push(["python3", root.cyclePath, dir > 0 ? "next" : "back"])
        changer.next()
    }
    // one change at a time, in the order they were asked for
    Process {
        id: changer
        property var queue: []
        function next() {
            if (running || queue.length === 0) return
            command = queue.shift()
            running = true
        }
        onExited: { root.refreshSoon(); Qt.callLater(changer.next) }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const name = event.name
            if (name === "configreloaded") { reloadTimer.restart(); return }
            if (name.indexOf("workspace") !== -1 || name.indexOf("focusedmon") === 0
                    || name === "openwindow" || name === "closewindow" || name.indexOf("movewindow") === 0)
                root.refreshSoon()
        }
    }

    IpcHandler {
        target: root.pluginId

        function refresh(): string { root.refreshSoon(); return "ok" }
        function next(): string { root.cycle(1); return "next" }
        function back(): string { root.cycle(-1); return "back" }
        function set(layout: string): string {
            const want = Util.toText(layout).toLowerCase()
            for (let i = 0; i < Layouts.list.length; i++) {
                const l = Layouts.list[i]
                if (l.id === want || l.name.toLowerCase() === want || l.id.replace(/^lua:tableau-/, "") === want) {
                    root.setLayout(l.id)
                    return l.name
                }
            }
            return "unknown, try: " + Layouts.list.map(l => l.name.toLowerCase().replace(/ /g, "-")).join(" ")
        }
        function settings(): string { root.ui.tabRequested("settings", true); return "ok" }
        function layouts(): string { root.ui.tabRequested("layouts", true); return "ok" }
        function status(): string {
            return JSON.stringify({ workspace: root.activeId, layout: root.activeLabel, mode: root.activeMode })
        }
    }

    Component.onCompleted: startTableau.running = true
    Component.onDestruction: stopTableau.running = true
}
