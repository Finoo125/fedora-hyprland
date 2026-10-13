-- Dock layout: HP E27q G5 portrait on the left, HP X27i on the right (top-aligned, like on Windows).
-- Monitors are matched by model, so port names (which differ per laptop and dock) don't matter.
local M = {}

hl.monitor({ output = "desc:HP Inc. HP E27q G5", mode = "preferred", position = "0x0", scale = 1, transform = 3 }) -- upside down? use 1
hl.monitor({ output = "desc:HP Inc. HP X27i", mode = "highrr", position = "1440x0", scale = 1 }) -- 144 Hz if the dock allows
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" }) -- anything else

-- FALLBACK/HEADLESS are outputs Hyprland creates itself when nothing is connected.
function M.is_external(name)
  return not (name:match("^eDP") or name:match("^FALLBACK") or name:match("^HEADLESS"))
end

-- The laptop panel is on only while no external monitor is connected.
function M.internal_enabled(monitors)
  for _, m in ipairs(monitors) do
    if M.is_external(m.name) then return false end
  end
  return true
end

function M.apply()
  local on = M.internal_enabled(hl.get_monitors())
  for _, m in ipairs(hl.get_monitors({ all = true })) do
    if m.name:match("^eDP") then
      if on then
        hl.monitor({ output = m.name, mode = "preferred", position = "auto", scale = "auto" })
      else
        hl.monitor({ output = m.name, disabled = true })
      end
    end
  end
end

-- Event driven: runs the moment a monitor is plugged in or out.
hl.on("hyprland.start", M.apply)
hl.on("monitor.added", M.apply)
hl.on("monitor.removed", M.apply)

return M
