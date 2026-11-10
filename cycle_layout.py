#!/usr/bin/env python3
"""Apply and persist Tableau's layouts through Omarchy's workspace modes.

  cycle_layout.py [next|back|<mode>] [--workspace ID]   change a workspace's layout
  cycle_layout.py --status                              print the workspaces as JSON
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


CHOICES = [
    ("dwindle", "Dwindle"),
    ("scrolling", "Scrolling"),
    ("floating", "Floating"),
    ("lua:tableau-portrait", "Portrait"),
    ("lua:tableau-landscape", "Landscape"),
    ("lua:tableau-centerpiece", "Centerpiece"),
    ("lua:tableau-diptych-left", "Diptych Left"),
    ("lua:tableau-diptych-right", "Diptych Right"),
    ("lua:tableau-diptych-top", "Diptych Top"),
    ("lua:tableau-diptych-bottom", "Diptych Bottom"),
    ("lua:tableau-triptych", "Triptych"),
    ("lua:tableau-bento", "Bento"),
    ("lua:tableau-mosaic", "Mosaic"),
    ("lua:tableau-strip", "Strip"),
    ("lua:tableau-column", "Column"),
    ("lua:tableau-spiral", "Spiral"),
    ("lua:tableau-gallery-right", "Gallery Right"),
    ("lua:tableau-gallery-bottom", "Gallery Bottom"),
    ("lua:tableau-gallery-left", "Gallery Left"),
    ("lua:tableau-gallery-top", "Gallery Top"),
    ("lua:tableau-spread", "Spread"),
]
IDS = [ident for ident, _ in CHOICES]
NAMES = dict(CHOICES)
PLUGIN_ID = "io.github.qempexe.tableau"


def run(args, timeout=4):
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout)


def state_home():
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def settings():
    """settings.conf from the Tableau panel: which layouts Super+L goes through, and
    whether a change is announced. Only known values are taken."""
    out = {"cycle": list(IDS), "notify": True}
    try:
        text = (state_home() / "hypr-tableau/settings.conf").read_text()[:65536]
    except OSError:
        return out
    for line in text.splitlines():
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if key == "cycle":
            wanted = {item.strip() for item in value.split(",")}
            cycle = [ident for ident in IDS if ident in wanted]
            if len(cycle) >= 2:
                out["cycle"] = cycle
        elif key == "notify":
            out["notify"] = value != "0"
    return out


def notify(message):
    try:
        run(["omarchy-notification-send", "Workspace layout", message], timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        pass


def tell_shell():
    """Let the bar button show the new layout right away. Fire and forget."""
    try:
        subprocess.Popen(["omarchy-shell", PLUGIN_ID, "refresh"], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


def saved_mode(path):
    try:
        text = path.read_text()[:4096]
    except OSError:
        return None
    match = re.search(r'mode\s*=\s*"([^"]+)"', text)
    return match.group(1) if match else None


def persist(path, workspace_id, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = f'o.workspace_mode({{ workspace = "{workspace_id}", mode = "{mode}" }})\n'
    fd, temp_name = tempfile.mkstemp(prefix=f".{workspace_id}-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise


def hypr_json(*args):
    result = run(["hyprctl", *args, "-j"])
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Hyprland did not answer")
    return json.loads(result.stdout)


def mode_of(workspace, modes_dir):
    """The mode a workspace is in: floating when Omarchy saved that, else its layout."""
    workspace_id = int(workspace.get("id", 0))
    persisted = saved_mode(modes_dir / f"{workspace_id}.lua") if workspace_id >= 1 else None
    layout = str(workspace.get("tiledLayout", workspace.get("tiled_layout", "")))
    if persisted == "floating":
        return "floating"
    if layout not in NAMES and persisted in NAMES:
        return persisted
    return layout


def status(modes_dir):
    active = hypr_json("activeworkspace")
    listed = hypr_json("workspaces")
    rows = {}
    for ws in listed if isinstance(listed, list) else []:
        workspace_id = int(ws.get("id", 0))
        if workspace_id < 1:
            continue
        mode = mode_of(ws, modes_dir)
        rows[workspace_id] = {"id": workspace_id, "name": str(ws.get("name", workspace_id))[:32],
                              "monitor": str(ws.get("monitor", ""))[:64], "windows": int(ws.get("windows", 0)),
                              "mode": mode, "label": NAMES.get(mode, mode[:40])}
    # workspaces that are empty now but have a saved layout
    try:
        for path in sorted(modes_dir.glob("*.lua"))[:200]:
            if not path.stem.isdigit() or int(path.stem) in rows:
                continue
            mode = saved_mode(path)
            if mode in NAMES:
                rows[int(path.stem)] = {"id": int(path.stem), "name": path.stem, "monitor": "", "windows": 0,
                                        "mode": mode, "label": NAMES[mode]}
    except OSError:
        pass
    active_id = int(active.get("id", 0))
    active_mode = mode_of(active, modes_dir)
    return {"active": active_id, "mode": active_mode, "label": NAMES.get(active_mode, active_mode[:40]),
            "monitor": str(active.get("monitor", ""))[:64],
            "workspaces": [rows[k] for k in sorted(rows)]}


def main(argv):
    modes_dir = state_home() / "omarchy/workspace-layouts"
    if argv[:1] == ["--status"]:
        try:
            print(json.dumps(status(modes_dir)))
            return 0
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
            print(json.dumps({"error": str(error)[:200]}))
            return 1

    args = list(argv)
    target = None
    if "--workspace" in args:
        at = args.index("--workspace")
        try:
            target = int(args[at + 1])
        except (IndexError, ValueError):
            notify("Could not change layout: --workspace needs a number")
            return 2
        del args[at:at + 2]
    requested = args[0] if args else "next"
    conf = settings()
    try:
        workspace = hypr_json("activeworkspace")
        if target is not None:
            listed = hypr_json("workspaces")
            workspace = next((ws for ws in listed if int(ws.get("id", 0)) == target), {"id": target})
        # Omarchy gives each physical monitor a persistent block of ten global
        # Hyprland workspace IDs, even though each monitor labels them 1–10.
        # Persist by that global ID so identically labeled workspaces stay separate.
        workspace_id = int(workspace.get("id", 0))
        if workspace_id < 1:
            raise RuntimeError("Omarchy persistence supports numbered workspaces")

        mode_path = modes_dir / f"{workspace_id}.lua"
        current = mode_of(workspace, modes_dir)
        if requested in ("next", "back"):
            cycle = conf["cycle"]
            step = 1 if requested == "next" else -1
            if current in cycle:
                next_mode = cycle[(cycle.index(current) + step) % len(cycle)]
            else:
                # a layout left out of the cycle: go on from where it sits in the full list
                count = len(IDS)
                at = IDS.index(current) if current in IDS else (-1 if step > 0 else count)
                next_mode = next(IDS[(at + step * k) % count] for k in range(1, count + 1)
                                 if IDS[(at + step * k) % count] in cycle)
        elif requested in NAMES:
            next_mode = requested
        else:
            raise RuntimeError(f"Unknown layout: {requested[:60]}")
        next_name = NAMES[next_mode]

        # Save the mode the same way Omarchy does, so a successful apply is
        # already persistent if the compositor reloads immediately afterward.
        try:
            previous = mode_path.read_bytes()
        except FileNotFoundError:
            previous = None
        persist(mode_path, workspace_id, next_mode)

        # Omarchy's workspace-mode API applies the layout; its normal loader
        # replays the saved file on login and compositor reload. Only a known mode
        # and a number go into the expression.
        sync_pointer_guard = (
            "; if _G.omarchy_tableau and _G.omarchy_tableau.sync_pointer_guard "
            "then _G.omarchy_tableau.sync_pointer_guard() end"
        )
        expression = f'o.workspace_mode({{ workspace = "{workspace_id}", mode = "{next_mode}" }}){sync_pointer_guard}'
        applied = run(["hyprctl", "eval", expression])
        if applied.returncode:
            if previous is None:
                mode_path.unlink(missing_ok=True)
            else:
                mode_path.write_bytes(previous)
            raise RuntimeError(applied.stderr.strip() or applied.stdout.strip() or "Hyprland rejected the layout")
        if conf["notify"]:
            notify(next_name if target is None else f"Workspace {workspace.get('name', workspace_id)}: {next_name}")
        tell_shell()
        return 0
    except (OSError, ValueError, RuntimeError, StopIteration, subprocess.TimeoutExpired) as error:
        notify(f"Could not change layout: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
