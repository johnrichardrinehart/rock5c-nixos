{
  inputs,
  pkgs,
  system,
  rock5cModules,
}:
let
  lib = inputs.nixpkgs.lib;
  evalSystem =
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
    pkgs.writeText "rock5c-eval-${builtins.toString (builtins.length modules)}" evaluated.config.system.build.toplevel.drvPath;
in
{
  eval-mpp = evalSystem [
    {
      rock5c = {
        enable = true;
        supportedKernelCheck.enable = false;
        videoBackend = "mpp";
      };
    }
  ];

  eval-aic8800-stable-mac = evalSystem [
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
  ];

  eval-cpu-stalls = evalSystem [
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
  ];

  rockchip-mpp = pkgs.rockchip_mpp;
}
