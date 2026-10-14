-- Input: German keyboard, inverted (natural) scrolling for mouse and touchpad.
hl.config({
  input = {
    kb_layout = "de",
    follow_mouse = 1,
    natural_scroll = true,
    touchpad = { natural_scroll = true },
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
