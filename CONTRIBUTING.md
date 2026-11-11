# Contributing to Tableau

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

Bug reports and ideas are welcome as [issues](https://github.com/qempexe/omarchy-tableau/issues).
For a bug, the Omarchy and Hyprland versions, the layout, what you did, and
`~/.local/state/hypr-tableau/errors.log` or the lines from
`qs log -p "$OMARCHY_PATH/shell" --tail 100` that mention `tableau` help most.

## How it fits together

- `hypr/tableau.lua` is every layout, registered with `hl.layout.register`, and what
  goes with them: the slots that keep a miniature in its place, the outline rules and
  tags, and the focus, swap, Alt + Tab and resize keys. It reads its settings from
  `settings.conf` and runs nothing from it.
- `tableau.lua` binds Super + L and the picker, and replays the saved workspace modes.
- `cycle_layout.py` changes and saves a workspace's layout through Omarchy's
  `o.workspace_mode`, and lists the workspaces for the panel (`--status`).
- `hypr/tableau-service.sh` loads both Lua files with `hyprctl eval`, and builds and
  loads the thumbnail helper in `hypr/stagethumbs/`.
- `qml/Service.qml` runs once in the shell: it starts the above, keeps the settings,
  writes `settings.conf` when a layout setting changes, and keeps the workspaces.
- `qml/js/Schema.js` is every setting; `qml/js/Layouts.js` every layout and its picture.

## Adding a layout

1. Write its `recalculate` in `hypr/tableau.lua` and register it with
   `register_layout("tableau-<name>", ...)`. Add it to `is_duo`, `is_balance` or
   `is_tableau_layout` so the keys and the outline know it.
2. Add it to `CHOICES` in `cycle_layout.py` and to `list` and `art()` in
   `qml/js/Layouts.js`, in the same place.
3. Give it a key in the picker in `tableau.lua` if there's one free.
4. Run the tests: they check every layout keeps its windows on screen and apart, and
   that the three lists agree.

## Adding a setting

1. Add an item to the right group in `qml/js/Schema.js`: `key`, `label`, `kind`,
   `fallback`, a short `hint`, and the range or options. The row, the search, the reset
   arrow, the saved value and its checking all come from that.
2. When the layouts need it, add it to `layoutKeys` and `confText()`, and read it in
   `read_settings()` in `hypr/tableau.lua`, clamped.
3. Run the tests.

`key` is what gets saved in people's settings. It never changes once released; a label
can.

## Testing

```bash
python3 tests/test_layouts.py    # every layout, 1 to 9 windows, three screens (Lua 5.5)
python3 tests/test_settings.py   # settings.conf, the outline rules, tags, resize keys
python3 tests/test_cycle.py      # cycle_layout.py with a stand-in hyprctl
python3 tests/test_focus.py      # a click nobody made promotes nothing and gives the focus back
node tests/test_schema.js        # the settings, settings.conf and the layout lists
```

The Lua tests need `lupa` (`pip install lupa`). Then copy the plugin to
`~/.config/omarchy/plugins/io.github.qempexe.tableau`, run `omarchy restart shell`, and
go through the layouts with three, five and nine windows, on one monitor and two.

## Style

- Lua is 5.5: a `for` loop's variables can't be assigned to.
- JavaScript is modern (`const`, `let`, arrow functions). Names other files read stay
  top-level `var` or `function`, which is how a `.pragma library` file shares them.
- Nothing from a window, a file or the panel goes into a command or a Lua expression
  unless it is a number or a name from a fixed list.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, one line each.
