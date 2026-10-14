-- Five linked desks: Super+N shows workspace N on the main monitor and 10+N on the portrait monitor.
-- Super+Shift+N moves the focused window to desk N on the monitor it's on.
-- Ctrl+Super+Left/Right steps to the previous/next desk, like Windows; with Shift the window comes along. Every session starts on desk 1.
local M = { COUNT = 5 }
local MAIN = "desc:HP Inc. HP X27i"
local PORTRAIT = "desc:HP Inc. HP E27q G5"
local PORTRAIT_MODEL = "HP E27q G5"

-- Workspaces to focus for desk n, in order; the last one keeps the focus.
function M.focus_order(n, portrait_connected)
  if portrait_connected then return { 10 + n, n } end
  return { n }
end

-- Desk a workspace belongs to: main 1-5, portrait 11-15.
function M.desk_of(ws_id)
  if ws_id > 10 then return ws_id - 10 end
  return ws_id
end

-- Ctrl+Super+Left/Right: the neighbouring desk, stopping at the first and last like Windows.
function M.step(ws_id, delta)
  return math.max(1, math.min(M.COUNT, M.desk_of(ws_id) + delta))
end

-- Portrait desks are workspaces 11-15.
function M.move_target(active_ws_id, n)
  if active_ws_id > 10 then return 10 + n end
  return n
end

-- After undocking, windows on 11-15 move to 1-5 so nothing is stranded.
function M.strays(windows)
  local out = {}
  for _, w in ipairs(windows) do
    local id = w.workspace and w.workspace.id
    if id and id >= 11 and id <= 10 + M.COUNT then table.insert(out, { address = w.address, workspace = id - 10 }) end
  end
  return out
end

local function portrait_connected()
  for _, m in ipairs(hl.get_monitors()) do
    if m.description and m.description:find(PORTRAIT_MODEL, 1, true) then return true end
  end
  return false
end

local function focus_desk(n)
  for _, ws in ipairs(M.focus_order(n, portrait_connected())) do
    hl.dispatch(hl.dsp.focus({ workspace = tostring(ws) }))
  end
end

local function active_ws_id()
  local ws = hl.get_active_workspace()
  return ws and ws.id or 1
end

for n = 1, M.COUNT do
  hl.workspace_rule({ workspace = tostring(n), monitor = MAIN, default = (n == 1) })
  hl.workspace_rule({ workspace = tostring(10 + n), monitor = PORTRAIT, default = (n == 1), layout_opts = { orientation = "top" } })
  local key = "code:" .. (9 + n) -- digit keys by keycode (1 = code:10), works on QWERTZ and AZERTY
  hl.bind("SUPER + " .. key, function() focus_desk(n) end)
  hl.bind("SUPER + SHIFT + " .. key, function()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(M.move_target(active_ws_id(), n)), follow = false }))
  end)
end
hl.bind("CONTROL + SUPER + Left", function() focus_desk(M.step(active_ws_id(), -1)) end)
hl.bind("CONTROL + SUPER + Right", function() focus_desk(M.step(active_ws_id(), 1)) end)
for key, delta in pairs({ Left = -1, Right = 1 }) do
  hl.bind("CONTROL + SUPER + SHIFT + " .. key, function()
    local id = active_ws_id()
    local n = M.step(id, delta)
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(M.move_target(id, n)), follow = false }))
    focus_desk(n)
  end)
end

-- Desks 1-5 belong to the main monitor, so without it Hyprland would open the laptop panel on workspace 6.
-- Start on desk 1 instead; the first apps then open there too.
hl.on("hyprland.start", function() focus_desk(1) end)

-- Decided by the removed monitor itself, in case Hyprland still lists it when the event fires.
hl.on("monitor.removed", function(m)
  if not (m and m.description and m.description:find(PORTRAIT_MODEL, 1, true)) then return end
  for _, s in ipairs(M.strays(hl.get_windows())) do
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. s.address, workspace = tostring(s.workspace), follow = false }))
  end
end)

return M
