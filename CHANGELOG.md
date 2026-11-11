# Changelog

All notable changes to Tableau. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.2.1] - 2026-11-11

### Removed

- **Keep the pointer in games**. It held the pointer in a game only while the game let
  the pointer roam, so you couldn't leave the game with its cursor showing, and it never
  held it while you steered: a game holds the pointer itself then, and Hyprland lets the
  game win. A game in its windowed mode holds it to its window.

### Fixed

- The windows flickered while the pointer rested on one that didn't have the focus and
  a game was open: Tableau took back the focus the game handed over, and the game handed
  it over again, many times a second. That focus is left where it is now.
- A click that brought a window forward was undone a moment later when a game was open:
  the game handed the focus to the window that went out from under the click, and that
  counted as the same click.
- With a game open, the focus left a window moved with **Super + Shift + arrows** or
  **Super + Z** after a moment, for the window the pointer was left on. The pointer goes
  along with the window now.
- Right after a shell restart, the focus a game hands over still brought windows
  forward until the first click. The mouse buttons are known to be watched from the
  start now.

## [1.2.0] - 2026-11-11

### Added

- **Keep the pointer in games** (Rules), on by default: while a Steam or Wine game or
  gamescope has the focus in the main spot of a Tableau layout, the pointer can't leave
  its window, so a quick turn of the camera no longer ends on the window beside it.
  **Keep the pointer in** takes other window classes. A game shown as a miniature never
  holds the pointer.
- `touch ~/.local/state/hypr-tableau/trace` and a shell restart write every focus
  change to `focus.log`, with the reason Hyprland gave.

### Fixed

- A click on a miniature that had the focus already, after **Super + arrows** or after
  a game handed it the focus, brought nothing forward. It does now.
- With a game open, the focus a game hands to the window under the pointer goes back to
  the window that had it every time, and the pointer stays where it is. In 1.1.3 it went
  back a few times and then stayed on the miniature, so the next click did nothing.
- Clicks count as clicks until a mouse button has been seen to report its presses, so
  a setup where the buttons can't be watched behaves as it did before 1.1.3.

## [1.1.3] - 2026-11-11

### Fixed

- With a game open and the pointer on a window that isn't the focused one, the windows
  kept trading places, fast and without end. A game running through XWayland asks for a
  size over and over, Hyprland answers each time by focusing the window under the
  pointer and calls that a click, and Tableau promoted it, which resized the game, which
  asked again. While an X11 window is open, only a press of a mouse button promotes a
  window now, and the focus goes back to the window that had it.

## [1.1.2] - 2026-11-10

### Fixed

- A layout change, from the bar button, the panel or **Super + L**, was undone when
  Hyprland printed a warning or a note while making it. Only errors count now.
- Warnings while the layouts load no longer show a "didn't load" notification.

## [1.1.1] - 2026-11-10

### Fixed

- The bar button and the panel showed Portrait for every Tableau layout, and
  **Super + L** went on from Portrait instead of the layout on screen. `hyprctl`
  gives every Lua layout the name of the first one registered, so the layouts are now
  read from Hyprland's Lua, and from the saved layout when that doesn't answer.

## [1.1.0] - 2026-11-10

### Added

- **Resize step** under Windows › Sizes: how much one press of **Super + -** or
  **Super + =** changes, from 0.5% to 5% of the screen.

### Changed

- The resize keys grow and shrink the main window or the focused tile in small steps,
  and keep going while held. Alt makes the steps finer and Ctrl coarser. Elsewhere they
  resize as Omarchy's do.
- **Super + Alt + L**, Omarchy's key for the previous layout, goes back through
  Tableau's layouts too.

### Fixed

- Choosing a layout could leave the workspace on Hyprland's own layout without a word
  when Tableau's layouts weren't loaded in Hyprland. They are now loaded again first,
  and when that fails the notification says so and points to the error log.
- A Lua error while changing layout was taken for success, because `hyprctl` still
  exits cleanly; the saved layout is now put back and the error shown.
- When the layouts fail to load at start, the reason goes to the error log and a
  notification.
- The layout keys no longer depend on a helper only some Omarchy versions have.

## [1.0.0] - 2026-11-10

### Added

- Eighteen layouts in Omarchy's workspace layout cycle: Portrait, Landscape,
  Centerpiece, Diptych Left, Right, Top and Bottom, Triptych, Bento, Mosaic, Strip,
  Column, Spiral, Gallery Right, Bottom, Left and Top, and Spread.
- Live miniatures in Portrait, Landscape, Centerpiece and the Galleries: the other
  windows keep running, drawn small at their normal size, through a small Hyprland
  plugin built for the installed Hyprland.
- A layout per workspace, kept across restarts through Omarchy's workspace modes.
- **Super + L**, **Super + Shift + L** and the **Super + Ctrl + L** picker, and the
  focus, swap, Alt + Tab, bring forward and resize keys on every layout.
- A bar button with the focused workspace's layout, and a panel: Layouts, Windows,
  Rules, Panel and About tabs, a search over every setting, **Changed only**, a reset
  arrow on each row, and **Pop out** to turn it into a window of its own.
- Layouts tab: every layout as a picture to click for the focused workspace, and a dot
  on each to keep it in **Super + L** or leave it out.
- **Outline**: the border on every window of a Tableau layout, from none to 10 px.
- **Other windows**: the windows you're not using wear the focused window's outline,
  the theme's inactive border, or none.
- **Miniatures fade to**, **Light up a swap**, **Main pane**, **Triptych middle** and
  **Spread gap**.
- Rules tab: every workspace with its layout, changed with ‹ and ›, and **Never a
  miniature** for apps that should get a real small window.
- **Say which layout**: the notification when the layout changes can be turned off.
- Commands: `omarchy-shell io.github.qempexe.tableau layouts | settings | next | back |
  set <layout> | status | refresh`.
- A logo, light and dark, and an About tab.

[1.2.1]: https://github.com/qempexe/omarchy-tableau/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/qempexe/omarchy-tableau/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/qempexe/omarchy-tableau/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/qempexe/omarchy-tableau/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/qempexe/omarchy-tableau/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/qempexe/omarchy-tableau/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/qempexe/omarchy-tableau/releases/tag/v1.0.0
