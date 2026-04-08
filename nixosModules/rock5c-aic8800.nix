{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.rock5c.aic8800;
  aic8800Src = import ../packages/aic8800-src.nix { inherit (pkgs) fetchFromGitHub; };
  aic8800Pkg = pkgs.callPackage ../packages/aic8800.nix {
    inherit (config.boot.kernelPackages) kernel kernelModuleMakeFlags;
  };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.stableMac.enable || cfg.stableMac.address != null;
        message = "rock5c.aic8800.stableMac.address must be set when rock5c.aic8800.stableMac.enable is true.";
      }
    ];

    boot.extraModprobeConfig =
      lib.mkAfter "options aic_load_fw aic_fw_path=\"${aic8800Src}/src/USB/driver_fw/fw/aic8800D80\"";

    # It appears that the below aren't necessary. Maybe because of USB enumeration.
    boot.kernelModules = [
      "aic_btusb"
      "aic_load_fw"
      "aic8800_fdrv"
    ];

    boot.extraModulePackages = [ aic8800Pkg ];

    systemd.network.links."10-wlan0" = lib.mkIf cfg.stableMac.enable {
      matchConfig.OriginalName = "wlan*";
      linkConfig = {
        MACAddress = cfg.stableMac.address;
      };
    };

    networking.wireless.iwd.settings = lib.mkIf cfg.stableMac.enable {
      General = {
        AddressOverride = cfg.stableMac.address;
        AddressRandomization = "disabled";
      };
    };
  };
}
