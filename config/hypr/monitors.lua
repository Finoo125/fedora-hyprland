-- Dock layout: HP E27q G5 portrait on the left, HP X27i on the right (top-aligned, like on Windows).
-- Monitors are matched by model, so port names (which differ per laptop and dock) don't matter.
local M = {}

hl.monitor({ output = "desc:HP Inc. HP E27q G5", mode = "preferred", position = "0x0", scale = 1, transform = 3 }) -- upside down? use 1
hl.monitor({ output = "desc:HP Inc. HP X27i", mode = "highrr", position = "1440x0", scale = 1 }) -- 144 Hz if the dock allows
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 }) -- anything else

-- panel_scale(WIDTH, HEIGHT, PHYSICAL_WIDTH_MM) -> scale for the laptop panel from its pixel density: 1 up to ~160 PPI
-- (15.6" 1080p), 1.5 up to ~230 PPI (Framework 13 2.2K), else 2 (2.8K/3K). Snapped to the nearest multiple of 1/120
-- that divides both sides, since Hyprland rejects others (2256x1504 -> 1.566667, i.e. 1440x960).
function M.panel_scale(width, height, physical_width)
  if not (width and height and physical_width) or width <= 0 or height <= 0 or physical_width <= 0 then return 1 end
  local ppi = width / (physical_width / 25.4)
  local target = ppi < 160 and 1 or ppi < 230 and 1.5 or 2
  local base = math.floor(target * 120 + 0.5)
  for d = 0, 30 do
    for _, n in ipairs({ base - d, base + d }) do
      if (width * 120) % n == 0 and (height * 120) % n == 0 then return n / 120 end
    end
  end
  return target
end

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

-- A disabled panel may report no size, so the scale is remembered from when it was last on.
local panel_scales = {}

function M.apply(removed)
  local on = M.internal_enabled(hl.get_monitors(), removed and removed.name)
  for _, m in ipairs(hl.get_monitors({ all = true })) do
    if m.name:match("^eDP") then
      if (m.width or 0) > 0 then panel_scales[m.name] = M.panel_scale(m.width, m.height, m.physical_width) end
      if on then
        hl.monitor({ output = m.name, disabled = false, mode = "preferred", position = "auto", scale = panel_scales[m.name] or 1 })
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
