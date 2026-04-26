{ lib, ... }:
{
  options.rock5c = {
    enable = lib.mkEnableOption "radxa rock5c hardware stuff";

    videoBackend = lib.mkOption {
      type = lib.types.enum [
        "mainline"
        "mpp"
      ];
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

    cpuStalls = {
      enable = lib.mkEnableOption "Rock 5C CPU lockup and RCU stall handling/debugging";

      recovery = {
        enable = lib.mkEnableOption "panic and reboot handling for CPU lockups" // {
          default = true;
        };

        softlockupPanic = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Set `softlockup_panic=1` so soft lockups panic instead of leaving the board wedged.";
        };

        hardlockupPanic = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Set `hardlockup_panic=1` so hard lockups panic instead of leaving the board wedged.";
        };

        hungTaskPanic = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Set `hung_task_panic=1`. Leave this off unless blocked tasks are the failure being tested.";
        };

        panicTimeout = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = 30;
          example = 10;
          description = "Seconds before rebooting after a kernel panic. Set to null to leave `panic=` unmanaged.";
        };
      };

      watchdog = {
        enable = lib.mkEnableOption "kernel watchdog parameters for CPU stall diagnosis" // {
          default = true;
        };

        threshold = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 10;
          description = "Optional `watchdog_thresh=` value in seconds.";
        };
      };

      rcu = {
        enable = lib.mkEnableOption "RCU stall reporting parameters" // {
          default = true;
        };

        panicOnStall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Set `kernel.panic_on_rcu_stall=1` so repeated RCU stalls become crash-capturable.";
        };

        maxStallsToPanic = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = 1;
          example = 2;
          description = "Optional `kernel.max_rcu_stall_to_panic` sysctl when `panicOnStall` is enabled.";
        };

        stallTimeout = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 21;
          description = "Optional `rcupdate.rcu_cpu_stall_timeout=` value in seconds.";
        };

        cpuStallCpuTime = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Set `rcupdate.rcu_cpu_stall_cputime=1` to include CPU-time and interrupt/task counts in RCU stall reports.";
        };

        expStallTaskDetails = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Set `rcupdate.rcu_exp_stall_task_details=1` for expedited RCU stall task details.";
        };
      };

      cpuidle = {
        disable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Add `cpuidle.off=1` for a full cpuidle A/B test.";
        };

        governor = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "ladder"
              "menu"
              "teo"
            ]
          );
          default = null;
          example = "teo";
          description = "Optional `cpuidle.governor=` override.";
        };

        disableStates = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "cpu-sleep" ];
          description = ''
            cpuidle states to disable at runtime after boot. Each selector can
            be a state index (`1`), sysfs state name (`state1`), state `name`,
            or state `desc`. This is useful for testing deeper PSCI idle states
            such as `cpu-sleep` while leaving shallow WFI enabled.
          '';
        };
      };

      logging = {
        verbose = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Add verbose printk-oriented kernel parameters (`loglevel=7`, `printk.time=1`).";
        };

        kernelConfig = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable pstore/ramoops kernel config, and dynamic debug config when requested.";
        };
      };

      dynamicDebug = {
        enable = lib.mkEnableOption "Linux dynamic debug support for CPU stall investigation";

        boot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Apply selected dynamic debug queries at boot via the `dyndbg=` kernel parameter.";
        };

        categories = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "cpuidle"
              "psci"
              "rcu"
              "timers"
              "scheduler"
              "usb"
              "aic8800"
            ]
          );
          default = [
            "cpuidle"
            "psci"
            "rcu"
          ];
          example = [
            "cpuidle"
            "psci"
            "usb"
            "aic8800"
          ];
          description = "Predefined dynamic debug query groups to enable via boot parameter or helper command.";
        };

        queries = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "file drivers/base/power/* +p" ];
          description = "Extra raw dynamic debug queries.";
        };
      };

      trace = {
        enable = lib.mkEnableOption "boot-time tracefs events useful for CPU idle/stall diagnosis";

        events = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "power/cpu_idle"
            "irq/irq_handler_entry"
            "irq/irq_handler_exit"
            "timer/hrtimer_expire_entry"
            "timer/hrtimer_expire_exit"
          ];
          example = [
            "power/cpu_idle"
            "timer/hrtimer_expire_entry"
          ];
          description = "Trace event paths under `/sys/kernel/tracing/events` to enable.";
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
      enable = lib.mkEnableOption "Rock 5C media packages for the Wayland/Hyprland RKMPP stack";

      ffmpegTools.enable = lib.mkEnableOption "Rock 5C FFmpeg RKMPP tools" // {
        default = true;
      };

      mpv = {
        enable = lib.mkEnableOption "install the stock mpv package alongside Kodi" // {
          default = false;
        };
      };

      kodi = {
        enable = lib.mkEnableOption "Rock 5C Kodi 22 Wayland RKMPP Dolby Vision package" // {
          default = true;
        };

        autostart.enable = lib.mkEnableOption "autostart Kodi after the compositor/session comes up";

        disableCecStandbyOnExit = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Apply a Rock 5C-specific Kodi patch that suppresses HDMI-CEC standby and
            inactive-source commands when Kodi exits.
          '';
        };
      };
    };
  };
}
