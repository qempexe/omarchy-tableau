# Changelog

All notable changes to Tableau. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-10

### Added

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
- Two layouts: **Triptych** (the window you use in the middle, the rest stacked on
  either side) and **Bento** (a large pane, one window beside it, the rest in a row
  below it), on **Super + Ctrl + L**, **0**, then **-** and **=**.
- Commands: `omarchy-shell io.github.qempexe.tableau layouts | settings | next | back |
  set <layout> | status | refresh`.
- A logo, light and dark, and an About tab.

### Changed

- The four Galleries show the other windows as live miniatures at their normal size,
  the same as Portrait and Landscape, whatever size the main pane is.
- Unfocused windows on Portrait, Landscape, Centerpiece and the Galleries keep the same
  outline as the focused one instead of losing it.
- **Super + -** grows and **Super + =** shrinks the main window or the focused tile on
  every layout, the way Omarchy's own keys expand and shrink a window.

### Fixed

- Gallery miniatures were squashed into cells of another shape.
- A window left alone in a Gallery could stay drawn as a miniature.
- **Super + Shift + Down** in Mosaic and Spread could swap a window with one in its
  own row.
- The error log grew without end; it now starts over past 256 KB.
- Old builds of the thumbnail helper piled up in the plugin folder.
- A state folder with a quote in its path broke saving the main window sizes.

## [0.1.0] - 2026-11-08

### Added

- Sixteen layouts in Omarchy's workspace layout cycle: Portrait, Landscape,
  Centerpiece, four Diptychs, Mosaic, Strip, Column, Spiral, four Galleries and Spread.
- Live miniatures through a small Hyprland plugin, built for the installed Hyprland.
- **Super + L**, **Super + Shift + L** and the **Super + Ctrl + L** picker, and the
  focus, swap, Alt + Tab, promote and resize keys on every layout.

[1.0.0]: https://github.com/qempexe/omarchy-tableau/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/qempexe/omarchy-tableau/releases/tag/v0.1.0
