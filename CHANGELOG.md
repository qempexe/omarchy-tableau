# Changelog

All notable changes to Tableau. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

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

[1.0.0]: https://github.com/qempexe/omarchy-tableau/releases/tag/v1.0.0
