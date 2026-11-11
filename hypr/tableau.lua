-- Tableau's layouts for Hyprland, registered as Lua layouts and chosen per workspace
-- through Omarchy's workspace modes.
--
-- Portrait, Landscape, Centerpiece and the four Galleries keep the window you use
-- large and show every other window as a live miniature around it. Thumbnails keep
-- their spot: bringing a window forward only swaps it with the current one.
--   click a thumbnail      swap it into the middle
--   ALT + TAB              hold ALT, tap TAB to move the highlight across the
--   ALT + SHIFT + TAB      thumbnails; release ALT to open it
--   SUPER + arrows         move focus without moving anything (you can type
--                          into a focused thumbnail)
--   SUPER + SHIFT + arrows swap the focused window with its neighbour
--   SUPER + Z              swap the focused thumbnail into the middle
--   SUPER + - / =          grow / shrink the main window in small steps, and
--                          keep going while held (ALT: finer, CTRL: coarser);
--                          the others use the space that's left
--
-- The Diptychs, Triptych and Bento give the focused window the main pane. Mosaic,
-- Spread, Strip, Column and Spiral share the screen, and the resize keys give the
-- focused window more or less of it.
--
-- Portrait and Landscape adapt the Stage layout from
-- https://github.com/Sulejman/omarchy-stage (MIT), inspired by Scott Jenson's talk
-- "Are we really going to use the same Desktop UX forever?".
--
-- Settings come from ~/.local/state/hypr-tableau/settings.conf, which the Tableau
-- panel writes: plain key=value lines, read here without running anything.

-- Loaded once per Hyprland Lua state. A config reload starts a fresh state,
-- so this only stops a second copy (e.g. both the Omarchy plugin and a manual
-- `require`) from registering everything twice.
if _G.omarchy_tableau then
  return _G.omarchy_tableau
end

local cfg = {
  center_aspect = 1.6, -- preferred width:height of the middle window...
  center_min = 0.40, -- ...but never less than this share of the screen width
  center_max = 0.64, -- ...and never more
  decay = 0.75, -- each thumbnail column further out is this much narrower
  center_step_min = 0.25, -- the middle window can be resized between these shares of the width
  center_step_max = 0.92,

  thumb_opacity = 0.72, -- thumbnails at rest; the selected or hovered one is fully opaque
  swap_flash_ms = 700, -- both windows of a swap light up this long, so it's clear which two traded places

  -- from settings.conf (see read_settings below)
  outline = 2, -- border (px) on every window of a Tableau layout, focused or not
  others = "same", -- unfocused windows' border: same (as the focused one), theme (inactive color), hidden
  flash = true, -- light up both windows of a swap
  pane = 0.62, -- share of the screen the main pane gets in the Diptychs and Bento
  middle = 0.50, -- share of the width the middle window gets in Triptych
  gap = 20, -- space between tiles in Spread
  step = 0.01, -- how much one press of the resize keys changes (a share of the screen); held, it repeats
  full_size = {}, -- window classes never shown as miniatures (lower case)
  confine = true, -- the pointer stays inside a game while the game has the focus
  confine_apps = {}, -- other window classes it stays inside (lower case)
}

local LAYOUT = "lua:tableau-portrait"
local HORIZON_LAYOUT = "lua:tableau-landscape"
local SURROUND_LAYOUT = "lua:tableau-centerpiece"
local GALLERY_LAYOUT = "lua:tableau-gallery-bottom"
local GALLERY_RIGHT_LAYOUT = "lua:tableau-gallery-right"
local GALLERY_LEFT_LAYOUT = "lua:tableau-gallery-left"
local GALLERY_TOP_LAYOUT = "lua:tableau-gallery-top"
-- Nerd Font md-view_carousel_outline: one window in the middle, others at the
-- sides. Shown like the icons on Omarchy's dwindle/scrolling notifications.
local STAGE_ICON = "\u{F1486}"
local state_dir = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/hypr-tableau"
local error_file = state_dir .. "/errors.log"
local settings_file = state_dir .. "/settings.conf"
-- `touch` the first and restart the shell to have every focus change written to the second
local trace_switch = state_dir .. "/trace"
local trace_file = state_dir .. "/focus.log"
local ERROR_LOG_MAX = 256 * 1024

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- settings.conf: one `key=value` per line, written by the Tableau panel. Only the keys
-- below are read, each checked and clamped, so a hand edit can't break a layout.
local function number_in(text, low, high, fallback)
  local n = tonumber(text)
  if not n or n ~= n then return fallback end
  return math.max(low, math.min(high, n))
end

local function read_settings()
  local switch = io.open(trace_switch, "r")
  cfg.trace = switch ~= nil
  if switch then switch:close() end
  local file = io.open(settings_file, "r")
  if not file then return end
  local values = {}
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and #value <= 4096 then values[key] = value end
  end
  file:close()
  cfg.outline = math.floor(number_in(values.outline, 0, 20, 2))
  cfg.others = ({ same = "same", theme = "theme", hidden = "hidden" })[values.others or ""] or "same"
  cfg.thumb_opacity = number_in(values.dim, 0.2, 1, 0.72)
  cfg.flash = values.flash ~= "0"
  cfg.pane = number_in(values.pane, 0.4, 0.85, 0.62)
  cfg.middle = number_in(values.middle, 0.3, 0.8, 0.5)
  cfg.gap = math.floor(number_in(values.gap, 0, 80, 20))
  cfg.step = number_in(values.step, 0.002, 0.1, 0.01)
  local function class_set(text)
    local classes = {}
    for item in (text or ""):gmatch("[^,]+") do
      local class = item:lower():match("^%s*(.-)%s*$")
      if class ~= "" and #class <= 80 then classes[class] = true end
    end
    return classes
  end
  cfg.full_size = class_set(values.full_size)
  cfg.confine = values.confine ~= "0"
  cfg.confine_apps = class_set(values.confine_apps)
end
read_settings()

-- Hyprland shows callback errors only in its error bar, and every config
-- reload clears that. Keep a copy, with a traceback, that survives.
local function guarded(fn)
  return function(...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if ok then
      return err
    end
    os.execute("mkdir -p " .. shell_quote(state_dir))
    -- keep the log small: a callback that fails on every frame would fill the disk
    local size = 0
    local current = io.open(error_file, "r")
    if current then
      size = current:seek("end") or 0
      current:close()
    end
    if size > ERROR_LOG_MAX then os.rename(error_file, error_file .. ".old") end
    local file = io.open(error_file, "a")
    if file then
      file:write(os.date("%Y-%m-%d %H:%M:%S "), tostring(err), "\n\n")
      file:close()
    end
    error(err, 0)
  end
end

-- On Stage layouts, focus changes that mean "put this window in the middle".
-- Keyboard navigation and hover may highlight a thumbnail without promoting
-- it; SUPER + Z promotes explicitly. Duo always promotes the focused window.
local DELIBERATE = {
  [3] = true, -- focus dispatcher (window switchers, notifications)
  [5] = true, -- click
  [8] = true, -- switch to window (soft)
  [9] = true, -- switch to window (hard)
  [16] = true, -- new window
}

-- workspace id -> list of window stable_ids. [1] is the window in the
-- middle; [2], [3], ... are thumbnail slots (alternating left and right,
-- inner column first). Windows only change slot when swapped.
local slots = {}

local function index_of(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
end

-- Opening order (stable ids only grow): who takes the middle when the middle
-- window closes, and the slot order when a workspace is first seen.
local function sequence(list)
  local seq = {}
  for i, id in ipairs(list) do
    seq[i] = id
  end
  table.sort(seq)
  return seq
end

-- Bring the window with this id into the middle by swapping it with the
-- current middle window. Unknown windows take a new slot first.
local function swap_in(list, id)
  local j = index_of(list, id)
  if not j then
    list[#list + 1] = id
    j = #list
  end
  list[1], list[j] = list[j], list[1]
end

-- Make the slot list match the windows that are actually there.
local function sync(list, windows, focused_id)
  local present = {}
  for _, w in ipairs(windows) do
    present[w.stable_id] = true
  end

  -- A window that left: the last thumbnail fills its slot, so at most one
  -- other window moves. If it was the middle one, the next window in the
  -- Alt+Tab order takes the middle.
  local i = 1
  while i <= #list do
    local id = list[i]
    if present[id] then
      i = i + 1
    elseif i == 1 and #list > 1 then
      local rest = {}
      for k = 2, #list do
        if present[list[k]] then
          rest[#rest + 1] = list[k]
        end
      end
      if #rest == 0 then
        table.remove(list, 1)
      else
        local successor = sequence(rest)[1]
        for _, cand in ipairs(sequence(rest)) do
          if cand > id then
            successor = cand
            break
          end
        end
        local j = index_of(list, successor)
        list[1] = successor
        if j == #list then
          table.remove(list)
        else
          list[j] = table.remove(list)
        end
      end
    elseif i == #list then
      table.remove(list)
    else
      list[i] = table.remove(list)
    end
  end

  -- First time this workspace is seen (e.g. after a config reload): the
  -- focused window goes in the middle, the rest in opening order.
  if #list == 0 then
    for _, id in ipairs(sequence((function()
      local ids = {}
      for _, w in ipairs(windows) do
        ids[#ids + 1] = w.stable_id
      end
      return ids
    end)())) do
      list[#list + 1] = id
    end
    if focused_id and index_of(list, focused_id) then
      swap_in(list, focused_id)
    end
    return
  end

  for _, w in ipairs(windows) do
    if not index_of(list, w.stable_id) then
      list[#list + 1] = w.stable_id
    end
  end
end

local function slots_for(ws_id)
  slots[ws_id] = slots[ws_id] or {}
  return slots[ws_id]
end

-- workspace id -> how much wider (+) or narrower (-) than the default the
-- middle window is, as a share of the screen width. Changed with the resize
-- keys and kept in a state file so config reloads don't reset it.
local center_file = state_dir .. "/center"
local center_adjust = {}
do
  local file = io.open(center_file, "r")
  if file then
    for line in file:lines() do
      local id, adjust = line:match("^(%-?%d+)%s+(%-?[%d.e+-]+)$")
      if id then
        center_adjust[tonumber(id)] = tonumber(adjust)
      end
    end
    file:close()
  end
end

local function save_center()
  os.execute("mkdir -p " .. shell_quote(state_dir))
  local file = io.open(center_file, "w")
  if not file then
    return
  end
  for id, adjust in pairs(center_adjust) do
    file:write(id, " ", adjust, "\n")
  end
  file:close()
end

local function default_share(area, horizon)
  local preferred_aspect = horizon and 2.1 or cfg.center_aspect
  local maximum = horizon and 0.76 or cfg.center_max
  return math.min(maximum, math.max(cfg.center_min, preferred_aspect / (area.w / area.h)))
end

local function center_share(area, ws_id, horizon)
  local base
  if horizon then
    -- Horizon puts its focused, landscape window between top and bottom rails.
    -- Its height is chosen so the full-width centre stays close to 2.1:1.
    base = math.min(0.76, math.max(cfg.center_min, (area.w / area.h) / 2.1))
  else
    base = default_share(area, false)
  end
  local share = base + (center_adjust[ws_id] or 0)
  return math.min(cfg.center_step_max, math.max(cfg.center_step_min, share))
end

-- Width of each side of the middle window.
local function side_geometry(area, ws_id, horizon)
  return area.w * (1 - center_share(area, ws_id, horizon)) / 2
end

-- Lay out one side's thumbnails, shaped like the middle window (so they are
-- true miniatures of it). Columns get smaller going outward (`decay`), and
-- inner columns fill first, top to bottom; each column is centred vertically.
-- For 1, 2, 3, ... columns, find the biggest inner column that still fits all
-- thumbnails, and keep the column count where that is biggest (fewer unless
-- more are clearly better): a few windows get one column of big thumbnails, and more columns only
-- appear once a column would get too crowded.
-- `inner` is the x of the edge facing the middle; `dir` is -1 (left) or 1.
local function fill_side(targets, area, inner, side_w, dir, aspect)
  local n = #targets
  if n == 0 then
    return
  end

  -- How many thumbnails each of `cols` columns holds when the inner one is w1 wide.
  local function capacities(w1, cols)
    local caps, total, w = {}, 0, w1
    for k = 1, cols do
      caps[k] = math.floor(area.h * aspect / w)
      total = total + caps[k]
      w = w * cfg.decay
    end
    return caps, total
  end

  local best
  for cols = 1, n do
    local span = (1 - cfg.decay ^ cols) / (1 - cfg.decay)
    local hi = math.min(side_w / span, area.h * aspect)
    local _, total = capacities(hi, cols)
    local w1 = hi
    if total < n then
      local lo = 0
      for _ = 1, 40 do
        local mid = (lo + hi) / 2
        if select(2, capacities(mid, cols)) >= n then
          lo = mid
        else
          hi = mid
        end
      end
      w1 = lo
    end
    -- Another column has to be clearly better (5%) to be worth adding.
    if not best or w1 > best.w1 * 1.05 then
      best = { w1 = w1, cols = cols }
    end
  end

  local caps = capacities(best.w1, best.cols)
  local x, i, w = inner, 1, best.w1
  for c = 1, best.cols do
    local count = math.min(caps[c], n - i + 1)
    if c == best.cols then
      count = n - i + 1 -- rounding: the last column takes what's left
    end
    local th = math.min(w / aspect, area.h / math.max(count, 1))
    local tw = th * aspect
    local tx = dir < 0 and (x - tw) or x
    local y = area.y + (area.h - th * count) / 2
    for j = 0, count - 1 do
      targets[i + j]:place({ x = tx, y = y + j * th, w = tw, h = th })
    end
    i = i + count
    x = x + dir * w
    w = w * cfg.decay
  end
end

-- Horizon's rails are transposed: rows of miniature windows pack across the
-- display, with further rows moving away from the focused window.
local function fill_rail(targets, area, inner, rail_h, dir, aspect)
  local n = #targets
  if n == 0 then return end

  local function capacities(h1, rows)
    local caps, total, h = {}, 0, h1
    for row = 1, rows do
      caps[row] = math.floor(area.w / (h * aspect))
      total = total + caps[row]
      h = h * cfg.decay
    end
    return caps, total
  end

  local best
  for rows = 1, n do
    local span = (1 - cfg.decay ^ rows) / (1 - cfg.decay)
    local hi = math.min(rail_h / span, area.w / aspect)
    local _, total = capacities(hi, rows)
    local h1 = hi
    if total < n then
      local lo = 0
      for _ = 1, 40 do
        local mid = (lo + hi) / 2
        if select(2, capacities(mid, rows)) >= n then lo = mid else hi = mid end
      end
      h1 = lo
    end
    if not best or h1 > best.h1 * 1.05 then best = { h1 = h1, rows = rows } end
  end

  local caps = capacities(best.h1, best.rows)
  local y, i, h = inner, 1, best.h1
  for row = 1, best.rows do
    local count = math.min(caps[row], n - i + 1)
    if row == best.rows then count = n - i + 1 end
    local th = math.min(h, area.w / (aspect * math.max(count, 1)))
    local tw = th * aspect
    local x = area.x + (area.w - tw * count) / 2
    local y0 = dir < 0 and (y - th) or y
    for col = 0, count - 1 do
      local target = targets[i + col]
      target:place({ x = x + col * tw, y = y0, w = tw, h = th })
    end
    i = i + count
    y = y + dir * h
    h = h * cfg.decay
  end
end

-- The optional stagethumbs plugin (~/.config/hypr/stagethumbs) turns
-- thumbnails into real miniatures: the app keeps its full size and is drawn
-- scaled down. Without it, thumbnails are just small windows.
local function thumbs()
  return hl.plugin and hl.plugin.stagethumbs
end

-- Register it on every config run while it is built. hl.plugin.load only adds
-- the path to Hyprland's wanted list; after each run Hyprland loads what is
-- listed and unloads what isn't. Registering it conditionally (e.g. "only if
-- not loaded yet") makes it flip between loaded and unloaded forever, which
-- freezes Hyprland.
--
-- When the Omarchy plugin loads this file at runtime (hyprctl eval), it sets
-- tableau_runtime and loads the .so itself with `hyprctl plugin load`, which
-- survives config reloads; hl.plugin.load only takes effect during a config run.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or (os.getenv("HOME") .. "/.config/hypr/")
local plugin_so = here .. "stagethumbs/stagethumbs.so"
local built = io.open(plugin_so, "r")
if built then
  built:close()
  if not _G.tableau_runtime then
    hl.plugin.load(plugin_so)
  end
end

local function show_full(target)
  local p = thumbs()
  local address = target.window and target.window.address
  if p and address then
    p.clear(address)
  end
end

-- Apps on the "never a miniature" list get a real small window instead.
local function full_size(window)
  local class = window and type(window.class) == "string" and window.class:lower() or ""
  return cfg.full_size[class] == true
end

local function show_thumbnail(target, w, h)
  local p = thumbs()
  local address = target.window and target.window.address
  if p and address then
    if full_size(target.window) then
      p.clear(address)
    else
      p.set(address, w, h)
    end
  end
end

local set_no_follow_mouse
local sync_tile_tags

-- A layout run can move a window in or out of the tiles (floated, closed, carried in).
-- Tags can't be set while a layout runs (that runs the layout again), so the outline
-- tags are brought in line right after it.
local tags_pending = false
local function after_layout()
  if tags_pending or not sync_tile_tags then return end
  tags_pending = true
  hl.timer(guarded(function()
    tags_pending = false
    sync_tile_tags()
  end), { timeout = 1, type = "oneshot" })
end

local function recalculate(ctx, horizon)
  local area = ctx.area
  if #ctx.targets == 0 then
    return
  end

  local windows, by_id, others = {}, {}, {}
  for _, target in ipairs(ctx.targets) do
    local window = target.window
    if window and window.stable_id and window.workspace then
      windows[#windows + 1] = window
      by_id[window.stable_id] = target
    else
      others[#others + 1] = target
    end
  end

  local middle, side = nil, {}
  if #windows > 0 then
    local list = slots_for(windows[1].workspace.id)
    local active = hl.get_active_window()
    sync(list, windows, active and active.stable_id)
    middle = by_id[list[1]]
    for k = 2, #list do
      side[#side + 1] = by_id[list[k]]
    end
  end
  for _, target in ipairs(others) do
    if middle then
      side[#side + 1] = target
    else
      middle = target
    end
  end

  if #side == 0 then
    show_full(middle)
    middle:place(area)
    return
  end

  local ws_id = windows[1] and windows[1].workspace.id
  if horizon then
    local rail_h = area.h * (1 - center_share(area, ws_id, true)) / 2
    local mid_h = area.h - 2 * rail_h
    if middle then
      show_full(middle)
      middle:place({ x = area.x, y = area.y + rail_h, w = area.w, h = mid_h })
    end
    for _, target in ipairs(side) do show_thumbnail(target, area.w, mid_h) end
    local top, bottom = {}, {}
    for k, target in ipairs(side) do
      local list = k % 2 == 1 and top or bottom
      list[#list + 1] = target
    end
    local aspect = area.w / mid_h
    fill_rail(top, area, area.y + rail_h, rail_h, -1, aspect)
    fill_rail(bottom, area, area.y + rail_h + mid_h, rail_h, 1, aspect)
    return
  end

  local side_w = side_geometry(area, ws_id, false)
  local mid_w = area.w - 2 * side_w
  if middle then
    show_full(middle)
    middle:place({ x = area.x + side_w, y = area.y, w = mid_w, h = area.h })
  end
  local thumb_w = area.w * default_share(area, false)
  for _, target in ipairs(side) do show_thumbnail(target, thumb_w, area.h) end
  local left, right = {}, {}
  for k, target in ipairs(side) do
    local list = k % 2 == 1 and left or right
    list[#list + 1] = target
  end
  local aspect = thumb_w / area.h
  fill_side(left, area, area.x + side_w, side_w, -1, aspect)
  fill_side(right, area, area.x + area.w - side_w, side_w, 1, aspect)
end

local function register_layout(name, definition)
  local recalculate = definition.recalculate
  definition.recalculate = function(ctx)
    recalculate(ctx)
    after_layout()
  end
  local ok, err = pcall(hl.layout.register, name, definition)
  if not ok and not tostring(err):find("already registered", 1, true) then
    error(err, 0)
  end
end

register_layout("tableau-portrait", {
  recalculate = guarded(function(ctx) recalculate(ctx, false) end),
  layout_msg = function(_, msg) if msg ~= "refresh" then return "tableau-portrait: expected refresh" end return true end,
})
register_layout("tableau-landscape", {
  recalculate = guarded(function(ctx) recalculate(ctx, true) end),
  layout_msg = function(_, msg)
    if msg ~= "refresh" then
      return "tableau-landscape: expected refresh"
    end
    return true
  end,
})

-- Stage's side rails and Horizon's top/bottom rails wrap the focused window.
local function recalculate_surround(ctx)
  local area, targets = ctx.area, ctx.targets
  if #targets == 0 then return end

  local windows, by_id, others = {}, {}, {}
  for _, target in ipairs(targets) do
    local window = target.window
    if window and window.stable_id and window.workspace then
      windows[#windows + 1] = window
      by_id[window.stable_id] = target
    else
      others[#others + 1] = target
    end
  end
  local middle, side = nil, {}
  if #windows > 0 then
    local list = slots_for(windows[1].workspace.id)
    local active = hl.get_active_window()
    sync(list, windows, active and active.stable_id)
    middle = by_id[list[1]]
    for i = 2, #list do side[#side + 1] = by_id[list[i]] end
  end
  for _, target in ipairs(others) do
    if middle then side[#side + 1] = target else middle = target end
  end

  if #side == 0 then
    show_full(middle)
    middle:place(area)
    return
  end

  local side_w, rail_h = area.w * 0.18, area.h * 0.18
  local center_w, center_h = area.w - 2 * side_w, area.h - 2 * rail_h
  local center = { x = area.x + side_w, y = area.y + rail_h, w = center_w, h = center_h }
  show_full(middle)
  middle:place(center)
  for _, target in ipairs(side) do show_thumbnail(target, center_w, center_h) end

  local left, top, right, bottom = {}, {}, {}, {}
  local rails = { left, top, right, bottom }
  for i, target in ipairs(side) do
    local rail = rails[((i - 1) % #rails) + 1]
    rail[#rail + 1] = target
  end
  local aspect = center_w / center_h
  fill_side(left, { x = area.x, y = area.y, w = side_w, h = area.h },
    area.x + side_w, side_w, -1, aspect)
  fill_rail(top, { x = center.x, y = area.y, w = center_w, h = rail_h },
    center.y, rail_h, -1, aspect)
  fill_side(right, { x = area.x + area.w - side_w, y = area.y, w = side_w, h = area.h },
    area.x + area.w - side_w, side_w, 1, aspect)
  fill_rail(bottom, { x = center.x, y = center.y + center_h, w = center_w, h = rail_h },
    center.y + center_h, rail_h, 1, aspect)
end

register_layout("tableau-centerpiece", {
  recalculate = guarded(recalculate_surround),
  layout_msg = function(_, msg)
    if msg ~= "refresh" then return "tableau-centerpiece: expected refresh" end
    return true
  end,
})

-- Focused window fills the main 62% pane; clicking a side window promotes it
-- while the other side windows keep their positions and relative order.
local function refresh_message(name)
  return function(_, msg)
    if msg ~= "refresh" then return name .. ": expected refresh" end
    return true
  end
end

local duo_shares = {}

local function duo_recalculate(ctx, main_edge)
  local targets, area = ctx.targets, ctx.area
  local count = #targets
  if count == 0 then return end

  local windows, by_id, other = {}, {}, {}
  for _, target in ipairs(targets) do
    local window = target.window
    if window and window.stable_id and window.workspace then
      windows[#windows + 1] = window
      by_id[window.stable_id] = target
    else
      other[#other + 1] = target
    end
  end
  local ordered = {}
  if #windows > 0 then
    local list = slots_for(windows[1].workspace.id)
    local active = hl.get_active_window()
    sync(list, windows, active and active.stable_id)
    for _, id in ipairs(list) do
      if by_id[id] then ordered[#ordered + 1] = by_id[id] end
    end
  end
  for _, target in ipairs(other) do ordered[#ordered + 1] = target end
  if #ordered == 1 then ordered[1]:place(area); return end

  local main = ordered[1]
  local side_count = #ordered - 1
  local ws_id = windows[1] and windows[1].workspace.id
  if main_edge == "center" then
    -- Triptych: the main window in the middle, the others stacked on its left and
    -- right in turn (first to the left), each side sharing its height evenly.
    local share = duo_shares[ws_id] or cfg.middle
    local main_w = math.floor(area.w * share)
    local left_w = math.floor((area.w - main_w) / 2)
    local right_w = area.w - main_w - left_w
    main:place({ x = area.x + left_w, y = area.y, w = main_w, h = area.h })
    local left, right = {}, {}
    for i = 2, #ordered do
      local list = (i % 2 == 0) and left or right
      list[#list + 1] = ordered[i]
    end
    if #right == 0 then
      -- one other window: it gets the whole left, the main window the rest
      main:place({ x = area.x + left_w, y = area.y, w = area.w - left_w, h = area.h })
    end
    for side, list in pairs({ [1] = left, [2] = right }) do
      local x = side == 1 and area.x or (area.x + left_w + main_w)
      local w = side == 1 and left_w or right_w
      for k, target in ipairs(list) do
        local y = area.y + (k - 1) * area.h / #list
        local h = k == #list and (area.y + area.h - y) or area.h / #list
        target:place({ x = x, y = y, w = w, h = h })
      end
    end
    return
  end
  local share = duo_shares[ws_id] or cfg.pane
  if main_edge == "bento" then
    -- Bento: the main pane on the left; on the right the next window takes the top
    -- half, and the rest share the bottom half side by side.
    local main_w = math.floor(area.w * share)
    local side_x, side_w = area.x + main_w, area.w - main_w
    main:place({ x = area.x, y = area.y, w = main_w, h = area.h })
    if side_count == 1 then
      ordered[2]:place({ x = side_x, y = area.y, w = side_w, h = area.h })
      return
    end
    local top_h = math.floor(area.h / 2)
    ordered[2]:place({ x = side_x, y = area.y, w = side_w, h = top_h })
    local rest = side_count - 1
    for i = 3, #ordered do
      local x = side_x + (i - 3) * side_w / rest
      local w = i == #ordered and (side_x + side_w - x) or side_w / rest
      ordered[i]:place({ x = x, y = area.y + top_h, w = w, h = area.h - top_h })
    end
    return
  end
  if main_edge == "left" or main_edge == "right" then
    local main_w = math.floor(area.w * share)
    local side_w = area.w - main_w
    local main_x = main_edge == "left" and area.x or (area.x + side_w)
    local side_x = main_edge == "left" and (area.x + main_w) or area.x
    main:place({ x = main_x, y = area.y, w = main_w, h = area.h })
    local row_h = area.h / side_count
    for i = 2, #ordered do
      local row = i - 2
      local y = area.y + row * row_h
      local h = i == #ordered and (area.y + area.h - y) or row_h
      ordered[i]:place({ x = side_x, y = y, w = side_w, h = h })
    end
  else
    local main_h = math.floor(area.h * share)
    local side_h = area.h - main_h
    local main_y = main_edge == "top" and area.y or (area.y + side_h)
    local side_y = main_edge == "top" and (area.y + main_h) or area.y
    main:place({ x = area.x, y = main_y, w = area.w, h = main_h })
    local cell_w = area.w / side_count
    for i = 2, #ordered do
      local col = i - 2
      local x = area.x + col * cell_w
      local w = i == #ordered and (area.x + area.w - x) or cell_w
      ordered[i]:place({ x = x, y = side_y, w = w, h = side_h })
    end
  end
end

register_layout("tableau-diptych-left", {
  recalculate = guarded(function(ctx) duo_recalculate(ctx, "left") end),
  layout_msg = refresh_message("tableau-diptych-left"),
})
register_layout("tableau-diptych-right", {
  recalculate = guarded(function(ctx) duo_recalculate(ctx, "right") end),
  layout_msg = refresh_message("tableau-diptych-right"),
})
register_layout("tableau-diptych-top", {
  recalculate = guarded(function(ctx) duo_recalculate(ctx, "top") end),
  layout_msg = refresh_message("tableau-diptych-top"),
})
register_layout("tableau-diptych-bottom", {
  recalculate = guarded(function(ctx) duo_recalculate(ctx, "bottom") end),
  layout_msg = refresh_message("tableau-diptych-bottom"),
})
register_layout("tableau-triptych", {
  recalculate = guarded(function(ctx) duo_recalculate(ctx, "center") end),
  layout_msg = refresh_message("tableau-triptych"),
})
register_layout("tableau-bento", {
  recalculate = guarded(function(ctx) duo_recalculate(ctx, "bento") end),
  layout_msg = refresh_message("tableau-bento"),
})
local balance_columns = {}
local balance_weights = {}
local linear_weights = {}
local spiral_weights = {}

-- a tile's weight after one resize step: `amount` is the share of the screen to
-- add (negative takes it away)
local function resize_weight(weights, id, amount)
  local current = weights[id] or 1
  return math.max(0.25, math.min(4, current * math.exp(2.5 * amount)))
end

local function grid_shape(area, count, preferred_aspect)
  local best_cols, best_rows, best_score
  for cols = 1, count do
    local rows = math.ceil(count / cols)
    local cell_aspect = (area.w * rows) / (area.h * cols)
    local empty = cols * rows - count
    local score = math.abs(math.log(cell_aspect / preferred_aspect)) + 0.30 * empty / count
    if not best_score or score < best_score then
      best_cols, best_rows, best_score = cols, rows, score
    end
  end
  return best_cols, best_rows
end

local function place_weighted_grid(ordered, area, cols, rows, gap, ws_id)
  local count = #ordered
  if count == 0 then return end
  if count == 1 then ordered[1]:place(area); return end
  local weights = balance_weights[ws_id] or {}
  local col_sum, col_count, row_sum, row_count = {}, {}, {}, {}
  for i, target in ipairs(ordered) do
    local window = target.window
    local weight = window and window.stable_id and (weights[window.stable_id] or 1) or 1
    local row, col = math.floor((i - 1) / cols) + 1, (i - 1) % cols + 1
    col_sum[col] = (col_sum[col] or 0) + weight
    col_count[col] = (col_count[col] or 0) + 1
    row_sum[row] = (row_sum[row] or 0) + weight
    row_count[row] = (row_count[row] or 0) + 1
  end
  local col_total, row_total = 0, 0
  for col = 1, cols do
    col_sum[col] = col_sum[col] / col_count[col]
    col_total = col_total + col_sum[col]
  end
  for row = 1, rows do
    row_sum[row] = row_sum[row] / row_count[row]
    row_total = row_total + row_sum[row]
  end
  local gx = math.min(gap, area.w / math.max(cols * 2, 1))
  local gy = math.min(gap, area.h / math.max(rows * 2, 1))
  local usable_w, usable_h = area.w - gx * (cols - 1), area.h - gy * (rows - 1)
  local widths, heights = {}, {}
  for col = 1, cols do widths[col] = usable_w * col_sum[col] / col_total end
  for row = 1, rows do heights[row] = usable_h * row_sum[row] / row_total end

  local row_y = area.y
  for row = 1, rows do
    local first = (row - 1) * cols + 1
    local in_row = math.min(cols, count - first + 1)
    local row_w = gx * (in_row - 1)
    for col = 1, in_row do row_w = row_w + widths[col] end
    local x = area.x + (area.w - row_w) / 2
    for col = 1, in_row do
      local target = ordered[first + col - 1]
      target:place({ x = x, y = row_y, w = widths[col], h = heights[row] })
      x = x + widths[col] + gx
    end
    row_y = row_y + heights[row] + gy
  end
end

local function balance_layout(ctx)
  local targets, area = ctx.targets, ctx.area
  local windows, by_id, ordered = {}, {}, {}
  for _, target in ipairs(targets) do
    local window = target.window
    if window and window.stable_id and window.workspace then
      windows[#windows + 1] = window
      by_id[window.stable_id] = target
    else
      ordered[#ordered + 1] = target
    end
  end
  if #windows > 0 then
    local list = slots_for(windows[1].workspace.id)
    sync(list, windows, nil)
    for _, id in ipairs(list) do
      if by_id[id] then ordered[#ordered + 1] = by_id[id] end
    end
  end
  local count = #ordered
  if count == 0 then return end
  if count == 1 then ordered[1]:place(area); return end

  -- Pick a screen-shaped grid. Per-window weights shift shared row and column
  -- sizes, so resizing one tile also redistributes space across its neighbours.
  local best_cols, best_rows = grid_shape(area, count, 1.55)
  local ws_id = windows[1] and windows[1].workspace.id
  if ws_id then balance_columns[ws_id] = best_cols end
  place_weighted_grid(ordered, area, best_cols, best_rows, 0, ws_id)
end

register_layout("tableau-mosaic", {
  recalculate = guarded(balance_layout),
  layout_msg = refresh_message("tableau-mosaic"),
})

-- Stable, focus-first ordering shared by the additional tiled compositions.
local function ordered_targets(ctx)
  local windows, by_id, ordered = {}, {}, {}
  for _, target in ipairs(ctx.targets) do
    local window = target.window
    if window and window.stable_id and window.workspace then
      windows[#windows + 1] = window
      by_id[window.stable_id] = target
    else
      ordered[#ordered + 1] = target
    end
  end
  if #windows > 0 then
    local list = slots_for(windows[1].workspace.id)
    local active = hl.get_active_window()
    sync(list, windows, active and active.stable_id)
    for _, id in ipairs(list) do
      if by_id[id] then ordered[#ordered + 1] = by_id[id] end
    end
  end
  return ordered, windows
end

local function linear_layout(ctx, horizontal)
  local area = ctx.area
  local ordered, windows = ordered_targets(ctx)
  local count = #ordered
  if count == 0 then return end
  local ws_id = windows[1] and windows[1].workspace.id
  local weights = linear_weights[ws_id] or {}
  local total = 0
  for _, target in ipairs(ordered) do
    local window = target.window
    total = total + (window and window.stable_id and (weights[window.stable_id] or 1) or 1)
  end
  local offset = 0
  for _, target in ipairs(ordered) do
    local window = target.window
    local weight = window and window.stable_id and (weights[window.stable_id] or 1) or 1
    local share = weight / total
    if horizontal then
      local width = area.w * share
      target:place({ x = area.x + offset, y = area.y, w = width, h = area.h })
      offset = offset + width
    else
      local height = area.h * share
      target:place({ x = area.x, y = area.y + offset, w = area.w, h = height })
      offset = offset + height
    end
  end
end

local function strip_layout(ctx) linear_layout(ctx, true) end
local function column_layout(ctx) linear_layout(ctx, false) end

local function spiral_layout(ctx)
  local area = ctx.area
  local ordered, windows = ordered_targets(ctx)
  local count = #ordered
  if count == 0 then return end
  local ws_id = windows[1] and windows[1].workspace.id
  local weights = spiral_weights[ws_id] or {}
  local rest = { x = area.x, y = area.y, w = area.w, h = area.h }
  for i, target in ipairs(ordered) do
    if i == count then
      target:place(rest)
      break
    end
    local window = target.window
    local next_window = ordered[i + 1].window
    local weight = window and window.stable_id and (weights[window.stable_id] or 1) or 1
    local next_weight = next_window and next_window.stable_id and (weights[next_window.stable_id] or 1) or 1
    local share = weight / (weight + next_weight)
    if rest.w >= rest.h then
      local w = rest.w * share
      target:place({ x = rest.x, y = rest.y, w = w, h = rest.h })
      rest = { x = rest.x + w, y = rest.y, w = rest.w - w, h = rest.h }
    else
      local h = rest.h * share
      target:place({ x = rest.x, y = rest.y, w = rest.w, h = h })
      rest = { x = rest.x, y = rest.y + h, w = rest.w, h = rest.h - h }
    end
  end
end

local function place_grid(ordered, area, preferred_aspect, gap)
  local count = #ordered
  if count == 0 then return end
  if count == 1 then ordered[1]:place(area); return end
  local cols, rows = grid_shape(area, count, preferred_aspect)
  local gx = math.min(gap, area.w / math.max(cols * 2, 1))
  local gy = math.min(gap, area.h / math.max(rows * 2, 1))
  local cell_w = (area.w - gx * (cols - 1)) / cols
  local cell_h = (area.h - gy * (rows - 1)) / rows
  for i, target in ipairs(ordered) do
    local row = math.floor((i - 1) / cols)
    local first = row * cols + 1
    local in_row = math.min(cols, count - first + 1)
    local col = (i - 1) % cols
    local row_w = in_row * cell_w + (in_row - 1) * gx
    target:place({
      x = area.x + (area.w - row_w) / 2 + col * (cell_w + gx),
      y = area.y + row * (cell_h + gy), w = cell_w, h = cell_h,
    })
  end
end

-- Lay out live miniatures that all share one shape (`aspect`, width over height) in
-- a grid as large as fits `area`, the last row centred. Every tile is a true
-- miniature of a window of that shape, so nothing is drawn squashed.
local function place_miniatures(targets, area, aspect, gap)
  local n = #targets
  if n == 0 then return end
  local best
  for cols = 1, n do
    local rows = math.ceil(n / cols)
    local gx = math.min(gap, area.w / math.max(cols * 4, 1))
    local gy = math.min(gap, area.h / math.max(rows * 4, 1))
    local w = math.min((area.w - gx * (cols - 1)) / cols, (area.h - gy * (rows - 1)) / rows * aspect)
    if not best or w > best.w + 0.01 then best = { w = w, cols = cols, rows = rows, gx = gx, gy = gy } end
  end
  local w, h = best.w, best.w / aspect
  local grid_h = best.rows * h + (best.rows - 1) * best.gy
  local y0 = area.y + (area.h - grid_h) / 2
  for i, target in ipairs(targets) do
    local row = math.floor((i - 1) / best.cols)
    local col = (i - 1) % best.cols
    local in_row = math.min(best.cols, n - row * best.cols)
    local row_w = in_row * w + (in_row - 1) * best.gx
    target:place({
      x = area.x + (area.w - row_w) / 2 + col * (w + best.gx),
      y = y0 + row * (h + best.gy), w = w, h = h,
    })
  end
end

-- The size a window shown as a miniature believes it has: the same as in Portrait
-- (side galleries) or Landscape (top and bottom galleries), at their default size, so
-- a miniature looks the same however large the main pane is made.
local function normal_size(area, horizontal)
  if horizontal then
    return area.w * default_share(area, false), area.h
  end
  return area.w, area.h * math.min(0.76, math.max(cfg.center_min, (area.w / area.h) / 2.1))
end

local function gallery_layout(ctx, edge)
  local area = ctx.area
  local ordered, windows = ordered_targets(ctx)
  local count = #ordered
  if count == 0 then return end
  if count == 1 then show_full(ordered[1]); ordered[1]:place(area); return end
  local ws_id = windows[1] and windows[1].workspace.id
  local horizontal = edge == "left" or edge == "right"
  local axis = horizontal and area or { w = area.h, h = area.w }
  local share = center_share(axis, ws_id, false)
  local main, side = ordered[1], {}
  for i = 2, count do side[#side + 1] = ordered[i] end
  local main_area, side_area
  if horizontal then
    local main_w = area.w * share
    if edge == "right" then
      main_area = { x = area.x, y = area.y, w = main_w, h = area.h }
      side_area = { x = area.x + main_w, y = area.y, w = area.w - main_w, h = area.h }
    else
      side_area = { x = area.x, y = area.y, w = area.w - main_w, h = area.h }
      main_area = { x = area.x + side_area.w, y = area.y, w = main_w, h = area.h }
    end
  else
    local main_h = area.h * share
    if edge == "bottom" then
      main_area = { x = area.x, y = area.y, w = area.w, h = main_h }
      side_area = { x = area.x, y = area.y + main_h, w = area.w, h = area.h - main_h }
    else
      side_area = { x = area.x, y = area.y, w = area.w, h = area.h - main_h }
      main_area = { x = area.x, y = area.y + side_area.h, w = area.w, h = main_h }
    end
  end
  show_full(main)
  main:place(main_area)
  local full_w, full_h = normal_size(area, horizontal)
  for _, target in ipairs(side) do show_thumbnail(target, full_w, full_h) end
  place_miniatures(side, side_area, full_w / full_h, 8)
end

local function spread_layout(ctx)
  local ordered, windows = ordered_targets(ctx)
  if #ordered == 0 then return end
  local cols, rows = grid_shape(ctx.area, #ordered, 1.55)
  local ws_id = windows[1] and windows[1].workspace.id
  if ws_id then balance_columns[ws_id] = cols end
  place_weighted_grid(ordered, ctx.area, cols, rows, cfg.gap, ws_id)
end

register_layout("tableau-strip", { recalculate = guarded(strip_layout), layout_msg = refresh_message("tableau-strip") })
register_layout("tableau-column", { recalculate = guarded(column_layout), layout_msg = refresh_message("tableau-column") })
register_layout("tableau-spiral", { recalculate = guarded(spiral_layout), layout_msg = refresh_message("tableau-spiral") })
register_layout("tableau-gallery-bottom", { recalculate = guarded(function(ctx) gallery_layout(ctx, "bottom") end), layout_msg = refresh_message("tableau-gallery-bottom") })
register_layout("tableau-gallery-right", { recalculate = guarded(function(ctx) gallery_layout(ctx, "right") end), layout_msg = refresh_message("tableau-gallery-right") })
register_layout("tableau-gallery-left", { recalculate = guarded(function(ctx) gallery_layout(ctx, "left") end), layout_msg = refresh_message("tableau-gallery-left") })
register_layout("tableau-gallery-top", { recalculate = guarded(function(ctx) gallery_layout(ctx, "top") end), layout_msg = refresh_message("tableau-gallery-top") })
register_layout("tableau-spread", { recalculate = guarded(spread_layout), layout_msg = refresh_message("tableau-spread") })

-- Helpers for the Stage and Horizon window-slot model.

local function selector(ws)
  return ws.id > 0 and tostring(ws.id) or ("name:" .. ws.name)
end

local function is_stage(ws)
  return ws and not ws.special and (ws.tiled_layout == LAYOUT
    or ws.tiled_layout == HORIZON_LAYOUT or ws.tiled_layout == SURROUND_LAYOUT
    or ws.tiled_layout == GALLERY_LAYOUT or ws.tiled_layout == GALLERY_RIGHT_LAYOUT
    or ws.tiled_layout == GALLERY_LEFT_LAYOUT or ws.tiled_layout == GALLERY_TOP_LAYOUT)
end

local function is_duo(ws)
  return ws and not ws.special
    and (ws.tiled_layout == "lua:tableau-diptych-left" or ws.tiled_layout == "lua:tableau-diptych-right"
      or ws.tiled_layout == "lua:tableau-diptych-top" or ws.tiled_layout == "lua:tableau-diptych-bottom"
      or ws.tiled_layout == "lua:tableau-triptych" or ws.tiled_layout == "lua:tableau-bento")
end

local function is_balance(ws)
  return ws and not ws.special
    and (ws.tiled_layout == "lua:tableau-mosaic" or ws.tiled_layout == "lua:tableau-spread")
end

local function is_tableau_layout(ws)
  return ws and not ws.special and (is_stage(ws) or is_duo(ws) or is_balance(ws)
    or ws.tiled_layout == "lua:tableau-strip" or ws.tiled_layout == "lua:tableau-column"
    or ws.tiled_layout == "lua:tableau-spiral")
end

local function tiled_windows(ws)
  local windows = {}
  for _, w in ipairs(hl.get_workspace_windows(selector(ws))) do
    if w.mapped and not w.floating then
      windows[#windows + 1] = w
    end
  end
  return windows
end

-- Layout messages go to the focused window's layout, so only send one when
-- that is a tiled window on an Tableau workspace. Otherwise it could land on a
-- native layout and show up as an error.
local function stage_focused()
  local w = hl.get_active_window()
  if w and w.mapped and not w.floating and is_stage(w.workspace) then
    return w.workspace
  end
end

-- Stage layouts can keep keyboard focus on a thumbnail, while Duo layouts
-- always make the focused window the main pane. Share focus navigation and
-- explicit promotion across both families.
local function tableau_focused()
  local ws = stage_focused()
  if ws then return ws end
  local w = hl.get_active_window()
  if w and w.mapped and not w.floating and is_tableau_layout(w.workspace) then
    return w.workspace
  end
end

-- Thumbnails must not grab focus just because the mouse passes over them,
-- or a later click on them wouldn't register as a new focus. They also carry
-- the "stage-thumb" tag, which the highlight rules below style. The tag itself
-- is the source of truth (it survives config reloads, a Lua table wouldn't);
-- the hover block is always set together with it.
local function has_tag(window, name)
  for _, tag in ipairs(type(window.tags) == "table" and window.tags or {}) do
    if tag == name or tag == name .. "*" then
      return true
    end
  end
  return false
end

local function has_thumb_tag(window)
  return has_tag(window, "stage-thumb")
end

-- window: a window object or an "address:0x..." selector
local function tag_window(window, tag, on)
  hl.dispatch(hl.dsp.window.tag({ window = window, tag = (on and "+" or "-") .. tag }))
end

set_no_follow_mouse = function(window, blocked)
  if not window or not window.stable_id then return end
  local marked = has_tag(window, "tableau-no-follow")
  if blocked then
    if marked then return end
    hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = "no_follow_mouse", value = "1" }))
    tag_window(window, "tableau-no-follow", true)
  else
    -- stage-thumb is the legacy pointer-guard marker used before Tableau had a
    -- shared tag. Clear its property too when switching out of that layout.
    if not marked and not has_thumb_tag(window) then return end
    hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = "no_follow_mouse", value = "0" }))
    if marked then tag_window(window, "tableau-no-follow", false) end
  end
end

local function set_thumb(window, is_thumb)
  if not window or not window.stable_id then
    return
  end
  set_no_follow_mouse(window, is_thumb)
  if has_thumb_tag(window) == is_thumb then return end
  tag_window(window, "stage-thumb", is_thumb)
  if not is_thumb and has_tag(window, "stage-hover") then
    tag_window(window, "stage-hover", false)
  end
end

-- A game moves the pointer back to its middle after every move of the mouse. A quick
-- move carries the pointer out of the window before the game gets to that, onto the
-- window beside it, and the game stops turning. Steam and Wine games, gamescope, and
-- the classes listed in the panel keep the pointer inside while they have the focus.
local function keeps_pointer(window)
  local class = type(window.class) == "string" and window.class:lower() or ""
  if cfg.confine_apps[class] then return true end
  if not cfg.confine then return false end
  return class:find("^steam_app_") ~= nil or class:find("%.exe$") ~= nil or class == "gamescope"
    or window.content_type == "game"
end

-- Every tiled window on a workspace with a Tableau layout carries "tableau-tile", for
-- the outline rule, and "tableau-confine" when the pointer stays inside it: a game in the
-- main spot, or any tile on a layout without one. Every other window loses them. Only
-- changes are dispatched.
sync_tile_tags = function()
  for _, w in ipairs(hl.get_windows()) do
    if w.mapped and w.stable_id then
      local want = not w.floating and is_tableau_layout(w.workspace) == true
      if has_tag(w, "tableau-tile") ~= want then tag_window(w, "tableau-tile", want) end
      -- never a miniature: a miniature with the focus would hold the pointer in its small box
      local main_spot = not (is_stage(w.workspace) or is_duo(w.workspace)) or slots_for(w.workspace.id)[1] == w.stable_id
      local confine = want and main_spot and keeps_pointer(w)
      if has_tag(w, "tableau-confine") ~= confine then tag_window(w, "tableau-confine", confine) end
    end
  end
end

local function update_thumbs(ws)
  local list = slots[ws.id] or {}
  for _, w in ipairs(tiled_windows(ws)) do
    set_thumb(w, list[1] ~= w.stable_id)
  end
end

-- Run outside layout recalculation callbacks: setting a window property causes
-- Hyprland to recalculate the layout, so doing it inside recalculate recurses.
local function sync_active_pointer_guard()
  local ws = hl.get_active_workspace()
  if not ws then return end
  local windows = tiled_windows(ws)
  if is_duo(ws) then
    local list = slots_for(ws.id)
    local active = hl.get_active_window()
    sync(list, windows, active and active.stable_id)
    for _, window in ipairs(windows) do
      set_no_follow_mouse(window, list[1] ~= window.stable_id)
    end
  elseif is_stage(ws) then
    local list = slots_for(ws.id)
    local active = hl.get_active_window()
    sync(list, windows, active and active.stable_id)
    update_thumbs(ws)
  else
    for _, window in ipairs(windows) do set_thumb(window, false) end
  end
  sync_tile_tags()
end

-- Highlighting, all done with tags and window rules: taking a tag off puts the
-- window straight back under Omarchy's own opacity and border rules.
--   stage-thumb  every thumbnail: dimmed unless focused; the focused one (e.g.
--                reached with SUPER + arrows) gets a thick border in the
--                theme's active border colour, the others an invisible one
--   stage-hover  the thumbnail under the mouse: opaque, softer border
--   stage-swap   both windows of a swap, briefly: border in the accent colour.
--                Colour only, so no window changes size (and re-lays out) for it
local function accent(alpha)
  local ok, opt = pcall(hl.get_config, "general.col.active_border")
  local argb = ok and type(opt) == "table" and type(opt.colors) == "table" and opt.colors[1]
  local rgb = type(argb) == "string" and argb:match("^0[xX]%x%x(%x%x%x%x%x%x)$") or "ffffff"
  return "rgba(" .. rgb .. alpha .. ")"
end

-- The theme's active border as a border_color gradient: "rgba(..) rgba(..) 45deg".
-- The angle is always there, so whatever follows it is read as the inactive colors.
local function active_gradient()
  local ok, opt = pcall(hl.get_config, "general.col.active_border")
  local parts = {}
  if ok and type(opt) == "table" and type(opt.colors) == "table" then
    for _, color in ipairs(opt.colors) do
      local alpha, rgb = nil, nil
      if type(color) == "string" then alpha, rgb = color:match("^0[xX](%x%x)(%x%x%x%x%x%x)$") end
      if rgb then parts[#parts + 1] = "rgba(" .. rgb .. alpha .. ")" end
      if #parts == 10 then break end
    end
  end
  if #parts == 0 then return accent("ff") .. " 0deg" end
  local angle = ok and type(opt) == "table" and tonumber(opt.angle) or 0
  parts[#parts + 1] = string.format("%ddeg", math.floor(angle + 0.5))
  return table.concat(parts, " ")
end

-- Every window of a Tableau layout carries the "tableau-tile" tag and gets the same
-- outline, focused or not; thumbnails, hovered ones and the two of a swap get theirs on
-- top. The rules are named, so new settings replace them without a config reload: the
-- old set is switched off and a fresh one is added after it, in the same order.
local rule_names = {}
local rule_generation = 0
local function apply_rules()
  for _, name in ipairs(rule_names) do pcall(hl.window_rule, { name = name, enabled = false }) end
  rule_names = {}
  rule_generation = rule_generation + 1
  local function rule(kind, props, optional)
    props.name = "tableau-" .. kind .. "-" .. rule_generation
    rule_names[#rule_names + 1] = props.name
    local ok, err = pcall(hl.window_rule, props)
    if not ok and not optional then error(err, 0) end
  end
  local active = active_gradient()
  local tile = { match = { tag = "tableau-tile" }, border_size = cfg.outline }
  if cfg.others == "same" then
    tile.border_color = active .. " " .. active
  elseif cfg.others == "hidden" then
    tile.border_color = active .. " rgba(00000000) 0deg"
  end
  rule("tile", tile)
  rule("thumb", { match = { tag = "stage-thumb" }, opacity = string.format("1.0 %.2f", cfg.thumb_opacity) })
  rule("hover", { match = { tag = "stage-hover" }, opacity = "1.0 1.0",
    border_color = accent("ff") .. " " .. accent("99") })
  rule("swap", { match = { tag = "stage-swap" }, opacity = "1.0 1.0",
    border_color = accent("ff") .. " " .. accent("ff") })
  -- Hyprland keeps the pointer inside such a window only while it has the focus. A
  -- Hyprland that doesn't know the rule goes without it.
  rule("confine", { match = { tag = "tableau-confine" }, confine_pointer = true }, true)
end
apply_rules()

-- Flash both windows of a swap. A window flashed again before its last flash
-- ended keeps the newer one; a window that closed meanwhile is skipped.
local flash_gen = {}
local function flash(ws, ids)
  if not cfg.flash then return end
  local want = {}
  for _, id in ipairs(ids) do
    want[id] = true
  end
  for _, w in ipairs(tiled_windows(ws)) do
    if want[w.stable_id] then
      local target = "address:" .. w.address
      local gen = (flash_gen[target] or 0) + 1
      flash_gen[target] = gen
      tag_window(target, "stage-swap", true)
      hl.timer(guarded(function()
        if flash_gen[target] == gen then
          flash_gen[target] = nil
          pcall(tag_window, target, "stage-swap", false)
        end
      end), { timeout = cfg.swap_flash_ms, type = "oneshot" })
    end
  end
end

-- swap_in plus the flash, for swaps the user caused
local function swap_and_flash(ws, list, id)
  local old = list[1]
  swap_in(list, id)
  if old and old ~= id then
    flash(ws, { old, id })
  end
end

-- Focus events fire mid-update; act on the next tick, once state has settled.
local pending = false
local function relayout_soon()
  if pending then
    return
  end
  pending = true
  hl.timer(guarded(function()
    pending = false
    local ws = hl.get_active_workspace()
    if is_duo(ws) then
      hl.dispatch(hl.dsp.layout("refresh"))
      sync_active_pointer_guard()
      return
    end
    if is_balance(ws) then
      hl.dispatch(hl.dsp.layout("refresh"))
      sync_active_pointer_guard()
      return
    end
    ws = tableau_focused()
    if ws then
      hl.dispatch(hl.dsp.layout("refresh"))
      if is_stage(ws) then update_thumbs(ws) end
    end
  end), { timeout = 1, type = "oneshot" })
end

-- Set while stage navigation moves focus, so that focus isn't a promotion.
local navigating = false

-- For finding out what Hyprland did on someone's desktop: one line per focus change.
local function trace(...)
  if not cfg.trace then return end
  local file = io.open(trace_file, "a")
  if not file then return end
  if (file:seek("end") or 0) < ERROR_LOG_MAX then
    file:write(os.date("%H:%M:%S "), table.concat({ ... }, " "), "\n")
  end
  file:close()
end

-- Hyprland says "click" for more than a click. When an X11 window asks for a size, which
-- a game in a full screen mode does again and again, Hyprland puts the focus on whatever
-- is under the pointer, past the hover block, and calls that a click too. It does the
-- same when a mouse button is let go after the pointer left the window it was pressed in.
-- So while an X11 window is open, only a press of a mouse button is a click.
local pressed = false
local press_seen = false -- the buttons are known to report: until then every click counts
local press_count = 0

local function super_down()
  for _, key in ipairs({ "Super_L", "Super_R" }) do
    local ok, down = pcall(hl.is_key_down, key)
    if ok and down then return true end
  end
  return false
end

local function promote(ws, window)
  local list = slots_for(ws.id)
  if is_duo(ws) then sync(list, tiled_windows(ws), window.stable_id) end
  swap_and_flash(ws, list, window.stable_id)
  if is_duo(ws) then sync_active_pointer_guard() end
  relayout_soon()
end

-- A click on a miniature that already has the focus changes no focus, so Hyprland says
-- nothing about it: once the click is through, the focused window under the pointer
-- comes forward if it isn't there yet. Super + a button moves and resizes windows.
local function after_press(count)
  if count ~= press_count or super_down() then return end
  local w = hl.get_active_window()
  if not w or not w.stable_id or w.floating or not w.workspace or not w.at or not w.size then return end
  local ws = w.workspace
  if not (is_stage(ws) or is_duo(ws)) or slots_for(ws.id)[1] == w.stable_id then return end
  local ok, pos = pcall(hl.get_cursor_pos)
  if not ok or type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end
  if pos.x < w.at.x or pos.y < w.at.y or pos.x >= w.at.x + w.size.x or pos.y >= w.at.y + w.size.y then return end
  trace("a click on", tostring(w.class), "brings it forward")
  promote(ws, w)
end

local function mouse_pressed()
  pressed = true
  press_seen = true
  press_count = press_count + 1
  local mine = press_count
  hl.timer(function() if press_count == mine then pressed = false end end, { timeout = 150, type = "oneshot" })
  hl.timer(guarded(function() after_press(mine) end), { timeout = 1, type = "oneshot" })
end
-- The buttons are only watched: the press goes on to the window as it always did.
for _, button in ipairs({ 272, 273, 274, 275, 276 }) do
  pcall(hl.bind, "mouse:" .. button, mouse_pressed,
    { non_consuming = true, ignore_mods = true, dont_inhibit = true, submap_universal = true })
end

local function x11_open()
  for _, w in ipairs(hl.get_windows()) do
    if w.mapped and w.xwayland then return true end
  end
  return false
end

-- A "click" nobody made: one that came without a press of a button.
local function not_a_click(reason)
  if reason ~= 5 or not press_seen then return false end
  local was_pressed = pressed
  pressed = false -- one press, one click
  return not was_pressed and x11_open()
end

-- Focus a window without moving the pointer: Hyprland takes the pointer along unless
-- warps are off, so they are off for that one step. When that can't be done, nothing is.
local function focus_in_place(w)
  local known, warps_off = pcall(hl.get_config, "cursor.no_warps")
  if not known then return false end
  local switch = not (warps_off == true or warps_off == 1)
  if switch and not pcall(hl.config, { cursor = { no_warps = true } }) then return false end
  navigating = true
  local ok = pcall(hl.dispatch, hl.dsp.focus({ window = w }))
  navigating = false
  if switch then pcall(hl.config, { cursor = { no_warps = false } }) end
  return ok
end

-- The window that had the focus on each workspace before the pointer was handed it.
local last_focus = {}

-- Give the focus back to the window that had it, and leave the pointer where it is, so
-- it can go on to the window it was heading for. A miniature only: the window in the
-- main spot may have the focus. Every time the game asks again, as long as it asks: a
-- limit would leave the focus on a miniature in the end.
local function return_focus(taker)
  local ws = taker.workspace
  local back = ws and last_focus[ws.id]
  if not back or back == taker.stable_id or taker.floating then return end
  if not (is_stage(ws) or is_duo(ws)) or slots_for(ws.id)[1] == taker.stable_id then return end
  local count = press_count
  hl.timer(guarded(function()
    if press_count ~= count then return end -- a click came first: it decides
    local active = hl.get_active_window()
    if not active or active.stable_id ~= taker.stable_id then return end
    for _, w in ipairs(tiled_windows(ws)) do
      if w.stable_id == back then
        trace("focus goes back to", tostring(w.class))
        focus_in_place(w)
        return
      end
    end
  end), { timeout = 1, type = "oneshot" })
end

hl.on("window.active", guarded(function(window, reason)
  if not window or not window.stable_id then
    return
  end
  local had_press = pressed
  local stray = not_a_click(reason)
  trace("focus", tostring(window.class), "reason", tostring(reason), "press", tostring(had_press),
    "buttons seen", tostring(press_seen), stray and "not a click" or "", navigating and "by the keys" or "")
  if not stray and window.workspace then
    last_focus[window.workspace.id] = window.stable_id
  end
  if navigating then
    return
  end
  if stray and (is_duo(window.workspace) or is_stage(window.workspace)) then
    return_focus(window)
    return
  end
  if is_duo(window.workspace) and not window.floating then
    promote(window.workspace, window)
    return
  end
  if window.workspace and not is_stage(window.workspace) then
    for _, candidate in ipairs(tiled_windows(window.workspace)) do
      set_thumb(candidate, false)
      set_no_follow_mouse(candidate, false)
    end
    return
  end
  if not DELIBERATE[reason] or window.floating then
    return
  end
  swap_and_flash(window.workspace, slots_for(window.workspace.id), window.stable_id)
  relayout_soon()
end))

hl.on("window.close", guarded(relayout_soon))
hl.on("workspace.active", guarded(function()
  hl.timer(guarded(sync_active_pointer_guard), { timeout = 1, type = "oneshot" })
end))

hl.on("window.destroy", guarded(function(window)
  show_full({ window = window })
end))

-- A thumbnail moved to a non-stage workspace becomes a normal window again.
-- After a config reload, bring tags in line with the current slots.
hl.timer(guarded(function()
  local ws = hl.get_active_workspace()
  if is_stage(ws) then
    if stage_focused() then
      hl.dispatch(hl.dsp.layout("refresh"))
    end
    update_thumbs(ws)
    -- A reload mid-flash would strand the swap highlight.
    for _, w in ipairs(tiled_windows(ws)) do
      if has_tag(w, "stage-swap") then
        tag_window(w, "stage-swap", false)
      end
    end
  elseif is_duo(ws) then
    hl.dispatch(hl.dsp.layout("refresh"))
    sync_active_pointer_guard()
  elseif ws then
    sync_active_pointer_guard()
  end
end), { timeout = 200, type = "oneshot" })

hl.on("window.move_to_workspace", guarded(function(window)
  if window and not is_stage(window.workspace) then
    set_thumb(window, false)
    if not is_duo(window.workspace) then set_no_follow_mouse(window, false) end
    show_full({ window = window })
  end
end))


local M = {}

function M.clear_pointer_guard(workspace_id)
  for _, window in ipairs(hl.get_workspace_windows(tostring(workspace_id))) do
    if window.mapped then
      set_thumb(window, false)
      set_no_follow_mouse(window, false)
    end
  end
end

M.sync_pointer_guard = sync_active_pointer_guard

-- The panel wrote settings.conf: read it, swap the window rules and lay out again.
function M.reload_settings()
  read_settings()
  apply_rules()
  sync_tile_tags()
  if tableau_focused() then hl.dispatch(hl.dsp.layout("refresh")) end
end

-- Swap the focused thumbnail into the middle.
function M.promote()
  local w = hl.get_active_window()
  local ws = tableau_focused()
  if w and ws and w.stable_id then
    swap_and_flash(ws, slots_for(ws.id), w.stable_id)
    relayout_soon()
  end
end

-- Hyprland's directional focus misses windows whose edges do not touch. Tableau
-- layouts use explicit window positions and slot order for keyboard focus.
local DIRECTIONS = {
  l = { x = -1, y = 0 },
  r = { x = 1, y = 0 },
  u = { x = 0, y = -1 },
  d = { x = 0, y = 1 },
}

local function centre(w)
  return w.at.x + w.size.x / 2, w.at.y + w.size.y / 2
end

function M.focus(dir)
  return function()
    local ws = tableau_focused()
    if not ws then
      hl.dispatch(hl.dsp.focus({ direction = dir }))
      return
    end

    local current = hl.get_active_window()
    local cx, cy = centre(current)
    local v = DIRECTIONS[dir]
    local best, best_score

    for _, w in ipairs(tiled_windows(ws)) do
      if w.stable_id ~= current.stable_id then
        local x, y = centre(w)
        local along = (x - cx) * v.x + (y - cy) * v.y
        local across = math.abs((x - cx) * v.y + (y - cy) * v.x)
        -- Only windows within ~60 degrees of straight ahead; favour the closest.
        if along > 1 and across <= 2 * along then
          local score = along + 2 * across
          if not best_score or score < best_score then
            best, best_score = w, score
          end
        end
      end
    end

    if best then
      navigating = true
      hl.dispatch(hl.dsp.focus({ window = best }))
      navigating = false
    end
  end
end

-- Shift+Super+arrows swaps the focused window with the nearest window in that direction.
function M.move(dir)
  return function()
    local ws = tableau_focused()
    if not ws then
      hl.dispatch(hl.dsp.window.swap({ direction = dir }))
      return
    end

    local current = hl.get_active_window()
    if not current or not current.stable_id then return end

    local list = slots_for(ws.id)
    local windows = tiled_windows(ws)
    sync(list, windows, current.stable_id)

    if is_balance(ws) then
      local from = index_of(list, current.stable_id)
      local count = #list
      local cols = balance_columns[ws.id] or count
      local to
      if dir == "l" then
        if from and (from - 1) % cols ~= 0 then to = from - 1 end
      elseif dir == "r" then
        if from and from < count and from % cols ~= 0 then to = from + 1 end
      elseif dir == "u" then
        if from and from > cols then to = from - cols end
      elseif from then
        -- down: the tile below, or the last one when the row below is short
        local row_end = math.ceil(from / cols) * cols
        if from + cols <= count then to = from + cols
        elseif count > row_end then to = count end
      end
      if to then
        list[from], list[to] = list[to], list[from]
        flash(ws, { current.stable_id, list[from] })
        relayout_soon()
      end
      return
    end

    local cx, cy = centre(current)
    local v = DIRECTIONS[dir]
    local best, best_score
    for _, w in ipairs(tiled_windows(ws)) do
      if w.stable_id ~= current.stable_id then
        local x, y = centre(w)
        local along = (x - cx) * v.x + (y - cy) * v.y
        local across = math.abs((x - cx) * v.y + (y - cy) * v.x)
        if along > 1 and across <= 2 * along then
          local score = along + 2 * across
          if not best_score or score < best_score then
            best, best_score = w, score
          end
        end
      end
    end
    if not best then return end

    local from, to = index_of(list, current.stable_id), index_of(list, best.stable_id)
    if from and to then
      list[from], list[to] = list[to], list[from]
      flash(ws, { current.stable_id, best.stable_id })
      relayout_soon()
    end
  end
end

-- Alt+Tab on a stage workspace is a switcher: while ALT is held, each TAB
-- moves the highlight (keyboard focus, which gives the thumbnail its border)
-- to the next thumbnail in screen order: the whole left side first (inner
-- column top to bottom, then the outer ones), then the right side the same
-- way. SHIFT goes backwards.
-- Releasing ALT opens the highlighted window into the middle (one swap).
-- A release bind can't see that (the TAB presses in between cancel it), so
-- the stagethumbs plugin watches for the ALT release and calls tab_commit.
-- Without the plugin, the window opens shortly after the last TAB instead.
-- Elsewhere, Omarchy's own Alt+Tab.
local switching = nil -- { ws = workspace id, p = position in the order } while ALT is held
local switch_gen = 0 -- for the no-plugin fallback timer

-- Slot indices in switcher order. Slots alternate sides (2 left, 3 right,
-- 4 left, ...) and each side fills its inner column first.
local function switch_order(n)
  local order = {}
  for start = 2, 3 do
    for k = start, n, 2 do
      order[#order + 1] = k
    end
  end
  return order
end

function M.tab(step)
  return function()
    local ws = tableau_focused()
    if not ws then
      hl.dispatch(hl.dsp.window.cycle_next({ next = step > 0 }))
      hl.dispatch(hl.dsp.window.bring_to_top())
      return
    end

    local list = slots_for(ws.id)
    local windows = tiled_windows(ws)
    local active = hl.get_active_window()
    sync(list, windows, active and active.stable_id)
    local n = #list
    if n < 2 then
      return
    end

    local order
    if is_balance(ws) or is_duo(ws) or ws.tiled_layout == "lua:tableau-strip"
      or ws.tiled_layout == "lua:tableau-column" or ws.tiled_layout == "lua:tableau-spiral"
      or ws.tiled_layout == GALLERY_LAYOUT or ws.tiled_layout == GALLERY_RIGHT_LAYOUT
      or ws.tiled_layout == GALLERY_LEFT_LAYOUT or ws.tiled_layout == GALLERY_TOP_LAYOUT then
      order = {}
      for k = 1, n do order[#order + 1] = k end
    else
      order = switch_order(n)
    end
    if not switching or switching.ws ~= ws.id then
      switching = { ws = ws.id, p = step > 0 and 0 or #order + 1 }
    end
    local p = switching.p + step
    if p > #order then
      p = 1
    elseif p < 1 then
      p = #order
    end
    switching.p = p
    local k = order[p]

    for _, w in ipairs(windows) do
      if w.stable_id == list[k] then
        navigating = true
        hl.dispatch(hl.dsp.focus({ window = w }))
        navigating = false
        break
      end
    end

    local plugin = thumbs()
    if plugin and plugin.watch_alt then
      plugin.watch_alt()
    else
      switch_gen = switch_gen + 1
      local gen = switch_gen
      hl.timer(guarded(function()
        if gen == switch_gen then
          M.tab_commit()
        end
      end), { timeout = 800, type = "oneshot" })
    end
  end
end

-- ALT released: open the highlighted thumbnail.
function M.tab_commit()
  local sw = switching
  switching = nil
  local ws = sw and tableau_focused()
  if not ws or ws.id ~= sw.ws then
    return
  end
  local w = hl.get_active_window()
  local list = slots_for(ws.id)
  if w and w.stable_id and list[1] ~= w.stable_id then
    swap_and_flash(ws, list, w.stable_id)
    relayout_soon()
  end
end

-- Omarchy's horizontal resize keys, which expand (minus, dx < 0) or shrink (equal) a
-- window. On a Tableau layout they do that to the main window, or to the focused tile
-- in Mosaic, Spread, Strip, Column and Spiral; elsewhere they resize as usual.
-- The resize keys repeat while held. `grow` is 1 for Omarchy's expand key (minus) and
-- -1 for shrink (equal); `scale` makes a step smaller (Alt) or larger (Ctrl). On a
-- Tableau layout each step is cfg.step of the screen, so holding a key grows or shrinks
-- the main window smoothly. Anywhere else the key resizes as Omarchy's does, `px` per
-- press, and a held key doesn't repeat.
local resize_held = false
local resize_generation = 0
local function note_resize_key()
  local was = resize_held
  resize_held = true
  resize_generation = resize_generation + 1
  local mine = resize_generation
  -- repeats come every 40 ms or so; a gap longer than this is a new press
  hl.timer(function() if resize_generation == mine then resize_held = false end end,
    { timeout = 150, type = "oneshot" })
  return was
end

function M.resize(grow, scale, px)
  return function()
    local repeated = note_resize_key()
    local amount = grow * cfg.step * scale
    local active = hl.get_active_window()
    local balance_ws = active and active.workspace
    if balance_ws and is_duo(balance_ws) and active.stable_id then
      local triptych = balance_ws.tiled_layout == "lua:tableau-triptych"
      local share = duo_shares[balance_ws.id] or (triptych and cfg.middle or cfg.pane)
      duo_shares[balance_ws.id] = math.max(0.30, math.min(0.82, share + amount))
      hl.dispatch(hl.dsp.layout("refresh"))
      return
    end
    if balance_ws and is_balance(balance_ws) and active.stable_id then
      local weights = balance_weights[balance_ws.id] or {}
      balance_weights[balance_ws.id] = weights
      weights[active.stable_id] = resize_weight(weights, active.stable_id, amount)
      hl.dispatch(hl.dsp.layout("refresh"))
      return
    end
    if balance_ws and active.stable_id then
      local layout = balance_ws.tiled_layout
      local store = (layout == "lua:tableau-strip" or layout == "lua:tableau-column") and linear_weights
        or layout == "lua:tableau-spiral" and spiral_weights
      if store then
        local weights = store[balance_ws.id] or {}
        store[balance_ws.id] = weights
        weights[active.stable_id] = resize_weight(weights, active.stable_id, amount)
        hl.dispatch(hl.dsp.layout("refresh"))
        return
      end
    end
    local ws = stage_focused()
    if not ws then
      if not repeated then hl.dispatch(hl.dsp.window.resize({ x = -grow * px, y = 0, relative = true })) end
      return
    end

    local mon = ws.monitor
    local rotated = ws.tiled_layout == HORIZON_LAYOUT or ws.tiled_layout == GALLERY_LAYOUT
      or ws.tiled_layout == GALLERY_TOP_LAYOUT
    local width = rotated and (mon and (mon.height / mon.scale) or 1080) or (mon and (mon.width / mon.scale) or 1920)
    local height = rotated and (mon and (mon.width / mon.scale) or 1920) or (mon and (mon.height / mon.scale) or 1080)
    local share
    if ws.tiled_layout == HORIZON_LAYOUT then
      share = math.min(0.76, math.max(cfg.center_min, (height / width) / 2.1))
    else
      share = center_share({ w = width, h = height }, ws.id, false)
    end
    local adjust = (center_adjust[ws.id] or 0) + amount
    -- clamp so a held key past a limit doesn't pile up
    adjust = math.min(cfg.center_step_max - share, math.max(cfg.center_step_min - share, adjust))
    center_adjust[ws.id] = adjust
    save_center()
    hl.dispatch(hl.dsp.layout("refresh"))
  end
end

-- Called by the thumbnail helper when the pointer moves onto a thumbnail
-- (its address) or off all of them (""). Hyprland has no hover event for Lua.
-- Every window on the workspace is brought in line, so a highlight left over
-- from before a config reload is cleared too.
function M.hover(address)
  local ws = hl.get_active_workspace()
  if not is_stage(ws) then
    return
  end
  for _, w in ipairs(tiled_windows(ws)) do
    local want = address ~= "" and w.address == address and has_thumb_tag(w)
    if has_tag(w, "stage-hover") ~= want then
      tag_window(w, "stage-hover", want)
    end
  end
end

o.bind("SUPER + Z", "Tableau: promote focused window", guarded(M.promote))

for _, k in ipairs({
  { "SUPER", 1, 100, "" },
  { "SUPER + ALT", 0.25, 25, " a little" },
  { "SUPER + CTRL", 4, 300, " a lot" },
}) do
  hl.unbind(k[1] .. " + code:20")
  hl.unbind(k[1] .. " + code:21")
  o.bind(k[1] .. " + code:20", "Expand window" .. k[4] .. " (Tableau: the main window, hold to keep going)",
    guarded(M.resize(1, k[2], k[3])), { repeating = true })
  o.bind(k[1] .. " + code:21", "Shrink window" .. k[4] .. " (Tableau: the main window, hold to keep going)",
    guarded(M.resize(-1, k[2], k[3])), { repeating = true })
end

hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "Focus on next window", guarded(M.tab(1)))
o.bind("ALT + SHIFT + TAB", "Focus on previous window", guarded(M.tab(-1)))

for key, dir in pairs({ LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d" }) do
  local name = ({ l = "left", r = "right", u = "above", d = "below" })[dir]
  hl.unbind("SUPER + " .. key)
  o.bind("SUPER + " .. key, "Focus on " .. name .. " window", guarded(M.focus(dir)))
  hl.unbind("SUPER + SHIFT + " .. key)
  o.bind("SUPER + SHIFT + " .. key, "Move Tableau window " .. name, guarded(M.move(dir)))
end

_G.omarchy_tableau = M
return M
