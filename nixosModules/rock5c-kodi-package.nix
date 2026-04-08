{
  config,
  lib,
  pkgs,
  ...
}:
let
  media = import ./rock5c-media-context.nix { inherit config lib pkgs; };
in
{
  config = lib.mkIf (media.cfg.enable && media.cfg.kodi.enable) {
    environment.systemPackages = [ media.selectedKodiPkg ];
  };
}
