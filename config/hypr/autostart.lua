-- Started once with Hyprland. uwsm runs your XDG autostart entries on its own.
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
  -- Mounts USB drives as they are plugged in; the Noctalia udiskie plugin shows the notifications.
  hl.exec_cmd("uwsm app -- udiskie --no-notify --no-tray")
end)
