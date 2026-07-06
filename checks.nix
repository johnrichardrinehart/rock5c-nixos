{
  inputs,
  pkgs,
  system,
  rock5cModules,
}:
let
  lib = inputs.nixpkgs.lib;
  evalConfig =
    modules: probe:
    let
      evaluated = lib.nixosSystem {
        inherit system;
        modules = [
          {
            nixpkgs.overlays = [ (import ./overlays/default.nix) ];
          }
          rock5cModules.default
          {
            fileSystems."/" = {
              device = "/dev/disk/by-label/NIXOS_SD";
              fsType = "ext4";
            };
            system.stateVersion = "25.11";
          }
        ]
        ++ modules;
      };
    in
    # Probe targeted config values instead of system.build.toplevel. The latter
    # retains heavyweight drv path context and fails in CI under --no-build.
    pkgs.writeText "rock5c-eval-${builtins.toString (builtins.length modules)}" (
      builtins.toJSON (probe evaluated.config)
    );
  evalImages =
    modules:
    let
      evaluated = lib.nixosSystem {
        inherit system;
        modules = [
          {
            nixpkgs.overlays = [ (import ./overlays/default.nix) ];
          }
          rock5cModules.default
          {
            fileSystems."/" = {
              device = "/dev/disk/by-label/NIXOS_SD";
              fsType = "ext4";
            };
            system.stateVersion = "25.11";
          }
        ]
        ++ modules;
      };
    in
    pkgs.writeText "rock5c-images-eval" (
      builtins.toJSON {
        hasSdImage = evaluated.config.system.build.images ? sdImage;
        hasLegacySdImage = evaluated.config.system.build ? sdImage;
      }
    );
in
{
  eval-mpp =
    evalConfig
      [
        {
          rock5c = {
            enable = true;
            supportedKernelCheck.enable = false;
            videoBackend = "mpp";
          };
        }
      ]
      (config: {
        inherit (config.rock5c) videoBackend;
        hasMppKernelModule = builtins.elem "rk_vcodec" config.boot.kernelModules;
        hasMppDeviceTreeOverlay = builtins.any (
          overlay: overlay.name == "rock5c-mpp-service"
        ) config.hardware.deviceTree.overlays;
      });

  eval-aic8800-stable-mac =
    evalConfig
      [
        {
          rock5c = {
            enable = true;
            aic8800 = {
              enable = true;
              stableMac = {
                enable = true;
                address = "02:00:00:00:00:01";
              };
            };
          };
        }
      ]
      (config: {
        inherit (config.rock5c.aic8800) interfaceName;
        stableMacAddress = config.rock5c.aic8800.stableMac.address;
        systemdMacAddress = config.systemd.network.links."10-wlan0".linkConfig.MACAddress;
        iwdAddressOverride = config.networking.wireless.iwd.settings.General.AddressOverride;
      });

  eval-cpu-stalls =
    evalConfig
      [
        {
          rock5c = {
            enable = true;
            cpuStalls = {
              enable = true;
              recovery.panicTimeout = 30;
              cpuidle.disableStates = [ "cpu-sleep" ];
              dynamicDebug = {
                enable = true;
                categories = [
                  "cpuidle"
                  "psci"
                  "rcu"
                ];
              };
            };
          };
        }
      ]
      (config: {
        panicTimeout = config.rock5c.cpuStalls.recovery.panicTimeout;
        cpuidleDisableStates = config.rock5c.cpuStalls.cpuidle.disableStates;
        dynamicDebugCategories = config.rock5c.cpuStalls.dynamicDebug.categories;
        hasCpuidleService = config.systemd.services ? rock5c-cpuidle-states;
      });

  eval-images = evalImages [
    {
      rock5c.enable = true;
    }
  ];

  rockchip-mpp = pkgs.rockchip_mpp;
}
