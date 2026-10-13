-- fedora-hyprland defaults. Your ~/.config/hypr/hyprland.lua calls this with the repo path.
-- Each module is a separate require, so an error in one doesn't stop the others.
return function(repo)
  local dir = repo .. "/config/hypr/"
  for _, name in ipairs({ "look", "input", "monitors", "desks", "rules", "binds", "autostart" }) do
    require(dir .. name .. ".lua")
  end
end
