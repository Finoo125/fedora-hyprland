-- Layout and decoration. Border colors come from Noctalia's hyprland template (noctalia.lua).
hl.config({
  general = { gaps_in = 5, gaps_out = 10, border_size = 2, layout = "master" },
  -- Main screen and laptop: one window left, the rest stacked on the right.
  master = { orientation = "left", new_status = "slave", mfact = 0.5 },
  decoration = {
    rounding = 14,
    rounding_power = 2,
    shadow = { enabled = true, range = 4, render_power = 3, color = 0xee1a1a1a },
    blur = { enabled = true, size = 3, passes = 2, vibrancy = 0.1696 },
  },
  misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 },
})

-- Fast animations from CachyOS (Hyprland's built-in default is a slow 800 ms for everything).
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("easy", { type = "spring", mass = 1, stiffness = 500, dampening = 35 })
hl.animation({ leaf = "global", enabled = true, speed = 3, bezier = "quick" })
hl.animation({ leaf = "windows", enabled = true, speed = 3, spring = "easy", style = "slide" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "quick", style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 2, bezier = "quick", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2, bezier = "quick", style = "slide bottom" })
