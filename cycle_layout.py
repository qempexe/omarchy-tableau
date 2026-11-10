#!/usr/bin/env python3
"""Apply and persist Tableau's native Omarchy workspace-mode cycle."""

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


def run(args, timeout=4):
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout)


def notify(message):
    try:
        run(["omarchy-notification-send", "Workspace layout", message], timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        pass


def saved_mode(path):
    try:
        text = path.read_text()
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


def main():
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    modes_dir = state_home / "omarchy/workspace-layouts"
    try:
        active = run(["hyprctl", "activeworkspace", "-j"])
        if active.returncode:
            raise RuntimeError(active.stderr.strip() or "Hyprland did not return the active workspace")
        workspace = json.loads(active.stdout)
        # Omarchy gives each physical monitor a persistent block of ten global
        # Hyprland workspace IDs, even though each monitor labels them 1–10.
        # Persist by that global ID so identically labeled workspaces stay separate.
        workspace_id = int(workspace.get("id", 0))
        if workspace_id < 1:
            raise RuntimeError("Omarchy persistence supports numbered workspaces")

        mode_path = modes_dir / f"{workspace_id}.lua"
        active_layout = str(workspace.get("tiledLayout", workspace.get("tiled_layout", "")))
        persisted_mode = saved_mode(mode_path)
        current = "floating" if persisted_mode == "floating" else active_layout
        if current not in {ident for ident, _ in CHOICES} and persisted_mode in {ident for ident, _ in CHOICES}:
            current = persisted_mode
        requested = sys.argv[1] if len(sys.argv) > 1 else "next"
        try:
            index = next(i for i, (ident, _) in enumerate(CHOICES) if ident == current)
        except StopIteration:
            index = len(CHOICES) - 1 if requested != "back" else 0
        if requested == "next":
            next_mode, next_name = CHOICES[(index + 1) % len(CHOICES)]
        elif requested == "back":
            next_mode, next_name = CHOICES[(index - 1) % len(CHOICES)]
        else:
            selected = next((choice for choice in CHOICES if choice[0] == requested), None)
            if selected is None:
                raise RuntimeError(f"Unknown layout: {requested}")
            next_mode, next_name = selected

        # Save the mode the same way Omarchy does, so a successful apply is
        # already persistent if the compositor reloads immediately afterward.
        try:
            previous = mode_path.read_bytes()
        except FileNotFoundError:
            previous = None
        persist(mode_path, workspace_id, next_mode)

        # Omarchy's workspace-mode API applies the layout; its normal loader
        # replays the saved file on login and compositor reload.
        lua_mode = next_mode.replace("\\", "\\\\").replace('"', '\\"')
        sync_pointer_guard = (
            "; if _G.omarchy_tableau and _G.omarchy_tableau.sync_pointer_guard "
            "then _G.omarchy_tableau.sync_pointer_guard() end"
        )
        expression = f'o.workspace_mode({{ workspace = "{workspace_id}", mode = "{lua_mode}" }}){sync_pointer_guard}'
        applied = run(["hyprctl", "eval", expression])
        if applied.returncode:
            if previous is None:
                mode_path.unlink(missing_ok=True)
            else:
                mode_path.write_bytes(previous)
            raise RuntimeError(applied.stderr.strip() or applied.stdout.strip() or "Hyprland rejected the layout")
        notify(next_name)
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        notify(f"Could not change layout: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
