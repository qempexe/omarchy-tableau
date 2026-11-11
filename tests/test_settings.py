#!/usr/bin/env python3
"""settings.conf, the outline rules and the tile tags, through the Hyprland stand-in."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_layouts import fresh

FAILS = []
def check(cond, what):
    if not cond: FAILS.append(what)

def rules(L):
    return [dict(r) for r in L.eval("require('hl_mock').rules").values()]

def live(L):
    """the rules still switched on, by kind, with their latest settings"""
    out, off = {}, set()
    for r in rules(L):
        if r.get("enabled") is False: off.add(r["name"]); continue
    for r in rules(L):
        if "name" in r and r["name"] not in off and r.get("enabled") is not False:
            out[r["name"].rsplit("-", 1)[0]] = r
    return out

L, mock, state = fresh()
now = live(L)
check(set(now) == {"tableau-tile", "tableau-thumb", "tableau-hover", "tableau-swap", "tableau-confine"}, f"rules at load: {set(now)}")
tile = now["tableau-tile"]
check(tile["border_size"] == 2, "default outline is 2 px")
check(tile["border_color"] == "rgba(33ccffee) rgba(00ff99ee) 45deg rgba(33ccffee) rgba(00ff99ee) 45deg",
      "unfocused windows get the focused gradient: " + tile["border_color"])
check(dict(tile["match"]) == {"tag": "tableau-tile"}, "tile rule matches the tag")
check(now["tableau-thumb"]["opacity"] == "1.0 0.72", "thumbnail fade")

# settings from the panel, odd values clamped, unknown keys and code ignored
os.makedirs(os.path.join(state, "hypr-tableau"), exist_ok=True)
with open(os.path.join(state, "hypr-tableau", "settings.conf"), "w") as f:
    f.write("outline=7\nothers=theme\ndim=0.05\nflash=0\npane=2\ngap=-4\nfull_size=MPV, steam ,,\n"
            "os.execute('touch /tmp/claude-0/pwned')\nbogus=1\n")
L.execute("_G.omarchy_tableau.reload_settings()")
now = live(L)
check(now["tableau-tile"]["border_size"] == 7, "outline 7")
check("border_color" not in now["tableau-tile"], "theme keeps Omarchy's colors")
check(now["tableau-thumb"]["opacity"] == "1.0 0.20", "fade clamped to 20%: " + now["tableau-thumb"]["opacity"])
check(len([r for r in rules(L) if r.get("enabled") is False]) == 5, "the old rules are switched off")
check(now["tableau-confine"]["confine_pointer"] is True and dict(now["tableau-confine"]["match"]) == {"tag": "tableau-confine"},
      "the pointer stays inside windows with the confine tag")
check(not os.path.exists("/tmp/claude-0/pwned"), "settings.conf is never run")

with open(os.path.join(state, "hypr-tableau", "settings.conf"), "w") as f:
    f.write("outline=0\nothers=hidden\n")
L.execute("_G.omarchy_tableau.reload_settings()")
now = live(L)
check(now["tableau-tile"]["border_color"].endswith("rgba(00000000) 0deg"), "hidden: " + now["tableau-tile"]["border_color"])

# tile tags: on for tiled windows of a Tableau layout, off elsewhere and for floating ones
ws, wins = mock.workspace(1, "lua:tableau-portrait", 3)
wins[3].floating = True
L.execute("_G.omarchy_tableau.sync_pointer_guard()")
tags = [list(w.tags.values()) for w in wins.values()]
check("tableau-tile" in tags[0] and "tableau-tile" in tags[1], f"tiled windows tagged {tags}")
check("tableau-tile" not in tags[2], "a floating window isn't tagged")
ws.tiled_layout = "dwindle"
L.execute("_G.omarchy_tableau.sync_pointer_guard()")
check(all("tableau-tile" not in list(w.tags.values()) for w in wins.values()), "tags come off on dwindle")

# games keep the pointer: Steam and Wine games and gamescope by themselves, others from the list
def confined(wins):
    L.execute("_G.omarchy_tableau.sync_pointer_guard()")
    return ["tableau-confine" in list(w.tags.values()) for w in wins.values()]
with open(os.path.join(state, "hypr-tableau", "settings.conf"), "w") as f:
    f.write("confine_apps=App2\n")
L.execute("_G.omarchy_tableau.reload_settings()")
ws, wins = mock.workspace(9, "lua:tableau-portrait", 4)
wins[1]["class"] = "steam_app_582660"; wins[3]["class"] = "BlackDesert64.exe"; wins[4]["class"] = "kitty"
check(confined(wins) == [True, True, True, False], f"games and listed classes are confined, a terminal isn't: {confined(wins)}")
wins[4]["class"] = "gamescope"; wins[1].floating = True
check(confined(wins) == [False, True, True, True], f"gamescope too, a floating game isn't: {confined(wins)}")
with open(os.path.join(state, "hypr-tableau", "settings.conf"), "w") as f:
    f.write("confine=0\nconfine_apps=App2\n")
L.execute("_G.omarchy_tableau.reload_settings()")
check(confined(wins) == [False, True, False, False], f"switched off, only the listed class is left: {confined(wins)}")
ws.tiled_layout = "dwindle"
check(confined(wins) == [False, False, False, False], "and nothing is confined on dwindle")

# the never-a-miniature list
with open(os.path.join(state, "hypr-tableau", "settings.conf"), "w") as f:
    f.write("full_size=App2\n")
L.execute("_G.omarchy_tableau.reload_settings()")
L.execute("""thumbs_set = {}
  hl.plugin.stagethumbs = { set = function(a, w, h) thumbs_set[a] = true end, clear = function(a) thumbs_set[a] = nil end }""")
mock.workspace(1, "lua:tableau-portrait", 3)
mock.run("tableau-portrait", L.table_from({"x": 0, "y": 0, "w": 1920, "h": 1080}))
shown = sorted(L.eval("thumbs_set").keys())
check(shown == ["a3"], f"app2 stays a real window, app3 is a miniature: {shown}")

# Super + minus expands and Super + = shrinks, in small steps of `step`, on every family
area = L.table_from({"x": 0, "y": 0, "w": 1920, "h": 1080})
for name in ["tableau-portrait", "tableau-diptych-left", "tableau-triptych", "tableau-bento", "tableau-mosaic",
             "tableau-strip", "tableau-spiral", "tableau-gallery-right"]:
    mock.workspace(5, "lua:" + name, 4)
    before = dict(mock.run(name, area)[101])
    L.execute("_G.omarchy_tableau.resize(1, 1, 100)()")
    one = dict(mock.run(name, area)[101])
    for _ in range(9): L.execute("_G.omarchy_tableau.resize(1, 1, 100)()")
    ten = dict(mock.run(name, area)[101])
    a0, a1, a10 = before["w"] * before["h"], one["w"] * one["h"], ten["w"] * ten["h"]
    check(a0 < a1 < a10, f"{name}: Super + minus grows the focused window, more while held {a0} {a1} {a10}")
    check((a1 - a0) / (1920 * 1080) < 0.03, f"{name}: one press is a small step ({(a1 - a0) / (1920 * 1080):.3f})")
    for _ in range(10): L.execute("_G.omarchy_tableau.resize(-1, 1, 100)()")
    back = dict(mock.run(name, area)[101])
    check(abs(back["w"] * back["h"] - a0) < 200, f"{name}: Super + = takes it back {a0} {back}")

# elsewhere the keys resize as Omarchy's do, once per press: a held key doesn't repeat there
mock.run_timers()   # let go of the keys pressed above
mock.workspace(6, "dwindle", 2)
L.execute("require('hl_mock').dispatched = {}")
for _ in range(3): L.execute("_G.omarchy_tableau.resize(1, 1, 100)()")
resizes = [d for d in L.eval("require('hl_mock').dispatched").values() if d.kind == "window.resize"]
check(len(resizes) == 1 and resizes[0].args.x == -100, f"one Omarchy-size resize for a held key off Tableau ({len(resizes)})")
mock.run_timers()
L.execute("_G.omarchy_tableau.resize(-1, 4, 300)()")
resizes = [d for d in L.eval("require('hl_mock').dispatched").values() if d.kind == "window.resize"]
check(len(resizes) == 2 and resizes[1].args.x == 300, "a new press after letting go resizes again")

# the step comes from settings.conf
with open(os.path.join(state, "hypr-tableau", "settings.conf"), "w") as f:
    f.write("step=0.05\n")
L.execute("_G.omarchy_tableau.reload_settings()")
mock.workspace(7, "lua:tableau-diptych-left", 3)
before = dict(mock.run("tableau-diptych-left", area)[101])
L.execute("_G.omarchy_tableau.resize(1, 1, 100)()")
after = dict(mock.run("tableau-diptych-left", area)[101])
check(abs((after["w"] - before["w"]) - 0.05 * 1920) < 2, f"a 5% step {before['w']} -> {after['w']}")

# the keys: resize repeats while held; Super + Alt + L goes back, as in Omarchy
opts = L.eval("require('hl_mock').bind_opts")
check(all(opts[k] and opts[k].repeating for k in ["SUPER + code:20", "SUPER + ALT + code:21", "SUPER + CTRL + code:20"]),
      "the resize keys repeat while held")
L.execute("io.popen = function() return nil end")  # no saved modes to replay here
L.execute("dofile(%r)" % (os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tableau.lua")))
binds = L.eval("require('hl_mock').binds")
check(all(binds[k] for k in ["SUPER + L", "SUPER + SHIFT + L", "SUPER + ALT + L", "SUPER + CTRL + L"]), "the layout keys, Super + Alt + L too")

if FAILS:
    print("\n".join(FAILS)); print(len(FAILS), "failures"); sys.exit(1)
print("ok")
