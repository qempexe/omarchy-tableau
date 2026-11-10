# Tableau

Tableau registers sixteen Hyprland Lua layouts and extends Omarchy's workspace-layout cycle with them. It uses Omarchy's per-workspace mode API and state files, so a layout choice survives shell restarts, logout, and reboot without editing a separate layout profile.

## Per-monitor persistence

Omarchy assigns each physical monitor its own persistent block of ten global Hyprland workspace IDs. Tableau saves the selected mode against that ID, so workspace 1 on one monitor and workspace 1 on another keep independent layouts. The block follows the monitor across shell restarts, logout, reboot, and monitor reconnection. Saved modes live in `~/.local/state/omarchy/workspace-layouts/` and are restored by Omarchy at compositor startup; Tableau replays them after registering its Lua layouts.

## Layouts

- **Portrait** — one focused window in the center, with adaptive miniature thumbnails arranged in side rails. As windows are added, thumbnails fit into additional narrower columns.
- **Landscape** — the same adaptive stage behavior rotated into a horizontal layout, with a focus row and thumbnail rails above and below.
- **Centerpiece** — the focused window stays in the center while the other windows fill thumbnail rails on all four sides.
- **Diptych Left** — the focused window gets a 62% pane on the left; the remaining windows stack on the right. Clicking a side window promotes it into the main pane.
- **Diptych Right** — the same focused-window layout mirrored, with the main pane on the right.
- **Mosaic** — equal-sized windows arranged in the screen shape that best balances their proportions; an incomplete final row is centred.
For **Mosaic**, **Spread**, **Strip**, **Column**, and **Spiral**, minus shrinks the focused window and plus expands it; the other windows resize to share the space. In all four **Diptych** orientations, the same keys shrink or grow the large pane, resizing the side windows to match.
- **Strip** — every window gets an equal-width tile in one horizontal row.
- **Column** — every window gets an equal-height tile in one vertical stack.
- **Spiral** — windows split the remaining space in alternating directions.
- **Gallery Right** — the focused window fills the left pane; the others form a grid on the right.
- **Gallery Bottom** — the focused window fills the upper pane; the others form a grid below.
- **Gallery Left** — the focused window fills the right pane; the others form a grid on the left.
- **Gallery Top** — the focused window fills the lower pane; the others form a grid above.
- **Diptych Top** — the focused window fills the upper pane; the others tile side by side below.
- **Diptych Bottom** — the focused window fills the lower pane; the others tile side by side above.
- **Spread** — a balanced grid with breathing room between tiles.

Portrait and Landscape adapt the Stage layout engine from [omarchy-stage](https://github.com/Sulejman/omarchy-stage), © Sulejman Sarajlija, under the included MIT license. The optional Hyprland thumbnail helper keeps each app at full size while drawing it as a true miniature. Tableau builds that helper for the installed Hyprland version when compiler dependencies are available; without it, those layouts still work with windows sized into the thumbnail positions.

`Super+L` cycles Dwindle → Scrolling → Floating → Portrait → Landscape → Centerpiece → Diptych Left → Diptych Right → Diptych Top → Diptych Bottom → Mosaic → Strip → Column → Spiral → Gallery Right → Gallery Bottom → Gallery Left → Gallery Top → Spread. `Super+Shift+L` cycles backwards, preserving Omarchy's `Super+Alt+L` lock-screen binding. Press `Super+Ctrl+L`, then `1`–`9` to choose directly: the first three select Omarchy's modes, and `4`–`9` select Portrait, Landscape, Centerpiece, Diptych Left, Diptych Right, and Mosaic. Press `0` for the second page, then `1`–`0` for Strip, Column, Spiral, Gallery Right, Gallery Bottom, Gallery Left, Gallery Top, Spread, Diptych Top, and Diptych Bottom. Tableau saves each choice through Omarchy's workspace-mode mechanism.

On every Tableau layout, `Super` + arrows focuses the nearest window in that direction, `Alt+Tab` cycles through windows, and `Super+Z` promotes the focused window. `Super+Shift` + arrows swaps the focused window with the nearest window in that direction. In all four Diptych orientations, the large pane follows the promoted window; Alt+Tab promotes the selected window when you release Alt.
