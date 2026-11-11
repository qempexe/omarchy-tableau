#!/usr/bin/env python3
"""A click nobody made must not promote a window: Hyprland reports the focus it hands to the
window under the pointer as a click, and does that every time an X11 window asks for a size."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_layouts import fresh

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

CLICK, DISPATCH = 5, 3

def scene(layout, x11):
    L, mock, _ = fresh()
    ws, wins = mock.workspace(1, layout, 3)
    w = [wins[i] for i in (1, 2, 3)]
    w[2].xwayland = x11                       # the game
    mock.fire("window.active", w[0], DISPATCH)
    mock.run_timers()
    mock.dispatched = L.table()
    return L, mock, w

def main_window(mock, layout, w):
    """The window in the big spot: the layout puts slot 1 there."""
    placed = mock.run(layout[len("lua:"):], mock.area)
    return max(w, key=lambda x: placed[x.stable_id].w * placed[x.stable_id].h).stable_id

def stray(mock, win):
    mock.set_active(win); mock.fire("window.active", win, CLICK); mock.run_timers()

def click(mock, win, button=272):
    mock.binds["mouse:%d" % button]()
    mock.set_active(win); mock.fire("window.active", win, CLICK); mock.run_timers()

def focus_returns(mock):
    return [d for d in mock.dispatched.values() if d.kind == "focus"]

def main():
    for layout in ("lua:tableau-portrait", "lua:tableau-gallery-right", "lua:tableau-diptych-left", "lua:tableau-bento"):
        name = layout[len("lua:tableau-"):]
        L, mock, w = scene(layout, x11=True)
        mock.area = L.table_from({"x": 0, "y": 0, "w": 1920, "h": 1080})
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": the first window starts in the main spot")

        stray(mock, w[1])
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": a click nobody made leaves the windows where they are")
        back = focus_returns(mock)
        check(len(back) == 1 and back[0].args.window.stable_id == w[0].stable_id, name + ": and the focus goes back to the window that had it")
        check(not mock.warped and mock.no_warps is False, name + ": without moving the pointer, and warps are as they were")

        click(mock, w[1])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": a real click still promotes")

        # the game was resized by the swap and asks for its size: focus lands under the pointer
        mock.dispatched = L.table()
        stray(mock, w[0])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": the swap is not undone by the game asking for a size")
        back = focus_returns(mock)
        check(len(back) == 1 and back[0].args.window.stable_id == w[1].stable_id, name + ": the clicked window keeps the focus")

        mock.dispatched = L.table()
        for i in range(40):
            mock.set_active(w[i % 2]); mock.fire("window.active", w[i % 2], CLICK)
        mock.run_timers()
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": forty in a row trade no places")
        check(len(focus_returns(mock)) <= 4, name + ": and the focus is handed back a few times at most (%d)" % len(focus_returns(mock)))

        L, mock, w = scene(layout, x11=True)
        mock.area = L.table_from({"x": 0, "y": 0, "w": 1920, "h": 1080})
        mock.binds["mouse:272"]()
        mock.set_active(w[1]); mock.fire("window.active", w[1], CLICK)
        mock.set_active(w[2]); mock.fire("window.active", w[2], CLICK)
        mock.run_timers()
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": one press is one click")

        mock.binds["mouse:272"]()
        mock.run_timers()                     # the press went to a window that already had the focus
        stray(mock, w[2])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": a press that changed nothing is forgotten")

        L, mock, w = scene(layout, x11=True)
        mock.area = L.table_from({"x": 0, "y": 0, "w": 1920, "h": 1080})
        mock.no_warps = True
        stray(mock, w[1])
        check(len(focus_returns(mock)) == 1 and len(list(mock.configs.values())) == 0, name + ": warps already off are left alone")

        L, mock, w = scene(layout, x11=False)
        mock.area = L.table_from({"x": 0, "y": 0, "w": 1920, "h": 1080})
        stray(mock, w[1])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": with no X11 window open a tap promotes as before")

    L, mock, w = scene("lua:tableau-portrait", x11=True)
    for button in (272, 273, 274, 275, 276):
        opts = mock.bind_opts["mouse:%d" % button]
        check(opts is not None and opts.non_consuming is True and opts.ignore_mods is True,
              "button %d is watched and still reaches the window" % button)

    L, mock, _ = fresh()
    ws, wins = mock.workspace(1, "lua:tableau-mosaic", 3)
    wins[3].xwayland = True
    mock.fire("window.active", wins[1], DISPATCH); mock.run_timers(); mock.dispatched = L.table()
    stray(mock, wins[2])
    check(len(focus_returns(mock)) == 0, "a layout without a main window lets the focus be")

    print("%d failed" % len(FAILS) if FAILS else "ok")
    sys.exit(1 if FAILS else 0)

if __name__ == "__main__":
    main()
