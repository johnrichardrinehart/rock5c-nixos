{
  lib,
  osConfig,
  ...
}:
let
  hyprlandEnabled = lib.attrByPath [ "rock5c" "sessions" "hyprland" "enable" ] false osConfig;
in
{
  config = lib.mkIf hyprlandEnabled {
    home.file.".config/hypr/hyprland.conf".text = ''
      source = /etc/xdg/hypr/hyprland.conf
    '';
  };
}
