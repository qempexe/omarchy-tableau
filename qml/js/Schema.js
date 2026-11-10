.pragma library
.import "Util.js" as Util
.import "Layouts.js" as Layouts

// Every setting Tableau has. The settings panel builds its tabs and rows from
// `groups`, resolve() turns tableau.json into a full, checked config, and confText()
// writes the part the layouts read (settings.conf, see hypr/tableau.lua).
//
//   kind: enum (pick one), steps (a number picked from a list, with − and +), bool (on/off),
//         string (text), palette (3 colors), tags (a list of names), int (slider),
//         layouts (the layout picker), workspaces (a layout per workspace), about
//   control: how an enum is shown: seg (buttons), tiles (little pictures), scheme, chips
//   fmt: how a steps value is shown (see format())
//   when: the row is greyed out unless these other settings have these values

// custom color swatches: backgrounds, text colors, accents
var swatches = [
  "#1c1210", "#141414", "#1a1b26", "#282a36", "#2e3440", "#2d353b", "#1f1f28", "#3b2a1f",
  "#e9dcc8", "#e0e0e0", "#ffffff", "#c0caf5", "#d8dee9", "#dcd7ba", "#f8f8f2", "#e0def4",
  "#c8905a", "#d4a35a", "#7aa2f7", "#cba6f7", "#a7c080", "#88c0d0", "#fabd2f", "#e06c75"
];

var outlineOn = [{ key: "outline", not: ["0"] }];

var groups = [
  {
    title: "Layouts",
    items: [
      { key: "layouts", label: "Layouts", kind: "layouts",
        hint: "Click one to use it on this workspace. The dot in the corner keeps it in Super + L." },
      { key: "notify", section: "Changing layout", label: "Say which layout", kind: "bool", fallback: true,
        hint: "A notification with the layout's name each time it changes." }
    ]
  },
  {
    title: "Windows",
    items: [
      { key: "outline", section: "Outline", label: "Outline", kind: "steps", fmt: "px", fallback: 2,
        min: 0, max: 20, round: true, options: [0, 1, 2, 3, 4, 6, 8, 10],
        hint: "How thick the border is on every window of a Tableau layout, from none to fat." },
      { key: "others", section: "Outline", label: "Other windows", kind: "enum", fallback: "same", control: "tiles",
        options: ["same", "theme", "hidden"],
        labels: { same: "Like the focused one", theme: "Theme's inactive", hidden: "No outline" },
        abouts: { same: "Every window gets the focused window's outline, gradient and all.",
                  theme: "The others keep your theme's inactive border color.",
                  hidden: "Only the focused window shows its outline." },
        hint: "The outline on the windows you're not using.", when: outlineOn },
      { key: "dim", section: "Miniatures", label: "Miniatures fade to", kind: "steps", fmt: "percent", fallback: 0.72,
        min: 0.2, max: 1, options: [0.4, 0.55, 0.72, 0.85, 1],
        hint: "How see-through the live miniatures are until you point at one. 100% keeps them solid." },
      { key: "flash", section: "Miniatures", label: "Light up a swap", kind: "bool", fallback: true,
        hint: "Both windows of a swap light up for a moment, so you see which two traded places." },
      { key: "pane", section: "Sizes", label: "Main pane", kind: "steps", fmt: "percent", fallback: 0.62,
        min: 0.4, max: 0.85, options: [0.5, 0.55, 0.62, 0.66, 0.7, 0.75, 0.8],
        hint: "How much of the screen the large pane gets in the Diptychs and Bento. Super + - and = change it per workspace." },
      { key: "middle", section: "Sizes", label: "Triptych middle", kind: "steps", fmt: "percent", fallback: 0.5,
        min: 0.3, max: 0.8, options: [0.34, 0.4, 0.45, 0.5, 0.55, 0.6, 0.66],
        hint: "How much of the width the middle window gets in Triptych." },
      { key: "gap", section: "Sizes", label: "Spread gap", kind: "steps", fmt: "px", fallback: 20,
        min: 0, max: 80, round: true, options: [0, 4, 8, 12, 20, 28, 40],
        hint: "The room between tiles in Spread, on top of your gaps." }
    ]
  },
  {
    title: "Rules",
    items: [
      { key: "workspaces", section: "Workspaces", label: "Workspaces", kind: "workspaces",
        hint: "Every workspace and its layout. Omarchy keeps the choice for that workspace across restarts." },
      { key: "fullSize", section: "Apps", label: "Never a miniature", kind: "tags", fallback: [], max: 64,
        presets: ["mpv", "vlc", "steam", "gamescope", "obs", "zoom"],
        hint: "Window classes that get a real small window instead of a scaled down picture in Portrait, Landscape, Centerpiece and the Galleries. Handy for games and video." }
    ]
  },
  {
    title: "Panel",
    items: [
      { key: "colorMode", section: "Colors", label: "Colors", kind: "enum", fallback: "theme", control: "scheme",
        options: ["theme", "borders", "custom", "monochrome"],
        labels: { theme: "Follow theme", borders: "Window borders", custom: "Custom", monochrome: "Monochrome" },
        hint: "Follow theme matches your Omarchy theme live. Window borders takes the accent from your theme's window border. Custom lets you choose. Monochrome removes every hue." },
      { key: "customColors", section: "Colors", label: "Custom colors", kind: "palette",
        fallback: { customBackground: "#1a1b26", customText: "#c0caf5", customAccent: "#7aa2f7" },
        targets: [{ key: "customBackground", label: "Background" }, { key: "customText", label: "Text" }, { key: "customAccent", label: "Accent" }],
        presets: swatches,
        hint: "Pick one, then a swatch or a hex code.",
        when: [{ key: "colorMode", is: ["custom"] }] },

      { key: "barIcon", section: "Button", label: "Bar icon", kind: "string", fallback: "󰕮", maxLength: 8,
        presets: ["󰕮", "󰕰", "󰕴", "󰙀", "󱒆"],
        hint: "A glyph or a short word for the button." },
      { key: "barShowName", section: "Button", label: "Show the layout", kind: "bool", fallback: true,
        hint: "The name of the focused workspace's layout, next to the icon." },
      { key: "rightClick", section: "Button", label: "Right click", kind: "enum", fallback: "next", control: "seg",
        options: ["next", "back", "none"], labels: { next: "Next layout", back: "Previous layout", none: "Nothing" },
        hint: "What a right click on the button does. It follows Super + L." },
      { key: "middleClick", section: "Button", label: "Middle click", kind: "enum", fallback: "back", control: "seg",
        options: ["back", "next", "none"], labels: { back: "Previous layout", next: "Next layout", none: "Nothing" },
        hint: "What a middle click on the button does." },

      { key: "openAs", section: "Window", label: "Open as", kind: "enum", fallback: "panel", control: "seg",
        options: ["panel", "window"], labels: { panel: "Bar panel", window: "Own window" },
        hint: "Where the button opens this panel. You can always pop it out or dock it back from the header." },
      { key: "windowWidth", section: "Window", label: "Panel width", kind: "int", fallback: 580, min: 480, max: 1000, step: 20,
        hint: "How wide the panel opens." },
      { key: "windowHeight", section: "Window", label: "Panel height", kind: "int", fallback: 660, min: 440, max: 1000, step: 20,
        hint: "How tall the panel opens." },

      { key: "density", section: "Look", label: "Spacing", kind: "enum", fallback: "comfortable", control: "seg",
        options: ["compact", "comfortable", "spacious"],
        labels: { compact: "Compact", comfortable: "Comfortable", spacious: "Spacious" },
        hint: "How much air there is between things in this panel." },
      { key: "cornerRadius", section: "Look", label: "Panel roundness", kind: "int", fallback: 6, min: 0, max: 20, step: 2,
        hint: "0 is square, 20 is very round." },
      { key: "frame", section: "Look", label: "Window outline", kind: "bool", fallback: false,
        hint: "Draw the panel edge in color instead of a plain neutral line." },
      { key: "frameGradient", section: "Look", label: "Outline gradient", kind: "bool", fallback: true,
        hint: "When your theme's window border is a gradient, the outline runs through all its colors.",
        when: [{ key: "frame", is: ["true"] }] },
      { key: "fontScale", section: "Look", label: "Text size", kind: "int", fallback: 100, min: 80, max: 150, step: 5, divisor: 100, decimals: 2,
        hint: "1 is normal, 1.25 is a quarter bigger." },
      { key: "opacity", section: "Look", label: "Panel opacity", kind: "int", fallback: 96, min: 50, max: 100, step: 2,
        hint: "Background of this panel." },
      { key: "speed", section: "Look", label: "Panel animations", kind: "enum", fallback: "on", control: "seg",
        options: ["on", "off"], labels: { on: "On", off: "Off" },
        hint: "Off makes switches and tabs change at once." }
    ]
  },
  {
    title: "About",
    items: [
      { key: "about", label: "About", kind: "about", hint: "The version, and more plugins." }
    ]
  }
];

// kept in the file but set from the layout picker, not a row of its own
var hiddenItems = [
  { key: "cycle", kind: "cycle", fallback: Layouts.ids.slice() }
];

// ---------- defaults and lookups, worked out once from the groups above ----------

var colorKeys = {};
var defaults = {};
var itemByKey = {};
var PAGE_KINDS = ["layouts", "workspaces", "about"];

function addItem(item) {
  itemByKey[item.key] = item;
  if (PAGE_KINDS.indexOf(item.kind) !== -1) return;
  if (item.kind === "palette") {
    for (let t = 0; t < item.targets.length; t++) {
      const colorKey = item.targets[t].key;
      defaults[colorKey] = item.fallback[colorKey];
      colorKeys[colorKey] = item.fallback[colorKey];
    }
  } else {
    defaults[item.key] = item.fallback;
  }
}
for (let g = 0; g < groups.length; g++)
  for (let i = 0; i < groups[g].items.length; i++) addItem(groups[g].items[i]);
for (let h = 0; h < hiddenItems.length; h++) addItem(hiddenItems[h]);

// what the layouts read: changing anything else never touches Hyprland
var layoutKeys = ["outline", "others", "dim", "flash", "fullSize", "pane", "middle", "gap", "notify", "cycle"];

var settingKeys = [];
for (const name in defaults) settingKeys.push(name);

function isSetting(key) { return settingKeys.indexOf(key) !== -1; }

// the setting for a key, or null (itemByKey["constructor"] is not one of ours)
function itemFor(key) {
  const item = itemByKey[key];
  if (item && typeof item === "object" && item.key === key) return item;
  return null;
}

function parseNum(value) {
  if (typeof value === "number") return value;
  if (typeof value === "string" && /^-?[0-9]{1,15}(\.[0-9]+)?$/.test(value.trim())) return parseFloat(value);
  return NaN;
}

function validHex(s) { return typeof s === "string" && /^#[0-9a-fA-F]{6}$/.test(s); }

// a window class as the never-a-miniature list keeps it: lower case letters, digits
// and . _ - + and spaces, so it can't break a line of settings.conf; short
function className(v) {
  return Util.toText(v).toLowerCase().replace(/[^a-z0-9._+ -]/g, "").trim().slice(0, 80);
}

// the layouts Super + L goes through, in the usual order; fewer than two means all
function cleanCycle(value) {
  if (!Array.isArray(value)) return Layouts.ids.slice();
  const out = [];
  for (let i = 0; i < Layouts.ids.length; i++)
    if (value.indexOf(Layouts.ids[i]) !== -1) out.push(Layouts.ids[i]);
  return out.length >= 2 ? out : Layouts.ids.slice();
}

// Checks one value against its setting. Anything odd gives the default back, so a
// hand-edited tableau.json can't break anything. Unknown keys give undefined.
function clean(key, value) {
  if (typeof colorKeys[key] === "string") {
    if (validHex(value)) return value.toLowerCase();
    return colorKeys[key];
  }
  const item = itemFor(key);
  if (item === null) return undefined;
  if (item.kind === "cycle") return cleanCycle(value);
  if (value === null || value === undefined) return Array.isArray(item.fallback) ? item.fallback.slice() : item.fallback;

  if (item.kind === "enum") {
    const t = Util.toText(value);
    return item.options.indexOf(t) !== -1 ? t : item.fallback;
  }
  if (item.kind === "steps" || item.kind === "int") {
    let n = parseNum(value);
    if (!isFinite(n)) return item.fallback;
    if (item.kind === "int" || item.round) n = Math.round(n);
    if (item.kind === "int" && item.step > 1) n = item.min + Math.round((n - item.min) / item.step) * item.step;
    if (n < item.min) return item.min;
    if (n > item.max) return item.max;
    return Math.round(n * 1000) / 1000;
  }
  if (item.kind === "bool") {
    if (value === true || value === "true") return true;
    if (value === false || value === "false") return false;
    return item.fallback;
  }
  if (item.kind === "tags") {
    if (!Array.isArray(value)) return item.fallback.slice();
    const out = [];
    for (let i = 0; i < value.length && out.length < item.max; i++) {
      const s = className(value[i]);
      if (s !== "" && out.indexOf(s) === -1) out.push(s);
    }
    return out;
  }
  // text: no control characters and no < >, so it always shows as plain text
  let text = Util.toText(value).replace(/[\u0000-\u001f\u007f<>]/g, "");
  if (item.maxLength) text = text.slice(0, item.maxLength);
  if (key === "barIcon" && text.trim() === "") return item.fallback;
  return text;
}

function migrate(obj) {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return {};
  const out = {};
  for (const k in obj) if (k !== "__proto__") out[k] = obj[k];
  return out;
}

// The whole saved file -> every setting, checked, with defaults filled in
function resolve(saved) {
  saved = migrate(saved);
  const result = {};
  for (const key in defaults) {
    let value = saved[key];
    if (typeof value === "function") value = undefined;
    result[key] = clean(key, value);
  }
  return result;
}

// settings.conf for hypr/tableau.lua and cycle_layout.py: one key=value per line, only
// numbers, known words and cleaned class names, so nothing in it can be run or break a line
function confText(cfg) {
  const n = (v, d) => isFinite(v) ? "" + Math.round(v * 1000) / 1000 : d;
  return [
    "# written by the Tableau panel; edit the settings there",
    "outline=" + n(cfg.outline, "2"),
    "others=" + (["same", "theme", "hidden"].indexOf(cfg.others) !== -1 ? cfg.others : "same"),
    "dim=" + n(cfg.dim, "0.72"),
    "flash=" + (cfg.flash === false ? "0" : "1"),
    "pane=" + n(cfg.pane, "0.62"),
    "middle=" + n(cfg.middle, "0.5"),
    "gap=" + n(cfg.gap, "20"),
    "notify=" + (cfg.notify === false ? "0" : "1"),
    "cycle=" + cleanCycle(cfg.cycle).join(","),
    "full_size=" + (Array.isArray(cfg.fullSize) ? cfg.fullSize.map(className).filter(s => s !== "").join(",") : "")
  ].join("\n") + "\n";
}

// the settings that matter to the layouts, as text, to tell real changes from panel ones
function layoutKey(cfg) {
  const o = {};
  for (let i = 0; i < layoutKeys.length; i++) o[layoutKeys[i]] = cfg[layoutKeys[i]];
  return JSON.stringify(o);
}

// ---------- showing numbers ----------

// short: without the unit, for the quick picks under a value that shows it
function format(fmt, v, short) {
  const n = typeof v === "number" ? v : parseNum(v);
  if (!isFinite(n)) return "?";
  if (short && fmt === "px") return "" + Math.round(n);
  switch (fmt) {
  case "percent": return Math.round(n * 100) + "%";
  case "px": return Math.round(n) === 0 ? "None" : Math.round(n) + " px";
  default: return "" + parseFloat(n.toFixed(2));
  }
}

// the next value in a steps list from where v is now (v may sit between two)
function stepFrom(options, v, dir) {
  if (!options || options.length === 0) return v;
  if (dir > 0) {
    for (let i = 0; i < options.length; i++) if (options[i] > v + 1e-9) return options[i];
    return options[options.length - 1];
  }
  for (let j = options.length - 1; j >= 0; j--) if (options[j] < v - 1e-9) return options[j];
  return options[0];
}
