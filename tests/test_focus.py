#!/usr/bin/env python3
"""Focus and clicks with a game open. Hyprland hands the focus to the window under the
pointer, and calls it a click, every time an X11 window asks for a size: such a "click"
must neither bring a window forward nor keep the focus, nor move the pointer. A real
click brings the window forward, also one that already has the focus. A game holds the
pointer only from the main spot."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_layouts import fresh

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

CLICK, DISPATCH = 5, 3
AREA = {"x": 0, "y": 0, "w": 1920, "h": 1080}

def scene(layout, x11=True, pressed_before=True, game_class="steam_app_582660"):
    L, mock, _ = fresh()
    ws, wins = mock.workspace(1, layout, 3)
    w = [wins[i] for i in (1, 2, 3)]
    w[2].xwayland = x11                       # the game, a miniature to start with
    w[2]["class"] = game_class
    mock.area = L.table_from(AREA)
    mock.fire("window.active", w[0], DISPATCH)
    if pressed_before:                        # a press somewhere, some time ago
        mock.binds["mouse:272"]()
    mock.run_timers()
    place(mock, layout)
    mock.dispatched = L.table()
    mock.configs = L.table()
    mock.warped = False
    return L, mock, w

def place(mock, layout):
    return mock.run(layout[len("lua:"):], mock.area)

def main_window(mock, layout, w):
    """The window in the big spot: the layout puts slot 1 there."""
    placed = place(mock, layout)
    return max(w, key=lambda x: placed[x.stable_id].w * placed[x.stable_id].h).stable_id

def point_at(mock, win):
    mock.cursor.x = win.at.x + win.size.x / 2
    mock.cursor.y = win.at.y + win.size.y / 2

def stray(mock, win):
    """Hyprland's refocus after a game asked for a size: the window under the pointer."""
    mock.set_active(win); mock.fire("window.active", win, CLICK); mock.run_timers()

def click(mock, win, button=272):
    point_at(mock, win)
    mock.binds["mouse:%d" % button]()
    if mock.lua_active().stable_id != win.stable_id:   # Hyprland only says something when the focus changes
        mock.set_active(win); mock.fire("window.active", win, CLICK)
    mock.run_timers()

def focus_returns(mock):
    return [d for d in mock.dispatched.values() if d.kind == "focus"]

def confined(w):
    return [("tableau-confine" in list(x.tags.values())) for x in w]

def main():
    for layout in ("lua:tableau-portrait", "lua:tableau-gallery-right", "lua:tableau-diptych-left", "lua:tableau-bento"):
        name = layout[len("lua:tableau-"):]
        L, mock, w = scene(layout)
        mock.lua_active = L.eval("function() return hl.get_active_window() end")
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": the first window starts in the main spot")

        # the pointer rests on the game's miniature, the game asks for a size again and again
        point_at(mock, w[2])
        for _ in range(30):
            stray(mock, w[2])
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": a click nobody made brings nothing forward")
        back = focus_returns(mock)
        check(len(back) == 30 and all(b.args.window.stable_id == w[0].stable_id for b in back),
              name + ": the focus goes back every time, with no limit that leaves it on a miniature (%d)" % len(back))
        check(not mock.warped and mock.no_warps is False, name + ": the pointer stays where it is, and warps are on again")
        check(mock.lua_active().stable_id == w[0].stable_id, name + ": the main window has the focus")

        # a real click on the game's miniature brings it forward
        click(mock, w[2])
        check(main_window(mock, layout, w) == w[2].stable_id, name + ": a real click brings the game forward")
        # the game asks for its size again: the pointer is now over the window that took its place
        mock.dispatched = L.table()
        stray(mock, w[0])
        check(main_window(mock, layout, w) == w[2].stable_id, name + ": the game asking for a size undoes nothing")
        back = focus_returns(mock)
        check(len(back) == 1 and back[0].args.window.stable_id == w[2].stable_id, name + ": the game keeps the focus")

        # a miniature that has the focus already, as after Super + arrows: a click brings it forward
        L, mock, w = scene(layout)
        mock.lua_active = L.eval("function() return hl.get_active_window() end")
        mock.set_active(w[1])
        click(mock, w[1])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": a click on a miniature that has the focus brings it forward")

        L, mock, w = scene(layout)
        mock.lua_active = L.eval("function() return hl.get_active_window() end")
        mock.set_active(w[1])
        mock.cursor.x, mock.cursor.y = 5000, 5000   # the bar, another monitor
        mock.binds["mouse:272"](); mock.run_timers()
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": a click somewhere else leaves it")
        mock["keys"]["Super_L"] = True
        point_at(mock, w[1]); mock.binds["mouse:272"](); mock.run_timers()
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": Super + a click moves or resizes, it brings nothing forward")
        mock["keys"]["Super_L"] = False

        # a click a moment before Hyprland's own refocus wins over giving the focus back
        L, mock, w = scene(layout)
        mock.lua_active = L.eval("function() return hl.get_active_window() end")
        point_at(mock, w[1])
        mock.set_active(w[1]); mock.fire("window.active", w[1], CLICK)   # a stray, not handled yet
        mock.binds["mouse:272"]()                                       # and a press before it is
        mock.run_timers()
        check(main_window(mock, layout, w) == w[1].stable_id and len(focus_returns(mock)) == 0,
              name + ": a click right after a stray is a click")

        # one press, one click
        L, mock, w = scene(layout)
        mock.lua_active = L.eval("function() return hl.get_active_window() end")
        point_at(mock, w[1]); mock.binds["mouse:272"]()
        mock.set_active(w[1]); mock.fire("window.active", w[1], CLICK)
        mock.set_active(w[2]); mock.fire("window.active", w[2], CLICK)
        mock.run_timers()
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": one press is one click")

        # warps already off are left alone; an option that can't be read means hands off
        L, mock, w = scene(layout)
        mock.no_warps = True
        stray(mock, w[1])
        check(len(focus_returns(mock)) == 1 and len(list(mock.configs.values())) == 0, name + ": warps already off are left alone")
        L, mock, w = scene(layout)
        mock.no_config = True
        stray(mock, w[1])
        check(len(focus_returns(mock)) == 0, name + ": when warps can't be switched off the focus is left, the pointer never jumps")

        # before any press was seen, every click counts as it always did
        L, mock, w = scene(layout, pressed_before=False)
        stray(mock, w[1])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": before any press was seen a click brings it forward")

        # with no X11 window open a tap brings it forward as before
        L, mock, w = scene(layout, x11=False)
        stray(mock, w[1])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": with no X11 window open a tap brings it forward")

        # the pointer is held by a game in the main spot only, never by a miniature
        L, mock, w = scene(layout)
        mock.lua_active = L.eval("function() return hl.get_active_window() end")
        L.execute("_G.omarchy_tableau.sync_pointer_guard()")
        check(confined(w) == [False, False, False], name + ": a game as a miniature doesn't hold the pointer")
        click(mock, w[2]); L.execute("_G.omarchy_tableau.sync_pointer_guard()")
        check(confined(w) == [False, False, True], name + ": in the main spot it does")
        click(mock, w[0]); L.execute("_G.omarchy_tableau.sync_pointer_guard()")
        check(confined(w) == [False, False, False], name + ": and lets go once it's a miniature again")

    for button in (272, 273, 274, 275, 276):
        L, mock, w = scene("lua:tableau-portrait")
        opts = mock.bind_opts["mouse:%d" % button]
        check(opts is not None and opts.non_consuming is True and opts.ignore_mods is True,
              "button %d is watched and still reaches the window" % button)

    # a layout without a main spot: the focus follows the pointer there, nothing is given back
    L, mock, w = scene("lua:tableau-mosaic")
    stray(mock, w[1])
    check(len(focus_returns(mock)) == 0, "a layout without a main spot lets the focus be")
    L.execute("_G.omarchy_tableau.sync_pointer_guard()")
    check(confined(w) == [False, False, True], "and every game tile there holds the pointer when it has the focus")

    print("%d failed" % len(FAILS) if FAILS else "ok")
    sys.exit(1 if FAILS else 0)

if __name__ == "__main__":
    main()
