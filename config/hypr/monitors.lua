-- Dock layout: HP E27q G5 portrait on the left, HP X27i on the right (top-aligned, like on Windows).
-- Monitors are matched by model, so port names (which differ per laptop and dock) don't matter.
local M = {}

hl.monitor({ output = "desc:HP Inc. HP E27q G5", mode = "preferred", position = "0x0", scale = 1, transform = 3 }) -- upside down? use 1
hl.monitor({ output = "desc:HP Inc. HP X27i", mode = "highrr", position = "1440x0", scale = 1 }) -- 144 Hz if the dock allows
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 }) -- anything else

-- FALLBACK/HEADLESS are outputs Hyprland creates itself when nothing is connected.
function M.is_external(name)
  return not (name:match("^eDP") or name:match("^FALLBACK") or name:match("^HEADLESS"))
end

-- The laptop panel is on only while no external monitor is connected. `gone` is a monitor being removed,
-- ignored in case Hyprland still lists it when the event fires.
function M.internal_enabled(monitors, gone)
  for _, m in ipairs(monitors) do
    if M.is_external(m.name) and m.name ~= gone then return false end
  end
  return true
end

function M.apply(removed)
  local on = M.internal_enabled(hl.get_monitors(), removed and removed.name)
  for _, m in ipairs(hl.get_monitors({ all = true })) do
    if m.name:match("^eDP") then
      if on then
        hl.monitor({ output = m.name, disabled = false, mode = "preferred", position = "auto", scale = 1 })
      else
        hl.monitor({ output = m.name, disabled = true })
      end
    end
  end
end

-- Event driven: runs the moment a monitor is plugged in or out.
hl.on("hyprland.start", function() M.apply() end)
hl.on("monitor.added", function() M.apply() end)
hl.on("monitor.removed", function(m) M.apply(m) end)

return M
