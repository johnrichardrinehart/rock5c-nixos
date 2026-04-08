{
  default = import ./all.nix;
  rock5c = import ./rock5c-options.nix;
  rock5c-aic8800 = import ./rock5c-aic8800.nix;
  rock5c-base = import ./rock5c-base.nix;
  rock5c-flash-tools = import ./rock5c-flash-tools.nix;
  rock5c-gstreamer-hwdec = import ./rock5c-gstreamer-hwdec.nix;
  rock5c-hyprland-session = import ./rock5c-hyprland-session.nix;
  rock5c-kodi = import ./rock5c-kodi.nix;
  rock5c-rkvdec = import ./rock5c-rkvdec.nix;
}
