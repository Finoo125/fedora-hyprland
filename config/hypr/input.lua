-- Input: the system keyboard layout (set with localectl, asked by install.sh), natural scrolling for mouse and touchpad.
local M = {}

-- keyboard(PATH) -> layout, variant from localed's keyboard file; "us" when it's missing.
function M.keyboard(path)
  local layout, variant = "us", ""
  local f = io.open(path or "/etc/X11/xorg.conf.d/00-keyboard.conf")
  if not f then return layout, variant end
  for line in f:lines() do
    local key, value = line:match('^%s*Option%s+"Xkb(%a+)"%s+"([^"]*)"')
    if key == "Layout" and value ~= "" then layout = value end
    if key == "Variant" then variant = value end
  end
  f:close()
  return layout, variant
end

local layout, variant = M.keyboard()
hl.config({
  input = {
    kb_layout = layout,
    kb_variant = variant,
    follow_mouse = 1,
    natural_scroll = true,
    touchpad = { natural_scroll = true },
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

return M
