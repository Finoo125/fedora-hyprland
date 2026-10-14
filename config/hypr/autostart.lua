-- Started once with Hyprland. uwsm runs your XDG autostart entries on its own.
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
end)
