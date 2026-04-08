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
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    system.build.firmware = pkgs.ubootRock5ModelC;

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    boot.kernelParams = lib.mkAfter [
      "earlycon=uart8250,mmio32,0xfeb50000"
      "ignore_loglevel"
    ];

    hardware.firmware = [ pkgs.mali-g610-firmware ];

    hardware.deviceTree.overlays = [
      {
        name = "rock5c-hdmi0-audio";
        filter = "rockchip/rk3588s-rock-5c.dtb";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "radxa,rock-5c", "rockchip,rk3588s";
          };

          &hdmi0_sound {
            status = "okay";
          };

          &i2s5_8ch {
            status = "okay";
          };
        '';
      }
      {
        name = "rock5c-ramoops";
        filter = "rockchip/rk3588s-rock-5c.dtb";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "radxa,rock-5c", "rockchip,rk3588s";
          };

          &{/reserved-memory} {
            ramoops: ramoops@110000 {
              compatible = "ramoops";
              reg = <0x0 0x110000 0x0 0xe0000>;
              boot-log-size = <0x8000>;
              boot-log-count = <0x1>;
              console-size = <0x80000>;
              pmsg-size = <0x30000>;
              ftrace-size = <0x0>;
              record-size = <0x14000>;
            };
          };
        '';
      }
    ];

    systemd.services.mount-pstore = {
      description = "Mount pstore filesystem for crash capture";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = [ pkgs.util-linux pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /sys/fs/pstore
        mountpoint -q /sys/fs/pstore || mount -t pstore pstore /sys/fs/pstore || true
      '';
    };
  };
}
