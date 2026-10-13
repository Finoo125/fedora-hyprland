-- Four linked desks: Super+N shows workspace N on the main monitor and 10+N on the portrait monitor.
-- Super+Shift+N moves the focused window to desk N on the monitor it's on.
local M = {}
local MAIN = "desc:HP Inc. HP X27i"
local PORTRAIT = "desc:HP Inc. HP E27q G5"
local PORTRAIT_MODEL = "HP E27q G5"

-- Workspaces to focus for desk n, in order; the last one keeps the focus.
function M.focus_order(n, portrait_connected)
  if portrait_connected then return { 10 + n, n } end
  return { n }
end

-- Portrait desks are workspaces 11-14.
function M.move_target(active_ws_id, n)
  if active_ws_id > 10 then return 10 + n end
  return n
end

-- After undocking, windows on 11-14 move to 1-4 so nothing is stranded.
function M.strays(windows)
  local out = {}
  for _, w in ipairs(windows) do
    local id = w.workspace and w.workspace.id
    if id and id >= 11 and id <= 14 then table.insert(out, { address = w.address, workspace = id - 10 }) end
  end
  return out
end

local function portrait_connected()
  for _, m in ipairs(hl.get_monitors()) do
    if m.description and m.description:find(PORTRAIT_MODEL, 1, true) then return true end
  end
  return false
end

for n = 1, 4 do
  hl.workspace_rule({ workspace = tostring(n), monitor = MAIN, default = (n == 1) })
  hl.workspace_rule({ workspace = tostring(10 + n), monitor = PORTRAIT, default = (n == 1), layout_opts = { orientation = "top" } })
  local key = "code:" .. (9 + n) -- digit keys by keycode (1 = code:10), works on QWERTZ and AZERTY
  hl.bind("SUPER + " .. key, function()
    for _, ws in ipairs(M.focus_order(n, portrait_connected())) do
      hl.dispatch(hl.dsp.focus({ workspace = tostring(ws) }))
    end
  end)
  hl.bind("SUPER + SHIFT + " .. key, function()
    local ws = hl.get_active_workspace()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(M.move_target(ws and ws.id or 1, n)), follow = false }))
  end)
end

-- Decided by the removed monitor itself, in case Hyprland still lists it when the event fires.
hl.on("monitor.removed", function(m)
  if not (m and m.description and m.description:find(PORTRAIT_MODEL, 1, true)) then return end
  for _, s in ipairs(M.strays(hl.get_windows())) do
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. s.address, workspace = tostring(s.workspace), follow = false }))
  end
end)

return M
