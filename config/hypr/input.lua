-- Input. The keyboard layout is set in your ~/.config/hypr/hyprland.lua (taken from the Fedora installer).
hl.config({
  input = {
    follow_mouse = 1,
    touchpad = { natural_scroll = true },
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
