#!/usr/bin/env python3
"""cycle_layout.py with stand-ins for hyprctl and the Omarchy commands on the PATH."""
import json, os, subprocess, sys, tempfile, textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILS = []
def check(cond, what):
    if not cond: FAILS.append(what)

tmp = tempfile.mkdtemp(prefix="tableau-cycle-")
bin_dir, state = os.path.join(tmp, "bin"), os.path.join(tmp, "state")
os.makedirs(bin_dir); os.makedirs(state)
log = os.path.join(tmp, "log")
world = os.path.join(tmp, "world.json")   # what hyprctl answers

def stub(name, body):
    path = os.path.join(bin_dir, name)
    with open(path, "w") as f:
        f.write("#!/usr/bin/env python3\n" + textwrap.dedent(body))
    os.chmod(path, 0o755)

stub("hyprctl", f'''
import json, sys
w = json.load(open({world!r}))
open({log!r}, "a").write("hyprctl " + " ".join(sys.argv[1:]) + "\\n")
if sys.argv[1] == "activeworkspace": print(json.dumps(w["active"]))
elif sys.argv[1] == "workspaces": print(json.dumps(w["workspaces"]))
elif sys.argv[1] == "eval":
    expr = " ".join(sys.argv[2:])
    if "dofile" in expr:
        w["loaded"] = not w.get("never_loads", False); json.dump(w, open({world!r}, "w"))
    if "hl.get_workspaces()" in expr:
        if w.get("lua") is None:
            print("[string]:1: attempt to index a nil value"); sys.exit(0)
        path = expr.split("io.open([[", 1)[1].split("]]", 1)[0]
        open(path, "w").write("".join(k + " " + v + "\\n" for k, v in w["lua"].items()))
        print("ok"); sys.exit(0)
    if "assert(_G.omarchy_tableau" in expr and not w.get("loaded", True):
        print("[string]:1: Tableau's layouts are not loaded")   # hyprctl still exits 0
    elif w.get("eval_fails") and "workspace_mode" in expr:
        print("[string]:1: attempt to call a nil value")
    else:
        print("ok")
''')
stub("omarchy-notification-send", f'open({log!r}, "a").write("notify " + " | ".join(__import__("sys").argv[1:]) + "\\n")')
stub("omarchy-shell", f'open({log!r}, "a").write("shell " + " ".join(__import__("sys").argv[1:]) + "\\n")')

def run(*args, layout="dwindle", saved=None, eval_fails=0, loaded=True, never_loads=False, lua=None):
    ws = {"id": 2, "name": "2", "monitor": "eDP-1", "windows": 3, "tiledLayout": layout}
    json.dump({"active": ws, "workspaces": [ws, {"id": 12, "name": "2", "monitor": "HDMI-A-1", "windows": 1, "tiledLayout": "dwindle"}],
               "eval_fails": eval_fails, "loaded": loaded, "never_loads": never_loads, "lua": lua}, open(world, "w"))
    open(log, "w").close()
    env = dict(os.environ, PATH=bin_dir + ":/usr/bin:/bin", XDG_STATE_HOME=state)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "cycle_layout.py"), *args], env=env,
                       capture_output=True, text=True, timeout=20)
    import time
    for _ in range(50):   # the shell is told in the background
        if "shell " in open(log).read() or r.returncode: break
        time.sleep(0.05)
    return r, open(log).read()

def mode_file(n):
    p = os.path.join(state, "omarchy/workspace-layouts", f"{n}.lua")
    return open(p).read() if os.path.exists(p) else None

def conf(text):
    os.makedirs(os.path.join(state, "hypr-tableau"), exist_ok=True)
    open(os.path.join(state, "hypr-tableau/settings.conf"), "w").write(text)

r, out = run("next", layout="dwindle")
check(r.returncode == 0, "next works")
check('mode = "scrolling"' in (mode_file(2) or ""), "dwindle → scrolling saved")
check("notify Workspace layout | Scrolling" in out, "announced")
check("shell io.github.qempexe.tableau refresh" in out, "the bar is told")

conf("cycle=dwindle,lua:tableau-portrait,lua:tableau-bento\nnotify=0\n")
r, out = run("next", layout="dwindle")
check('lua:tableau-portrait"' in mode_file(2), "the cycle skips layouts left out")
check("notify" not in out, "no notification when switched off")
r, out = run("back", layout="dwindle")
check('lua:tableau-bento"' in mode_file(2), "back wraps to the last one in the cycle")
r, out = run("next", layout="lua:tableau-mosaic")
check('"dwindle"' in mode_file(2), "from a layout outside the cycle, the next one after it in the full list: " + mode_file(2))
r, out = run("back", layout="lua:tableau-mosaic")
check('lua:tableau-bento"' in mode_file(2), "and back from it, the one before it: " + mode_file(2))

conf("cycle=dwindle\n")
r, out = run("next", layout="dwindle")
check('"scrolling"' in mode_file(2), "a cycle of one is ignored, every layout is used")

r, out = run("lua:tableau-triptych", "--workspace", "12")
check('workspace = "12", mode = "lua:tableau-triptych"' in (mode_file(12) or ""), "another workspace by id")
check("Workspace 2: Triptych" in out, "names the workspace it changed: " + out)

r, out = run('lua:tableau-portrait"}) os.execute("x") --')
check(r.returncode == 1 and "Unknown layout" in out, "anything not a known layout is refused")
r, out = run("dwindle", "--workspace", "0")
check(r.returncode == 1, "workspace 0 is refused")
r, out = run("dwindle", "--workspace", "x")
check(r.returncode == 2, "a workspace that isn't a number is refused")

before = mode_file(2)
r, out = run("lua:tableau-spread", eval_fails=1)
check(r.returncode == 1 and mode_file(2) == before, "a Lua error (hyprctl still exits 0) puts the saved file back")
check("attempt to call a nil value" in out, "and says what went wrong: " + out)

r, out = run("lua:tableau-spread", loaded=False)
check(r.returncode == 0 and "tableau-spread" in mode_file(2), "layouts that aren't loaded are loaded again first")
check("hyprctl eval _G.tableau_runtime = true; dofile(" in out, "through tableau-service.sh load")
before = mode_file(2)
r, out = run("lua:tableau-mosaic", loaded=False, never_loads=True)
check(r.returncode == 1 and mode_file(2) == before and "errors.log" in out, "when they still won't load, it says so and keeps the old layout: " + out[-200:])
r, out = run("scrolling", loaded=False, never_loads=True)
check(r.returncode == 0 and '"scrolling"' in mode_file(2), "Hyprland's own layouts don't need Tableau's")

r, out = run("--status", layout="lua:tableau-gallery-left")
st = json.loads(r.stdout)
check(st["active"] == 2 and st["label"] == "Gallery Left", f"status of the active workspace {st}")
check([w["id"] for w in st["workspaces"]] == [2, 12], f"workspaces listed {st['workspaces']}")

# hyprctl names every Lua layout after the first one registered (Portrait)
import shutil
open(os.path.join(state, "omarchy/workspace-layouts/2.lua"), "w").write('o.workspace_mode({ workspace = "2", mode = "lua:tableau-bento" })\n')
r, out = run("--status", layout="lua:tableau-portrait")
check(json.loads(r.stdout)["label"] == "Bento", "the saved mode says which Lua layout it is: " + r.stdout[:120])
r, out = run("--status", layout="lua:tableau-portrait", lua={"2": "lua:tableau-spiral", "12": "dwindle"})
check(json.loads(r.stdout)["label"] == "Spiral", "and Lua's own answer wins when it gives one: " + r.stdout[:120])
conf("cycle=" + ",".join(["dwindle", "lua:tableau-portrait", "lua:tableau-bento", "lua:tableau-mosaic"]) + "\n")
open(os.path.join(state, "omarchy/workspace-layouts/2.lua"), "w").write('o.workspace_mode({ workspace = "2", mode = "lua:tableau-bento" })\n')
r, out = run("next", layout="lua:tableau-portrait")
check('"lua:tableau-mosaic"' in mode_file(2), "Super + L goes on from Bento, not from Portrait: " + mode_file(2))

if FAILS:
    print("\n".join(FAILS)); print(len(FAILS), "failures"); sys.exit(1)
print("ok")
