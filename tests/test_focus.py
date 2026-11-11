#!/usr/bin/env python3
"""Focus and clicks with a game open. Hyprland hands the focus to the window under the
pointer, and calls it a click, every time an X11 window asks for a size: such a "click"
brings nothing forward, and the focus is left where Hyprland put it, so nothing flickers.
A real click brings the window forward, also one that already has the focus. Nothing
holds the pointer in a window."""
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
    mock.lua_active = L.eval("function() return hl.get_active_window() end")
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

def focus_moves(mock):
    return [d for d in mock.dispatched.values() if d.kind == "focus"]

def fresh_without_binds():
    """Tableau loaded where hl.bind refuses mouse buttons."""
    import tempfile
    from lupa import lua55
    state = tempfile.mkdtemp(prefix="tableau-test-")
    os.environ["XDG_STATE_HOME"] = state
    L = lua55.LuaRuntime(unpack_returned_tuples=True)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    L.execute("package.path = %r .. ';' .. package.path" % (root + "/tests/?.lua"))
    mock = L.execute("return (require('hl_mock'))")
    L.execute("local bind = hl.bind; hl.bind = function(keys, ...) if keys:find('^mouse:') then error('no') end return bind(keys, ...) end")
    L.execute("dofile(%r)" % (root + "/hypr/tableau.lua"))
    return L, mock, state

def main():
    for layout in ("lua:tableau-portrait", "lua:tableau-gallery-right", "lua:tableau-diptych-left", "lua:tableau-bento"):
        name = layout[len("lua:tableau-"):]
        L, mock, w = scene(layout)
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": the first window starts in the main spot")

        # the pointer rests on the game's miniature, the game asks for a size again and again
        point_at(mock, w[2])
        for _ in range(30):
            stray(mock, w[2])
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": a click nobody made brings nothing forward")
        check(len(focus_moves(mock)) == 0, name + ": and the focus is left where Hyprland put it: no flicker")
        check(not mock.warped and len(list(mock.configs.values())) == 0, name + ": the pointer and the settings are left alone")
        # the pointer goes on to another miniature, then back to the main window
        stray(mock, w[1]); stray(mock, w[0])
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": passing over the windows moves nothing")

        # a real click on the game's miniature brings it forward, focused or not
        click(mock, w[2])
        check(main_window(mock, layout, w) == w[2].stable_id, name + ": a real click brings the game forward")
        # the game asks for its size again: the pointer is now over the window that took its place
        stray(mock, w[0])
        check(main_window(mock, layout, w) == w[2].stable_id, name + ": the game asking for a size undoes nothing")
        # the focus the game handed to the miniature under the pointer: a click there brings it forward
        click(mock, w[0])
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": a click on the miniature the game handed the focus to brings it forward")

        # a miniature that has the focus already, as after Super + arrows: a click brings it forward
        L, mock, w = scene(layout)
        mock.set_active(w[1])
        click(mock, w[1])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": a click on a miniature that has the focus brings it forward")

        L, mock, w = scene(layout)
        mock.set_active(w[1])
        mock.cursor.x, mock.cursor.y = 5000, 5000   # the bar, another monitor
        mock.binds["mouse:272"](); mock.run_timers()
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": a click somewhere else leaves it")
        mock["keys"]["Super_L"] = True
        point_at(mock, w[1]); mock.binds["mouse:272"](); mock.run_timers()
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": Super + a click moves or resizes, it brings nothing forward")
        mock["keys"]["Super_L"] = False

        # one press, one click
        L, mock, w = scene(layout)
        point_at(mock, w[1]); mock.binds["mouse:272"]()
        mock.set_active(w[1]); mock.fire("window.active", w[1], CLICK)
        mock.set_active(w[2]); mock.fire("window.active", w[2], CLICK)
        mock.run_timers()
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": one press is one click")

        # right after loading, before any press: the buttons are watched, so this is no click
        L, mock, w = scene(layout, pressed_before=False)
        stray(mock, w[1])
        check(main_window(mock, layout, w) == w[0].stable_id, name + ": right after loading a click nobody made brings nothing forward")

        # with no X11 window open a tap brings it forward as before
        L, mock, w = scene(layout, x11=False)
        stray(mock, w[1])
        check(main_window(mock, layout, w) == w[1].stable_id, name + ": with no X11 window open a tap brings it forward")

        # nothing holds the pointer, and the tag 1.2.0 used for that comes off
        L, mock, w = scene(layout)
        w[2].tags = L.table("tableau-confine")
        click(mock, w[2]); L.execute("_G.omarchy_tableau.sync_pointer_guard()")
        check(not any("tableau-confine" in str(t) for x in w for t in x.tags.values()), name + ": no window is held, old tags come off")

    for button in (272, 273, 274, 275, 276):
        L, mock, w = scene("lua:tableau-portrait")
        opts = mock.bind_opts["mouse:%d" % button]
        check(opts is not None and opts.non_consuming is True and opts.ignore_mods is True,
              "button %d is watched and still reaches the window" % button)

    # when the buttons can't be watched, every click counts, as before 1.1.3
    L, mock, _ = fresh_without_binds()
    ws, wins = mock.workspace(1, "lua:tableau-portrait", 3)
    w = [wins[i] for i in (1, 2, 3)]
    w[2].xwayland = True
    mock.area = L.table_from(AREA)
    mock.fire("window.active", w[0], DISPATCH); mock.run_timers()
    stray(mock, w[1])
    check(main_window(mock, "lua:tableau-portrait", w) == w[1].stable_id, "with no watched buttons a click brings it forward as before")

    print("%d failed" % len(FAILS) if FAILS else "ok")
    sys.exit(1 if FAILS else 0)

if __name__ == "__main__":
    main()
