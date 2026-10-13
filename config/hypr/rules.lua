-- Window and layer rules.
hl.window_rule({ name = "suppress-maximize-events", match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ name = "noctalia-settings", match = { class = "dev.noctalia.Noctalia" }, float = true, size = { 1080, 920 } })
hl.window_rule({
  name = "small-tools-float",
  match = { class = "^(org.gnome.Calculator|nm-connection-editor|system-config-printer)$" },
  float = true,
})
hl.layer_rule({
  name = "noctalia",
  match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" },
  no_anim = true,
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})
