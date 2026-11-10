-- A stand-in for Hyprland's Lua API, just enough to load Tableau and run its layouts
-- outside Hyprland. Records what Tableau asks Hyprland to do.
local mock = { layouts = {}, rules = {}, dispatched = {}, binds = {}, bind_opts = {}, handlers = {}, timers = {}, execs = {} }
local windows, workspaces, active = {}, {}, nil

local function dsp(kind)
  return setmetatable({}, { __index = function(_, name)
    return function(args) return { kind = kind .. "." .. name, args = args } end
  end })
end

_G.hl = {
  dsp = setmetatable({
    window = dsp("window"),
    layout = function(msg) return { kind = "layout", args = msg } end,
    focus = function(args) return { kind = "focus", args = args } end,
    submap = function(name) return { kind = "submap", args = name } end,
  }, { __index = function(_, k) return function(args) return { kind = k, args = args } end end }),
  layout = { register = function(name, def)
    if mock.layouts[name] then error("layout " .. name .. " already registered") end
    mock.layouts[name] = def
  end },
  plugin = {},
  dispatch = function(d) mock.dispatched[#mock.dispatched + 1] = d
    if d.kind == "window.tag" then
      local target = d.args.window
      local w = type(target) == "table" and target or nil
      if type(target) == "string" then
        for _, cand in ipairs(windows) do if "address:" .. cand.address == target then w = cand end end
      end
      if w then
        local sign, tag = d.args.tag:sub(1, 1), d.args.tag:sub(2)
        local keep = {}
        for _, t in ipairs(w.tags) do if t ~= tag then keep[#keep + 1] = t end end
        if sign == "+" then keep[#keep + 1] = tag end
        w.tags = keep
      end
    end
  end,
  window_rule = function(r) mock.rules[#mock.rules + 1] = r; return r end,
  on = function(name, fn) mock.handlers[name] = mock.handlers[name] or {}; table.insert(mock.handlers[name], fn); return fn end,
  timer = function(fn, opts) mock.timers[#mock.timers + 1] = { fn = fn, opts = opts } end,
  bind = function(keys, fn) mock.binds[keys] = fn end,
  unbind = function(keys) mock.binds[keys] = nil end,
  define_submap = function(name, fn) fn() end,
  exec_cmd = function(cmd) mock.execs[#mock.execs + 1] = cmd end,
  get_config = function(key)
    if key == "general.col.active_border" then return { colors = { "0xee33ccff", "0xee00ff99" }, angle = 45 } end
    if key == "general.col.inactive_border" then return { colors = { "0xaa595959" }, angle = 0 } end
  end,
  get_active_window = function() return active end,
  get_active_workspace = function() return workspaces[1] end,
  get_workspace_windows = function(sel)
    local out = {}
    for _, w in ipairs(windows) do if tostring(w.workspace.id) == tostring(sel) then out[#out + 1] = w end end
    return out
  end,
  get_windows = function() return windows end,
  get_workspaces = function() return workspaces end,
  exec_scheduled_prop_refresh_immediately = function() end,
}

_G.o = {
  shell_quote = function(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end,
  bind = function(keys, _, fn, opts) mock.binds[keys] = fn; mock.bind_opts[keys] = opts end,
  window = function(match, rules) rules.match = match; mock.rules[#mock.rules + 1] = rules end,
  workspace_mode = function(spec) mock.modes = mock.modes or {}; mock.modes[spec.workspace] = spec.mode end,
}

-- a workspace with `n` tiled windows on the given layout
function mock.workspace(id, layout, n, monitor)
  local ws = { id = id, name = tostring(id), special = false, tiled_layout = layout,
               monitor = monitor or { width = 1920, height = 1080, scale = 1 } }
  workspaces = { ws }
  windows = {}
  for i = 1, n do
    windows[i] = { stable_id = 100 + i, address = string.format("%x", 0xa0 + i), workspace = ws, mapped = true,
                   floating = false, tags = {}, class = "app" .. i, at = { x = 0, y = 0 }, size = { x = 10, y = 10 } }
  end
  active = windows[1]
  return ws, windows
end
function mock.set_active(w) active = w end
function mock.windows() return windows end

-- run a layout over the windows; returns the boxes by stable id
function mock.run(name, area)
  local placed, targets = {}, {}
  for _, w in ipairs(windows) do
    targets[#targets + 1] = { window = w, place = function(self, box)
      placed[self.window.stable_id] = { x = box.x, y = box.y, w = box.w, h = box.h }
      self.window.at = { x = box.x, y = box.y }; self.window.size = { x = box.w, y = box.h }
    end }
  end
  mock.layouts[name].recalculate({ area = area, targets = targets })
  return placed
end

function mock.fire(event, ...)
  for _, fn in ipairs(mock.handlers[event] or {}) do fn(...) end
end
function mock.run_timers()
  for _ = 1, 20 do
    local pending = mock.timers
    if #pending == 0 then return end
    mock.timers = {}
    for _, t in ipairs(pending) do t.fn() end
  end
end

return mock
