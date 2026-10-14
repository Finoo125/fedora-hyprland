-- Unit tests for the logic in config/hypr. Run from the repo root: lua tests/test_hypr.lua
local failures = 0
local function check(cond, msg)
  if cond then print("ok   " .. msg) else print("FAIL " .. msg); failures = failures + 1 end
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- Recording stub for Hyprland's `hl` table.
local state = { active = {}, all = {}, windows = {}, ws = { id = 1 } }
local calls = { binds = {}, monitors = {}, rules = {}, events = {}, dispatched = {} }
local function proxy(path)
  return setmetatable({}, {
    __index = function(_, k) return proxy(path .. "." .. k) end,
    __call = function(_, args) return { dsp = path, args = args } end,
  })
end
hl = {
  dsp = proxy("dsp"),
  bind = function(keys, action) calls.binds[keys] = action end,
  dispatch = function(d) table.insert(calls.dispatched, d) end,
  monitor = function(spec) table.insert(calls.monitors, spec) end,
  workspace_rule = function(spec) table.insert(calls.rules, spec) end,
  on = function(ev, fn) calls.events[ev] = calls.events[ev] or {}; table.insert(calls.events[ev], fn) end,
  get_monitors = function(opts) if opts and opts.all then return state.all end return state.active end,
  get_windows = function() return state.windows end,
  get_active_workspace = function() return state.ws end,
  get_config = function() return 1.0 end,
  config = function() end, window_rule = function() end, layer_rule = function() end,
  gesture = function() end, env = function() end, exec_cmd = function() end,
}

-- monitors.lua
local mon = dofile("config/hypr/monitors.lua")
check(mon.is_external("DP-5"), "DP-5 is external")
check(not mon.is_external("eDP-1"), "eDP-1 is the laptop panel")
check(not mon.is_external("FALLBACK"), "Hyprland's FALLBACK output is not a real monitor")
check(mon.internal_enabled({ { name = "eDP-1" } }), "undocked: panel on")
check(not mon.internal_enabled({ { name = "eDP-1" }, { name = "DP-5" } }), "docked: panel off")
check(mon.internal_enabled({ { name = "FALLBACK" } }), "last external unplugged: panel comes back")
check(mon.internal_enabled({}), "no monitors at all: panel on")

state.active = { { name = "DP-5", description = "HP Inc. HP X27i CNK0420XTM" } }
state.all = { { name = "eDP-1", description = "BOE 0x0BCA" }, state.active[1] }
calls.monitors = {}
mon.apply()
check(calls.monitors[1].output == "eDP-1" and calls.monitors[1].disabled == true, "docked: apply() disables eDP-1")
state.active = { { name = "FALLBACK", description = "" } }
calls.monitors = {}
mon.apply()
-- hl.monitor merges into the existing rule for that output, so "on" must clear disabled explicitly.
check(calls.monitors[1].output == "eDP-1" and calls.monitors[1].disabled == false, "undocked: apply() re-enables eDP-1")
check(calls.events["monitor.added"] and calls.events["monitor.removed"], "dock handling runs on hotplug events")

-- The removed monitor may still be listed when monitor.removed fires: it must not keep the panel off.
state.active = { { name = "DP-5", description = "HP Inc. HP X27i" } }
calls.monitors = {}
calls.events["monitor.removed"][1]({ name = "DP-5", description = "HP Inc. HP X27i" })
check(calls.monitors[1].output == "eDP-1" and not calls.monitors[1].disabled, "unplugging the last monitor turns the panel on even if it's still listed")
calls.monitors = {}
calls.events["monitor.added"][1]({ name = "DP-5", description = "HP Inc. HP X27i" })
check(calls.monitors[1].output == "eDP-1" and calls.monitors[1].disabled == true, "plugging in a monitor turns the panel off")

-- desks.lua
local desks = dofile("config/hypr/desks.lua")
check(same(desks.focus_order(2, true), { 12, 2 }), "docked desk 2: portrait 12 first, main 2 last (focus ends on main)")
check(same(desks.focus_order(2, false), { 2 }), "undocked desk 2: only workspace 2")
check(desks.move_target(13, 1) == 11, "window on the portrait monitor moves to portrait desk 1")
check(desks.move_target(3, 4) == 4, "window on the main monitor moves to main desk 4")
local strays = desks.strays({
  { address = "0xa", workspace = { id = 12 } },
  { address = "0xb", workspace = { id = 2 } },
  { address = "0xc", workspace = { id = -98 } },
})
check(#strays == 1 and strays[1].address == "0xa" and strays[1].workspace == 2, "undock moves only portrait-desk windows")

state.active = { { name = "DP-6", description = "HP Inc. HP E27q G5 CNC42511SG" }, { name = "DP-5", description = "HP Inc. HP X27i" } }
calls.dispatched = {}
calls.binds["SUPER + code:11"]()
check(#calls.dispatched == 2 and calls.dispatched[1].args.workspace == "12" and calls.dispatched[2].args.workspace == "2",
  "Super+2 switches portrait to 12, then main to 2")

-- Undock: the portrait monitor's removal moves its windows, even if it is still listed when the event fires.
state.windows = { { address = "0xa", workspace = { id = 12 } } }
calls.dispatched = {}
local undock = calls.events["monitor.removed"][#calls.events["monitor.removed"]]
undock({ name = "DP-6", description = "HP Inc. HP E27q G5 CNC42511SG" })
check(#calls.dispatched == 1 and calls.dispatched[1].args.window == "address:0xa" and calls.dispatched[1].args.workspace == "2",
  "removing the portrait monitor moves its windows to the main desks")
calls.dispatched = {}
undock({ name = "DP-5", description = "HP Inc. HP X27i" })
check(#calls.dispatched == 0, "removing another monitor moves nothing")

local rule_for_11
for _, r in ipairs(calls.rules) do if r.workspace == "11" then rule_for_11 = r end end
check(rule_for_11 and rule_for_11.layout_opts.orientation == "top", "portrait desks stack windows top/bottom")

-- binds.lua and main.lua load and register what they promise
dofile("config/hypr/binds.lua")
check(calls.binds["SUPER + Return"] ~= nil, "Super+Return is bound")
check(calls.binds["SUPER + code:11"] ~= nil and calls.binds["SUPER + ALT + code:11"] ~= nil, "desk and monitor-focus keys don't collide")

local loaded = {}
local real_require = require
require = function(p) table.insert(loaded, p); return {} end
dofile("config/hypr/main.lua")("/repo")
require = real_require
check(#loaded == 7 and loaded[1] == "/repo/config/hypr/look.lua", "main.lua loads all 7 modules by absolute path")

if failures > 0 then print(failures .. " failed"); os.exit(1) end
print("all passed")
