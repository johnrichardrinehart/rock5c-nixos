{
  config,
  pkgs,
  ...
}:
let
  cfg = config.rock5c.media;
in
{
  inherit cfg;

  selectedKodiPkg =
    if cfg.kodi.disableCecStandbyOnExit then
      pkgs.kodi_22.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../patches/kodi/0002-rock5c-dont-send-cec-standby-on-exit.patch
        ];
      })
    else
      pkgs.kodi_22;
  selectedMpvPkg = pkgs.mpv;
}
