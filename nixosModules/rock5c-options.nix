{ lib, ... }:
{
  options.rock5c = {
    enable = lib.mkEnableOption "radxa rock5c hardware stuff";

    videoBackend = lib.mkOption {
      type = lib.types.enum [ "mainline" "mpp" ];
      default = "mainline";
      description = ''
        Select which Rockchip video stack should own the RK3588S2 media blocks.
        "mainline" keeps the V4L2/media drivers such as rockchip_vdec and hantro_vpu.
        "mpp" applies the vendor-style MPP device-tree takeover intended for /dev/mpp.
      '';
    };

    supportedKernelCheck.enable = lib.mkEnableOption "Rock 5C kernel support-range assertions" // {
      default = true;
    };

    rootfsLabel = lib.mkOption {
      type = lib.types.str;
      default = "NIXOS_SD";
      description = "Filesystem label used by the default Rock 5C rootfs image and boot config.";
    };

    mpp = {
      disabledDrivers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "VDPU1"
            "VEPU1"
            "VDPU2"
            "VEPU2"
            "RKVDEC"
            "RKVENC"
            "IEP2"
            "JPGDEC"
            "RKVDEC2"
            "RKVENC2"
            "AV1DEC"
            "VDPP"
            "JPGENC"
          ]
        );
        default = [ ];
        example = [ "RKVDEC2" ];
        description = ''
          MPP subdrivers to suppress when loading `rk_vcodec`. This is the
          preferred user-facing way to opt out of specific engines without
          hand-constructing a bitmask.
        '';
      };

      driverMask = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        example = 10240;
        description = ''
          Optional `rk_vcodec` subdriver bitmask passed as the `mpp_driver_mask`
          module parameter. Leave this unset to register all Kconfig-enabled MPP
          subdrivers. This is a low-level escape hatch; prefer
          `rock5c.mpp.disabledDrivers` for normal use.
        '';
      };
    };

    aic8800 = {
      enable = lib.mkEnableOption "AIC8800 Wi-Fi/Bluetooth support";

      interfaceName = lib.mkOption {
        type = lib.types.str;
        default = "wlan0";
        description = "Stable interface name assigned to the AIC8800 WLAN device.";
      };

      stableMac = {
        enable = lib.mkEnableOption "stable MAC address handling for AIC8800 devices";

        address = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "88:00:03:00:10:55";
          description = "Locally administered MAC address to assign to the AIC8800 WLAN device.";
        };
      };
    };

    gstreamerHwdec.enable = lib.mkEnableOption "Rock 5C GStreamer stateless hardware decode tools";
    rkvdec.enable = lib.mkEnableOption "Collabora RK3588 rkvdec backport for Rock 5C";

    sessions.hyprland = {
      enable = lib.mkEnableOption "Rock 5C Hyprland session";

      user = lib.mkOption {
        type = lib.types.str;
        default = "john";
        description = "User account that should own the greetd Hyprland session.";
      };
    };

    media = {
      enable = lib.mkEnableOption "Rock 5C media packages and Kodi session variants";

      ffmpegTools.enable = lib.mkEnableOption "Rock 5C FFmpeg V4L2 request tools" // {
        default = true;
      };

      mpv = {
        enable = lib.mkEnableOption "Rock 5C mpv package with hardware-decoding-focused FFmpeg" // {
          default = true;
        };

        variant = lib.mkOption {
          type = lib.types.enum [ "rockchip" "v4l2request" ];
          default = "v4l2request";
          description = ''
            Which Rock 5C mpv build to install.
            `rockchip` links mpv against ffmpeg-rockchip for `rkmpp`/RGA support.
            `v4l2request` keeps the local FFmpeg V4L2-request patch stack.
          '';
        };
      };

      kodi = {
        enable = lib.mkEnableOption "Rock 5C Kodi 22 V4L2 request package" // {
          default = true;
        };

        autostart.enable = lib.mkEnableOption "autostart Kodi after the compositor/session comes up";

        sessionUser = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "User account to run the standalone GBM Kodi session under.";
        };

        disableCecStandbyOnExit = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Apply a Rock 5C-specific Kodi patch that suppresses HDMI-CEC standby and
            inactive-source commands when Kodi exits.
          '';
        };

        variant = lib.mkOption {
          type = lib.types.enum [ "auto" "wayland" "x11" "gbm" ];
          default = "auto";
        };

        ffmpegBackend = lib.mkOption {
          type = lib.types.enum [ "auto" "ffmpeg8-rkmpp-v4l2request" "ffmpeg8-rkmpp" "ffmpeg-rockchip" ];
          default = "auto";
        };
      };
    };
  };
}
