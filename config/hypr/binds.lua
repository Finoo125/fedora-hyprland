-- Keybinds: the CachyOS cachyos-hypr-noctalia set, written fresh. Desk keys (Super+1..4) are in desks.lua.
local mod = "SUPER"
local PORTRAIT = "desc:HP Inc. HP E27q G5"
local MAIN = "desc:HP Inc. HP X27i"
local function run(cmd) return hl.dsp.exec_cmd("uwsm app -- " .. cmd) end
local function noctalia(cmd) return hl.dsp.exec_cmd("noctalia msg " .. cmd) end

-- Windows
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + D", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + J", hl.dsp.layout("swapwithmaster"))
for key, dir in pairs({ Left = "left", Right = "right", Up = "up", Down = "down" }) do
  hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }))
end
for key, dir in pairs({ Left = "l", Right = "r", Up = "u", Down = "d" }) do
  hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind(mod .. " + Tab", noctalia("window-switcher"))
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize())
hl.bind(mod .. " + ALT + code:10", hl.dsp.focus({ monitor = PORTRAIT }))
hl.bind(mod .. " + ALT + code:11", hl.dsp.focus({ monitor = MAIN }))
hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special("scratchpad"))

local function zoom(delta)
  local z = hl.get_config("cursor.zoom_factor") + delta
  hl.config({ cursor = { zoom_factor = math.max(1.0, math.min(3.0, z)) } })
end
hl.bind(mod .. " + Minus", function() zoom(-0.3) end, { repeating = true })
hl.bind(mod .. " + Plus", function() zoom(0.3) end, { repeating = true })

-- Apps
-- Ghostty runs as a background service (D-Bus activated), so new windows open instantly instead of in ~1 s.
hl.bind(mod .. " + Return", hl.dsp.exec_cmd("ghostty +new-window"))
hl.bind(mod .. " + E", run("dolphin"))
hl.bind(mod .. " + W", run("firefox"))
hl.bind(mod .. " + T", run("kate --new"))
hl.bind(mod .. " + C", run("kcalc"))
hl.bind("XF86Calculator", run("kcalc"))
hl.bind("CONTROL + SHIFT + Escape", hl.dsp.exec_cmd("ghostty +new-window -e btop"))

-- Noctalia
hl.bind(mod .. " + Space", noctalia("panel-toggle launcher"))
hl.bind(mod .. " + period", noctalia("panel-toggle launcher /emo"))
hl.bind(mod .. " + X", noctalia("panel-toggle control-center"))
hl.bind(mod .. " + Z", noctalia("settings-toggle"))
hl.bind(mod .. " + A", noctalia("panel-toggle control-center notifications"))
hl.bind(mod .. " + V", noctalia("panel-toggle clipboard"))
hl.bind(mod .. " + L", noctalia("session lock"))
hl.bind(mod .. " + ALT + C", noctalia("panel-toggle session"))
hl.bind(mod .. " + SHIFT + W", noctalia("panel-toggle wallpaper"))
hl.bind(mod .. " + P", hl.dsp.exec_cmd("hyprpicker -a -n"))
hl.bind("Print", noctalia("screenshot-region"))
hl.bind(mod .. " + Print", noctalia("screenshot-fullscreen"))
hl.bind(mod .. " + SHIFT + S", noctalia("plugin noctalia/screen_recorder:service all toggle"))

-- Hardware keys (also work on the lock screen)
local held, locked = { locked = true, repeating = true }, { locked = true }
hl.bind("XF86AudioRaiseVolume", noctalia("volume-up"), held)
hl.bind("XF86AudioLowerVolume", noctalia("volume-down"), held)
hl.bind("XF86AudioMute", noctalia("volume-mute"), locked)
hl.bind("XF86AudioMicMute", noctalia("mic-mute"), locked)
hl.bind("XF86AudioPlay", noctalia("media toggle"), locked)
hl.bind("XF86AudioPause", noctalia("media toggle"), locked)
hl.bind("XF86AudioNext", noctalia("media next"), locked)
hl.bind("XF86AudioPrev", noctalia("media previous"), locked)
hl.bind("XF86MonBrightnessUp", noctalia("brightness-up"), held)
hl.bind("XF86MonBrightnessDown", noctalia("brightness-down"), held)
