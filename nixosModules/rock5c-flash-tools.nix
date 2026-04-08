{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.rock5c;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.rock5c-flash-image
      pkgs.flash-rock5c-sd
      pkgs.flash-rock5c-emmc
    ];
  };
}
