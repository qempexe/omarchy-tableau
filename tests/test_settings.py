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
check(set(now) == {"tableau-tile", "tableau-thumb", "tableau-hover", "tableau-swap"}, f"rules at load: {set(now)}")
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
check(len([r for r in rules(L) if r.get("enabled") is False]) == 4, "the old rules are switched off")
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

# Super + minus (dx < 0) expands, as Omarchy's own binding says, on every family
area = L.table_from({"x": 0, "y": 0, "w": 1920, "h": 1080})
for name in ["tableau-portrait", "tableau-diptych-left", "tableau-triptych", "tableau-bento", "tableau-mosaic",
             "tableau-strip", "tableau-spiral", "tableau-gallery-right"]:
    mock.workspace(5, "lua:" + name, 4)
    before = dict(mock.run(name, area)[101])
    L.execute("_G.omarchy_tableau.resize(-100)()")
    after = dict(mock.run(name, area)[101])
    check(after["w"] * after["h"] > before["w"] * before["h"] + 100, f"{name}: Super + minus grows the focused window {before} {after}")
    L.execute("_G.omarchy_tableau.resize(100)()")
    back = dict(mock.run(name, area)[101])
    check(abs(back["w"] * back["h"] - before["w"] * before["h"]) < 50, f"{name}: Super + = undoes it")

if FAILS:
    print("\n".join(FAILS)); print(len(FAILS), "failures"); sys.exit(1)
print("ok")
