#!/usr/bin/env python3
"""Runs every Tableau layout outside Hyprland (Lua 5.5 through lupa) and checks the boxes."""
import os, sys, tempfile, itertools
from lupa import lua55

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILS = []

def check(cond, what):
    if not cond:
        FAILS.append(what)

def fresh(state=None):
    state = state or tempfile.mkdtemp(prefix="tableau-test-")
    os.environ["XDG_STATE_HOME"] = state
    L = lua55.LuaRuntime(unpack_returned_tuples=True)
    L.execute("package.path = %r .. ';' .. package.path" % (ROOT + "/tests/?.lua"))
    mock = L.execute("return (require('hl_mock'))")
    L.execute("dofile(%r)" % (ROOT + "/hypr/tableau.lua"))
    return L, mock, state

def boxes(mock, L, name, n, area):
    mock.workspace(1, "lua:" + name, n)
    placed = mock.run(name, L.table_from(area))
    return {k: dict(v) for k, v in placed.items()}

def overlap(a, b):
    return max(0, min(a["x"] + a["w"], b["x"] + b["w"]) - max(a["x"], b["x"])) * \
           max(0, min(a["y"] + a["h"], b["y"] + b["h"]) - max(a["y"], b["y"]))

def main():
    L, mock, _ = fresh()
    names = sorted(mock.layouts.keys())
    tiled = {"tableau-strip", "tableau-column", "tableau-spiral",
             "tableau-diptych-left", "tableau-diptych-right", "tableau-diptych-top", "tableau-diptych-bottom",
             "tableau-triptych", "tableau-bento"}
    for area in ({"x": 0, "y": 0, "w": 1920, "h": 1080}, {"x": 1920, "y": 30, "w": 2560, "h": 1410},
                 {"x": 0, "y": 0, "w": 1080, "h": 1920}):
        for name in names:
            for n in range(1, 10):
                b = boxes(mock, L, name, n, area)
                check(len(b) == n, f"{name} n={n}: placed {len(b)}")
                for k, v in b.items():
                    ok = all(v[c] == v[c] and abs(v[c]) < 1e7 for c in "xywh") and v["w"] > 0 and v["h"] > 0
                    check(ok, f"{name} n={n}: bad box {v}")
                    inside = v["x"] >= area["x"] - 0.5 and v["y"] >= area["y"] - 0.5 and \
                        v["x"] + v["w"] <= area["x"] + area["w"] + 0.5 and v["y"] + v["h"] <= area["y"] + area["h"] + 0.5
                    check(inside, f"{name} n={n} {area['w']}x{area['h']}: box outside the area {v}")
                vals = list(b.values())
                for p, q in itertools.combinations(vals, 2):
                    check(overlap(p, q) < 1, f"{name} n={n}: windows overlap {p} {q}")
                if name in tiled:
                    total = sum(v["w"] * v["h"] for v in vals)
                    check(abs(total - area["w"] * area["h"]) < n * 4, f"{name} n={n}: leaves space unused ({total})")
    # live miniatures: each one has exactly the shape of the window it pretends to be,
    # and that size doesn't depend on how large the main pane was made
    L.execute("""
      thumbs_set = {}
      hl.plugin.stagethumbs = {
        set = function(a, w, h) thumbs_set[a] = { w = w, h = h } end,
        clear = function(a) thumbs_set[a] = nil end,
      }""")
    area = {"x": 0, "y": 0, "w": 1920, "h": 1080}
    for name in ["tableau-portrait", "tableau-landscape", "tableau-centerpiece", "tableau-gallery-right",
                 "tableau-gallery-left", "tableau-gallery-top", "tableau-gallery-bottom"]:
        for n in range(2, 10):
            L.execute("thumbs_set = {}")
            b = boxes(mock, L, name, n, area)
            sizes = L.eval("thumbs_set")
            check(len(list(sizes.keys())) == n - 1, f"{name} n={n}: {len(sizes)} miniatures")
            for w in mock.windows().values():
                full = sizes[w.address]
                if full is None: continue
                box = b[w.stable_id]
                check(abs(box["w"] / box["h"] - full.w / full.h) < 0.01 * full.w / full.h,
                      f"{name} n={n}: miniature squashed {box} for {full.w}x{full.h}")
        if "gallery" in name:
            L.execute("thumbs_set = {}"); b1 = boxes(mock, L, name, 4, area)
            before = {k: (v.w, v.h) for k, v in L.eval("thumbs_set").items()}
            L.execute("_G.omarchy_tableau.resize(-300)()")
            L.execute("thumbs_set = {}"); b2 = mock.run(name, L.table_from(area))
            after = {k: (v.w, v.h) for k, v in L.eval("thumbs_set").items()}
            main1, main2 = b1[101], dict(b2[101])
            check(abs(main1["w"] * main1["h"] - main2["w"] * main2["h"]) > 1000, f"{name}: the resize keys did nothing")
            check(before == after, f"{name}: miniatures changed size with the main pane {before} {after}")
            L.execute("_G.omarchy_tableau.resize(300)()")
    print("layouts:", ", ".join(n.replace("tableau-", "") for n in names))
    return names

if __name__ == "__main__":
    main()
    if FAILS:
        print("\n".join(FAILS[:40])); print(len(FAILS), "failures"); sys.exit(1)
    print("ok")
