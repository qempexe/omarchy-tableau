// Schema.js and Layouts.js outside QML: defaults, checking, settings.conf, and the
// layout list agreeing with cycle_layout.py
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const js = name => fs.readFileSync(path.join(__dirname, "../qml/js", name), "utf8")
  .replace(/^\.pragma library$/m, "").replace(/^\.import .*$/mg, "")
const ctx = {}
vm.createContext(ctx)
vm.runInContext("var Util = (function(){" + js("Util.js") + "; return { toText }})();" +
  "var Layouts = (function(){" + js("Layouts.js") + "; return { list, ids, byId, isLayout, nameOf, step, art }})();" +
  js("Schema.js") + "; this.S = { defaults, resolve, clean, confText, cleanCycle, className, layoutKey, groups, Layouts, format }", ctx)
const S = ctx.S
let n = 0
const ok = (what, fn) => { fn(); n++; console.log("  ok   " + what) }

ok("defaults resolve", () => {
  const c = S.resolve({})
  assert.strictEqual(c.outline, 2)
  assert.strictEqual(c.others, "same")
  assert.strictEqual(c.cycle.length, S.Layouts.ids.length)
  assert.deepStrictEqual(Array.from(c.fullSize), [])
})

ok("odd values fall back or are clamped", () => {
  const c = S.resolve({ outline: "999", others: "rainbow", dim: -1, pane: "x", cycle: ["lua:tableau-bento", "nope"],
                        fullSize: ["MPV", "a,b", "x\ny=1", "<b>", "mpv"], __proto__: { evil: 1 } })
  assert.strictEqual(c.outline, 20)
  assert.strictEqual(c.others, "same")
  assert.strictEqual(c.dim, 0.2)
  assert.strictEqual(c.pane, 0.62)
  assert.strictEqual(c.cycle.length, S.Layouts.ids.length, "fewer than two in the cycle means all")
  assert.deepStrictEqual(Array.from(c.fullSize), ["mpv", "ab", "xy1", "b"])
})

ok("the cycle keeps the usual order", () => {
  assert.deepStrictEqual(Array.from(S.cleanCycle(["lua:tableau-spread", "dwindle", "dwindle"])), ["dwindle", "lua:tableau-spread"])
})

ok("settings.conf has one line per key and nothing else", () => {
  const c = S.resolve({ fullSize: ["steam", "evil\nos.execute('x')", "a=b"], outline: 6, flash: false, notify: false,
                        confineApps: ["Minecraft", "x\ny"] })
  const lines = S.confText(c).trim().split("\n").filter(l => !l.startsWith("#"))
  const keys = lines.map(l => l.split("=")[0])
  assert.deepStrictEqual(keys, ["outline", "others", "dim", "flash", "pane", "middle", "gap", "step", "notify", "cycle", "full_size", "confine", "confine_apps"])
  for (const l of lines) assert.match(l, /^[a-z_]+=[a-z0-9.,:_+ -]*$/, l)
  assert.ok(lines.includes("outline=6") && lines.includes("flash=0") && lines.includes("notify=0"))
  assert.ok(lines.includes("full_size=steam,evilos.executex,ab"), lines.join("|"))
  assert.ok(lines.includes("confine=1") && lines.includes("confine_apps=minecraft,xy"), lines.join("|"))
  assert.ok(S.confText(S.resolve({ confine: false })).includes("\nconfine=0\n"))
})

ok("only the layout settings count as a change for Hyprland", () => {
  const a = S.resolve({}), b = S.resolve({ opacity: 60, barIcon: "x" }), c = S.resolve({ gap: 8 })
  assert.strictEqual(S.layoutKey(a), S.layoutKey(b))
  assert.notStrictEqual(S.layoutKey(a), S.layoutKey(c))
})

ok("every layout has a picture inside the frame", () => {
  for (const id of S.Layouts.ids) {
    const boxes = S.Layouts.art(id)
    assert.ok(boxes.length > 0 && boxes.some(b => b.main), id)
    for (const b of boxes) assert.ok(b.w > 0 && b.h > 0 && b.y >= 0 && b.y + b.h <= 1.0001, id)
  }
})

ok("the layout list is the one cycle_layout.py and the Lua know", () => {
  const py = fs.readFileSync(path.join(__dirname, "../cycle_layout.py"), "utf8")
  const ids = [...py.matchAll(/^\s+\("([^"]+)", "([^"]+)"\),$/mg)].map(m => [m[1], m[2]])
  assert.strictEqual(JSON.stringify(ids), JSON.stringify(S.Layouts.list.map(l => [l.id, l.name])))
  const lua = fs.readFileSync(path.join(__dirname, "../hypr/tableau.lua"), "utf8")
  const registered = [...lua.matchAll(/register_layout\("(tableau-[a-z-]+)"/g)].map(m => "lua:" + m[1]).sort()
  assert.strictEqual(JSON.stringify(registered), JSON.stringify(S.Layouts.ids.filter(i => i.startsWith("lua:")).sort()))
})

ok("the resize step", () => {
  assert.strictEqual(S.resolve({}).step, 0.01)
  assert.strictEqual(S.resolve({ step: 5 }).step, 0.1)
  assert.strictEqual(S.resolve({ step: "x" }).step, 0.01)
  assert.ok(S.confText(S.resolve({ step: 0.005 })).includes("\nstep=0.005\n"))
})

console.log(n + " checks passed")
