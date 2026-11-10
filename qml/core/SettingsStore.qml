import QtQuick
import Quickshell
import Quickshell.Io
import "../js/Schema.js" as Schema

// The settings, kept in memory (instant) and saved to tableau.json in the Omarchy config
// folder. The file is watched, so a hand edit applies live. Nothing is sent to
// `omarchy bar set`: that rewrites the shell config and makes the whole shell reload.
Item {
    id: root

    // hand edits are picked up live (the file is watched below)
    property string stateDir: (Quickshell.env("XDG_CONFIG_HOME")
        || Quickshell.env("HOME") + "/.config") + "/omarchy"
    property string path: stateDir + "/tableau.json"

    property var values: ({})
    property bool loaded: false

    // Edits made before settings.json has been read. They are kept in memory
    // and merged over the file once it loads, so a very early write can never
    // replace the saved settings with a nearly empty file.
    property var pending: ({})
    property bool pendingAll: false     // a reset happened before the first load

    signal changed()
    // Which key was just edited ("*" = many keys or an external edit).
    signal keyChanged(string key)

    // only real settings, so odd names in a hand-edited file never end up in here
    function known(obj) {
        const out = {}
        for (let i = 0; i < Schema.settingKeys.length; i++) {
            const k = Schema.settingKeys[i]
            if (obj[k] !== undefined && typeof obj[k] !== "function") out[k] = obj[k]
        }
        return out
    }

    function get(key) {
        let v = values[key]
        return v === undefined ? null : v
    }

    function set(key, value) {
        let next = {}
        for (let k in values) next[k] = values[k]
        if (value === null || value === undefined) delete next[key]
        else next[key] = value
        values = next
        if (!loaded && !pendingAll) {
            let p = {}
            for (let pk in pending) p[pk] = pending[pk]
            p[key] = (value === undefined) ? null : value
            pending = p
        }
        persist()
        changed()
        keyChanged(key)
    }

    // Several keys at once (a preset): one write, one change signal.
    function setMany(patch) {
        let next = {}
        for (let k in values) next[k] = values[k]
        for (let pk in patch) {
            if (patch[pk] === null || patch[pk] === undefined) delete next[pk]
            else next[pk] = patch[pk]
        }
        values = next
        if (!loaded && !pendingAll) {
            let p = {}
            for (let ek in pending) p[ek] = pending[ek]
            for (let mk in patch) p[mk] = (patch[mk] === undefined) ? null : patch[mk]
            pending = p
        }
        persist()
        changed()
        keyChanged("*")
    }

    function reset() {
        values = ({})
        if (!loaded) pendingAll = true
        persist()
        changed()
        keyChanged("*")
    }

    // Back to the given defaults (stored explicitly, so nothing else shows through).
    function resetAll(defaults) {
        let next = {}
        for (let k in defaults) next[k] = defaults[k]
        values = next
        if (!loaded) pendingAll = true
        persist()
        changed()
        keyChanged("*")
    }

    // The last few texts we wrote ourselves. The file watcher reports each of our
    // own writes back a moment later; absorbing such an echo would roll the
    // settings back to an older state (a slider drag or typing would stutter or
    // jump back), so echoes are recognised and skipped.
    property var recent: []

    // Disk writes are coalesced: the UI reads `values` from memory, so nothing
    // has to hit the disk per tick of a slider drag or per typed character.
    property bool dirty: false

    property double lastWrite: 0

    // First change is written right away (so a click can never be lost); a burst
    // of changes after it is written once, shortly after the last one.
    function persist() {
        dirty = true
        if (!loaded) return              // written right after the file is read
        if (Date.now() - lastWrite > 300) writeNow()
        else writeTimer.restart()
    }

    function writeNow() {
        if (!dirty) return
        dirty = false
        lastWrite = Date.now()
        let text = JSON.stringify(values, null, 2) + "\n"
        let r = recent.slice(-7)
        r.push(text)
        recent = r
        echoTimer.restart()
        file.setText(text)
    }

    function absorb(text) {
        let raw = String(text || "")
        if (loaded) {
            // While our own write is pending or still settling, whatever the file
            // watcher reports is ours (it can even be a half-written or empty
            // file). Taking it in would flash the old values back.
            if (dirty || writeTimer.running || echoTimer.running) return
            if (recent.indexOf(raw) >= 0) return
        }
        let next = null
        try {
            const parsed = JSON.parse(raw)
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) next = root.known(Schema.migrate(parsed))
        } catch (e) { }
        let wasLoaded = loaded
        if (!wasLoaded) {
            // First read: saved file + anything edited before it arrived.
            let merged = {}
            if (!pendingAll && next !== null)
                for (let fk in next) merged[fk] = next[fk]
            if (pendingAll) {
                for (let vk in values) merged[vk] = values[vk]
            } else {
                for (let pk in pending) {
                    if (pending[pk] === null) delete merged[pk]
                    else merged[pk] = pending[pk]
                }
            }
            let touched = pendingAll || Object.keys(pending).length > 0
            values = merged
            pending = ({})
            pendingAll = false
            loaded = true
            if (touched) { dirty = true; writeNow() }
            return
        }
        if (next === null) return                  // empty or unreadable: keep what we have
        if (JSON.stringify(next) === JSON.stringify(values)) return
        values = next                              // edited elsewhere (another bar, by hand)
        changed()
        keyChanged("*")
    }

    Component.onCompleted: mkdir.running = true
    Component.onDestruction: writeNow()

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.stateDir]
        onExited: file.reload()
    }

    Timer { id: echoTimer; interval: 1500; onTriggered: root.recent = [] }
    Timer { id: writeTimer; interval: 250; onTriggered: root.writeNow() }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        // text is a function in FileView, so it must be called.
        onTextChanged: root.absorb(text())
        onLoaded: root.absorb(text())
        // No file yet (first run): nothing to restore, but start saving.
        onLoadFailed: function(error) { root.absorb("") }
    }
}
