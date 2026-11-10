-- Tableau's layouts are Omarchy workspace modes, next to Dwindle, Scrolling and
-- Floating: chosen per workspace, saved by Omarchy and restored at login.
local hl = _G.hl
local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local modes_dir = state_home .. "/omarchy/workspace-layouts"
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_dir = source:match("^(.*)/") or "."

local function choose(layout)
  hl.exec_cmd("python3 " .. o.shell_quote(plugin_dir .. "/cycle_layout.py") .. " " .. o.shell_quote(layout))
end

local function saved_mode(path)
  if not path then return nil end
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  return contents:match('mode%s*=%s*"([^"]+)"')
end

local function cycle()
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.special then return end
  choose("next")
end

local function cycle_back()
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.special then return end
  choose("back")
end

local function open_layout_picker()
  hl.dispatch(hl.dsp.submap("tableau-layout-picker"))
end

-- Workspace Layout loads after Omarchy's saved modes and can replace their
-- workspace rules. Replay every saved mode after Tableau has registered its Lua
-- layouts so the persisted Omarchy mode remains the final rule.
do
  local pipe = io.popen("find " .. o.shell_quote(modes_dir) .. " -maxdepth 1 -type f -name '*.lua' -print 2>/dev/null")
  if pipe then
    for path in pipe:lines() do
      local mode = saved_mode(path)
      if mode then
        local file = io.open(path, "r")
        local contents = file and file:read("*a") or ""
        if file then file:close() end
        local workspace = contents:match('workspace%s*=%s*"([^"]+)"')
        if workspace then pcall(o.workspace_mode, { workspace = workspace, mode = mode }) end
      end
    end
    pipe:close()
  end
end

-- Workspace Layout can reapply its profile rule when a workspace returns. Keep
-- an explicitly chosen Tableau layout authoritative for that workspace by
-- replaying Omarchy's saved mode after the workspace activation settles.
local function restore_active_tableau_mode()
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.special or not workspace.id then return end
  local workspace_id = tostring(workspace.id)
  local mode = saved_mode(modes_dir .. "/" .. workspace_id .. ".lua")
  -- Omarchy's Workspace Layout profile can reapply its rule after the
  -- workspace-mode file has been applied. Replay every persisted choice here,
  -- including native layouts such as dwindle and scrolling.
  if not mode then return end
  pcall(o.workspace_mode, { workspace = workspace_id, mode = mode })
  pcall(hl.exec_scheduled_prop_refresh_immediately)
  local tableau = _G.omarchy_tableau
  if tableau and tableau.sync_pointer_guard then pcall(tableau.sync_pointer_guard) end
end

local function schedule_restore()
  -- Profile rules may settle after workspace activation. A few delayed
  -- replays keep the persisted mode authoritative through that update.
  for _, timeout in ipairs({ 500, 1500, 3000 }) do
    hl.timer(restore_active_tableau_mode, { type = "oneshot", timeout = timeout })
  end
end

if not _G.tableau_workspace_restore_subscription then
  _G.tableau_workspace_restore_subscription = hl.on("workspace.active", schedule_restore)
end
schedule_restore()

hl.unbind("SUPER + L")
hl.unbind("SUPER + SHIFT + L")
hl.unbind("SUPER + CTRL + L")
o.bind("SUPER + L", "Cycle workspace layout (Tableau)", cycle)
o.bind("SUPER + SHIFT + L", "Cycle workspace layout back (Tableau)", cycle_back)
hl.bind("SUPER + CTRL + L", open_layout_picker)
hl.define_submap("tableau-layout-picker", function()
  for _, item in ipairs({
    { "1", "dwindle" }, { "2", "scrolling" }, { "3", "floating" },
    { "4", "lua:tableau-portrait" }, { "5", "lua:tableau-landscape" },
    { "6", "lua:tableau-centerpiece" }, { "7", "lua:tableau-diptych-left" },
    { "8", "lua:tableau-diptych-right" }, { "9", "lua:tableau-mosaic" },
  }) do
    local selected = item[2]
    hl.bind(item[1], function()
      hl.dispatch(hl.dsp.submap("reset"))
      choose(selected)
    end)
  end
  hl.bind("0", function() hl.dispatch(hl.dsp.submap("tableau-layout-picker-more")) end)
  hl.bind("Escape", hl.dsp.submap("reset"))
end)

hl.define_submap("tableau-layout-picker-more", function()
  for _, item in ipairs({
    { "1", "lua:tableau-strip" }, { "2", "lua:tableau-column" },
    { "3", "lua:tableau-spiral" }, { "4", "lua:tableau-gallery-right" },
    { "5", "lua:tableau-gallery-bottom" }, { "6", "lua:tableau-gallery-left" },
    { "7", "lua:tableau-gallery-top" }, { "8", "lua:tableau-spread" },
    { "9", "lua:tableau-diptych-top" }, { "0", "lua:tableau-diptych-bottom" },
    { "minus", "lua:tableau-triptych" }, { "equal", "lua:tableau-bento" },
  }) do
    local selected = item[2]
    hl.bind(item[1], function()
      hl.dispatch(hl.dsp.submap("reset"))
      choose(selected)
    end)
  end
  hl.bind("Escape", hl.dsp.submap("reset"))
end)
