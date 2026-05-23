{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.rock5c;
in
{
  config = lib.mkIf cfg.enable {
    image.modules.sdImage =
      { config, ... }:
      {
        system.build.image = config.system.build.sdImage;
      };

    system.build.sdImage = pkgs.callPackage ../packages/rock5c-sd-image.nix {
      firmware = config.system.build.firmware;
      genericExtlinuxPopulateCmd = config.boot.loader.generic-extlinux-compatible.populateCmd;
      inherit modulesPath;
      rootfsLabel = cfg.rootfsLabel;
      systemToplevel = config.system.build.toplevel;
    };
  };
}
