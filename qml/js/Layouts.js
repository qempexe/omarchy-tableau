.pragma library

// Every layout Super + L can pick, in the order it goes through them, with a little
// picture of each: boxes in a 0..1 square, `main` marking the window you're using.
// Keep the ids in step with CHOICES in cycle_layout.py.

var list = [
  { id: "dwindle", name: "Dwindle", hint: "Hyprland's own: every window splits the space it lands in" },
  { id: "scrolling", name: "Scrolling", hint: "Hyprland's own: columns on a strip that scrolls" },
  { id: "floating", name: "Floating", hint: "Omarchy's: windows float where you put them" },
  { id: "lua:tableau-portrait", name: "Portrait", hint: "One window in the middle, live miniatures at the sides" },
  { id: "lua:tableau-landscape", name: "Landscape", hint: "A wide window in the middle, miniatures above and below" },
  { id: "lua:tableau-centerpiece", name: "Centerpiece", hint: "One window in the middle, miniatures all round" },
  { id: "lua:tableau-diptych-left", name: "Diptych Left", hint: "A large pane on the left, the rest stacked on the right" },
  { id: "lua:tableau-diptych-right", name: "Diptych Right", hint: "A large pane on the right, the rest stacked on the left" },
  { id: "lua:tableau-diptych-top", name: "Diptych Top", hint: "A large pane on top, the rest side by side below" },
  { id: "lua:tableau-diptych-bottom", name: "Diptych Bottom", hint: "A large pane below, the rest side by side above" },
  { id: "lua:tableau-triptych", name: "Triptych", hint: "The window you use in the middle, the rest stacked either side" },
  { id: "lua:tableau-bento", name: "Bento", hint: "A large pane, one window beside it, the rest in a row below that" },
  { id: "lua:tableau-mosaic", name: "Mosaic", hint: "Equal tiles in the grid that suits the screen best" },
  { id: "lua:tableau-strip", name: "Strip", hint: "Side by side in one row" },
  { id: "lua:tableau-column", name: "Column", hint: "One above the other" },
  { id: "lua:tableau-spiral", name: "Spiral", hint: "Each window halves what's left, turning as it goes" },
  { id: "lua:tableau-gallery-right", name: "Gallery Right", hint: "A large pane, live miniatures in a grid on the right" },
  { id: "lua:tableau-gallery-bottom", name: "Gallery Bottom", hint: "A large pane, live miniatures in a grid below" },
  { id: "lua:tableau-gallery-left", name: "Gallery Left", hint: "A large pane, live miniatures in a grid on the left" },
  { id: "lua:tableau-gallery-top", name: "Gallery Top", hint: "A large pane, live miniatures in a grid above" },
  { id: "lua:tableau-spread", name: "Spread", hint: "A grid with room between the tiles" }
];

var ids = [];
var byId = {};
for (var i = 0; i < list.length; i++) { ids.push(list[i].id); byId[list[i].id] = list[i]; }

function isLayout(id) { return typeof id === "string" && byId.hasOwnProperty(id); }
function nameOf(id) { return isLayout(id) ? byId[id].name : (typeof id === "string" && id !== "" ? id.replace(/^lua:/, "") : "Unknown"); }

// the next layout from `id`, through all of them (dir 1 or -1)
function step(id, dir) {
  var at = ids.indexOf(id);
  if (at < 0) return dir > 0 ? ids[0] : ids[ids.length - 1];
  return ids[(at + dir + ids.length) % ids.length];
}

function box(x, y, w, h, main) { return { x: x, y: y, w: w, h: h, main: main === true }; }

// a column of n boxes in x..x+w, centred, each `aspect` wide for its height
function minis(x, w, n, aspect, out) {
  var h = Math.min(w / aspect, 0.9 / n);
  var bw = h * aspect, top = (1 - h * n) / 2;
  for (var k = 0; k < n; k++) out.push(box(x + (w - bw) / 2, top + k * h, bw, h * 0.92));
}

// The picture for a layout, with five windows
function art(id) {
  var b = [];
  switch (id) {
  case "dwindle":
    return [box(0, 0, 0.5, 1, true), box(0.5, 0, 0.5, 0.5), box(0.5, 0.5, 0.25, 0.5), box(0.75, 0.5, 0.25, 0.25), box(0.75, 0.75, 0.25, 0.25)];
  case "scrolling":
    return [box(-0.2, 0, 0.36, 1), box(0.18, 0, 0.5, 1, true), box(0.7, 0, 0.5, 0.5), box(0.7, 0.5, 0.5, 0.5)];
  case "floating":
    return [box(0.06, 0.1, 0.5, 0.5), box(0.3, 0.3, 0.52, 0.55, true), box(0.55, 0.08, 0.38, 0.4)];
  case "lua:tableau-portrait":
    b.push(box(0.25, 0, 0.5, 1, true)); minis(0, 0.23, 2, 0.6, b); minis(0.77, 0.23, 2, 0.6, b); return b;
  case "lua:tableau-landscape":
    return [box(0, 0.25, 1, 0.5, true), box(0.14, 0.02, 0.34, 0.21), box(0.52, 0.02, 0.34, 0.21), box(0.14, 0.77, 0.34, 0.21), box(0.52, 0.77, 0.34, 0.21)];
  case "lua:tableau-centerpiece":
    return [box(0.18, 0.18, 0.64, 0.64, true), box(0.02, 0.38, 0.14, 0.24), box(0.84, 0.38, 0.14, 0.24), box(0.36, 0.02, 0.28, 0.14), box(0.36, 0.84, 0.28, 0.14)];
  case "lua:tableau-diptych-left":
    return [box(0, 0, 0.62, 1, true), box(0.62, 0, 0.38, 0.25), box(0.62, 0.25, 0.38, 0.25), box(0.62, 0.5, 0.38, 0.25), box(0.62, 0.75, 0.38, 0.25)];
  case "lua:tableau-diptych-right":
    return [box(0.38, 0, 0.62, 1, true), box(0, 0, 0.38, 0.25), box(0, 0.25, 0.38, 0.25), box(0, 0.5, 0.38, 0.25), box(0, 0.75, 0.38, 0.25)];
  case "lua:tableau-diptych-top":
    return [box(0, 0, 1, 0.62, true), box(0, 0.62, 0.25, 0.38), box(0.25, 0.62, 0.25, 0.38), box(0.5, 0.62, 0.25, 0.38), box(0.75, 0.62, 0.25, 0.38)];
  case "lua:tableau-diptych-bottom":
    return [box(0, 0.38, 1, 0.62, true), box(0, 0, 0.25, 0.38), box(0.25, 0, 0.25, 0.38), box(0.5, 0, 0.25, 0.38), box(0.75, 0, 0.25, 0.38)];
  case "lua:tableau-triptych":
    return [box(0.25, 0, 0.5, 1, true), box(0, 0, 0.25, 0.5), box(0, 0.5, 0.25, 0.5), box(0.75, 0, 0.25, 0.5), box(0.75, 0.5, 0.25, 0.5)];
  case "lua:tableau-bento":
    return [box(0, 0, 0.62, 1, true), box(0.62, 0, 0.38, 0.5), box(0.62, 0.5, 0.127, 0.5), box(0.747, 0.5, 0.127, 0.5), box(0.873, 0.5, 0.127, 0.5)];
  case "lua:tableau-mosaic":
    return [box(0, 0, 1 / 3, 0.5, true), box(1 / 3, 0, 1 / 3, 0.5), box(2 / 3, 0, 1 / 3, 0.5), box(1 / 6, 0.5, 1 / 3, 0.5), box(0.5, 0.5, 1 / 3, 0.5)];
  case "lua:tableau-strip":
    for (var s = 0; s < 5; s++) b.push(box(s / 5, 0, 0.2, 1, s === 0)); return b;
  case "lua:tableau-column":
    for (var c = 0; c < 5; c++) b.push(box(0, c / 5, 1, 0.2, c === 0)); return b;
  case "lua:tableau-spiral":
    return [box(0, 0, 0.5, 1, true), box(0.5, 0, 0.5, 0.5), box(0.75, 0.5, 0.25, 0.5), box(0.5, 0.75, 0.25, 0.25), box(0.5, 0.5, 0.25, 0.25)];
  case "lua:tableau-gallery-right":
    return [box(0, 0, 0.64, 1, true), box(0.67, 0.1, 0.15, 0.36), box(0.83, 0.1, 0.15, 0.36), box(0.67, 0.54, 0.15, 0.36), box(0.83, 0.54, 0.15, 0.36)];
  case "lua:tableau-gallery-left":
    return [box(0.36, 0, 0.64, 1, true), box(0.02, 0.1, 0.15, 0.36), box(0.18, 0.1, 0.15, 0.36), box(0.02, 0.54, 0.15, 0.36), box(0.18, 0.54, 0.15, 0.36)];
  case "lua:tableau-gallery-bottom":
    return [box(0, 0, 1, 0.64, true), box(0.06, 0.68, 0.2, 0.28), box(0.29, 0.68, 0.2, 0.28), box(0.52, 0.68, 0.2, 0.28), box(0.75, 0.68, 0.2, 0.28)];
  case "lua:tableau-gallery-top":
    return [box(0, 0.36, 1, 0.64, true), box(0.06, 0.04, 0.2, 0.28), box(0.29, 0.04, 0.2, 0.28), box(0.52, 0.04, 0.2, 0.28), box(0.75, 0.04, 0.2, 0.28)];
  case "lua:tableau-spread":
    return [box(0.02, 0.03, 0.3, 0.44, true), box(0.35, 0.03, 0.3, 0.44), box(0.68, 0.03, 0.3, 0.44), box(0.185, 0.53, 0.3, 0.44), box(0.515, 0.53, 0.3, 0.44)];
  }
  return [box(0, 0, 1, 1, true)];
}
