{
  config,
  lib,
  pkgs,
}:
let
  cfg = config.rock5c.media;
  rock5cCfg = config.rock5c;

  defaultSession = lib.toLower (lib.attrByPath [ "services" "displayManager" "defaultSession" ] "" config);

  waylandSession =
    lib.attrByPath [ "programs" "niri" "enable" ] false config
    || lib.attrByPath [ "programs" "hyprland" "enable" ] false config
    || lib.attrByPath [ "programs" "sway" "enable" ] false config
    || lib.attrByPath [ "services" "desktopManager" "plasma6" "enable" ] false config
    || lib.hasInfix "wayland" defaultSession
    || lib.hasInfix "niri" defaultSession
    || lib.hasInfix "hypr" defaultSession
    || lib.hasInfix "sway" defaultSession
    || lib.hasInfix "plasma" defaultSession
    || lib.hasInfix "kwin" defaultSession
    || lib.attrByPath [ "rock5c" "sessions" "hyprland" "enable" ] false config;

  x11Session = lib.attrByPath [ "services" "xserver" "enable" ] false config && !waylandSession;

  autoKodiVariant =
    if waylandSession then
      "wayland"
    else if x11Session then
      "x11"
    else
      "gbm";

  effectiveKodiVariant = if cfg.kodi.variant == "auto" then autoKodiVariant else cfg.kodi.variant;
  effectiveKodiFfmpegBackend =
    if cfg.kodi.ffmpegBackend == "auto" then
      if rock5cCfg.videoBackend == "mpp" then
        "ffmpeg8-rkmpp"
      else
        "ffmpeg8-rkmpp-v4l2request"
    else
      cfg.kodi.ffmpegBackend;

  selectedKodiAttr = "kodi_22-${effectiveKodiVariant}-${effectiveKodiFfmpegBackend}";
  selectedKodiPkg =
    let
      baseKodiPkg = builtins.getAttr selectedKodiAttr pkgs;
    in
    if cfg.kodi.disableCecStandbyOnExit then
      baseKodiPkg.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../patches/kodi/0002-rock5c-dont-send-cec-standby-on-exit.patch ];
      })
    else
      baseKodiPkg;

  selectedMpvPkg =
    if cfg.mpv.variant == "rockchip" then
      pkgs.mpv_rockchip
    else
      pkgs.mpv_v4l2request;
in
{
  inherit
    cfg
    effectiveKodiVariant
    effectiveKodiFfmpegBackend
    selectedKodiAttr
    selectedKodiPkg
    selectedMpvPkg
    ;
}
