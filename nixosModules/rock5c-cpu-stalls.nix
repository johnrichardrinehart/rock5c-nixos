{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.rock5c.cpuStalls;

  boolParam = name: value: "${name}=${if value then "1" else "0"}";

  dynamicDebugCategories = {
    cpuidle = [
      "file drivers/cpuidle/* +p"
      "file drivers/cpuidle/governors/* +p"
    ];
    psci = [
      "file drivers/firmware/psci/* +p"
    ];
    rcu = [
      "file kernel/rcu/* +p"
    ];
    timers = [
      "file kernel/time/* +p"
    ];
    scheduler = [
      "file kernel/sched/* +p"
    ];
    usb = [
      "file drivers/usb/dwc3/* +p"
      "file drivers/usb/host/xhci* +p"
    ];
    aic8800 = [
      "module aic8800_fdrv +p"
      "module aic_load_fw +p"
      "module aic_btusb +p"
    ];
  };

  selectedDynamicDebugQueries =
    lib.concatLists (map (category: dynamicDebugCategories.${category}) cfg.dynamicDebug.categories)
    ++ cfg.dynamicDebug.queries;

  dynamicDebugBootParam = ''dyndbg="${lib.concatStringsSep "; " selectedDynamicDebugQueries}"'';

  traceEventPaths = map (event: "/sys/kernel/tracing/events/${event}/enable") cfg.trace.events;

  writeCpuidleStatesScript =
    value:
    let
      selectors = lib.escapeShellArgs cfg.cpuidle.disableStates;
    in
    ''
      set -eu

      for selector in ${selectors}; do
        matched=0
        for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
          [ -d "$cpu/cpuidle" ] || continue
          for state in "$cpu"/cpuidle/state*; do
            [ -e "$state/name" ] || continue
            index="''${state##*/state}"
            name="$(${pkgs.coreutils}/bin/cat "$state/name" 2>/dev/null || true)"
            desc="$(${pkgs.coreutils}/bin/cat "$state/desc" 2>/dev/null || true)"

            if [ "$selector" = "$index" ] || [ "$selector" = "state$index" ] || [ "$selector" = "$name" ] || [ "$selector" = "$desc" ]; then
              echo ${value} > "$state/disable" 2>/dev/null || true
              matched=1
            fi
          done
        done

        if [ "$matched" -eq 0 ]; then
          echo "rock5c-cpuidle-states: no cpuidle state matched '$selector'" >&2
        fi
      done
    '';

  stallDebugTool = pkgs.writeShellScriptBin "rock5c-stall-debug" ''
    set -eu

    CONTROL="/proc/dynamic_debug/control"
    TRACE="/sys/kernel/tracing"

    run_dyndbg() {
      action="$1"
      if [ ! -w "$CONTROL" ]; then
        echo "$CONTROL is not writable; run as root or enable dynamic debug support." >&2
        exit 1
      fi

      ${lib.concatMapStringsSep "\n"
        (query: ''
          echo '${query} '"$action" | ${pkgs.coreutils}/bin/tee "$CONTROL" >/dev/null || true
        '')
        (map (query: lib.removeSuffix " +p" (lib.removeSuffix " -p" query)) selectedDynamicDebugQueries)
      }
    }

    set_trace_events() {
      value="$1"
      if [ ! -d "$TRACE" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$TRACE" 2>/dev/null || true
      fi
      if ! ${pkgs.util-linux}/bin/mountpoint -q "$TRACE"; then
        ${pkgs.util-linux}/bin/mount -t tracefs tracefs "$TRACE" 2>/dev/null || true
      fi

      ${lib.concatMapStringsSep "\n" (path: ''
        if [ -e '${path}' ]; then
          echo "$value" > '${path}' || true
        else
          echo "trace event not present: ${path}" >&2
        fi
      '') traceEventPaths}
    }

    case "''${1:-status}" in
      status)
        echo "Kernel: $(${pkgs.coreutils}/bin/uname -r)"
        echo
        echo "Command line:"
        ${pkgs.coreutils}/bin/cat /proc/cmdline
        echo
        echo
        echo "Watchdog sysctls:"
        for key in kernel.watchdog kernel.softlockup_panic kernel.hardlockup_panic kernel.hung_task_panic kernel.panic kernel.panic_on_rcu_stall kernel.max_rcu_stall_to_panic; do
          ${pkgs.procps}/bin/sysctl "$key" 2>/dev/null || true
        done
        echo
        echo "cpuidle:"
        for file in /sys/devices/system/cpu/cpuidle/{current_driver,current_governor_ro,current_governor}; do
          [ -e "$file" ] && printf '%s: %s\n' "$file" "$(${pkgs.coreutils}/bin/cat "$file")"
        done
        for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
          [ -d "$cpu/cpuidle" ] || continue
          echo "$cpu"
          for state in "$cpu"/cpuidle/state*; do
            [ -e "$state/name" ] || continue
            printf '  %s name=%s desc=%s disabled=%s usage=%s\n' \
              "''${state##*/}" \
              "$(${pkgs.coreutils}/bin/cat "$state/name" 2>/dev/null || true)" \
              "$(${pkgs.coreutils}/bin/cat "$state/desc" 2>/dev/null || true)" \
              "$(${pkgs.coreutils}/bin/cat "$state/disable" 2>/dev/null || true)" \
              "$(${pkgs.coreutils}/bin/cat "$state/usage" 2>/dev/null || true)"
          done
        done
        echo
        echo "pstore:"
        if [ -d /sys/fs/pstore ]; then
          ${pkgs.coreutils}/bin/ls -l /sys/fs/pstore
        else
          echo "/sys/fs/pstore is not mounted"
        fi
        ;;
      dyndbg-on)
        run_dyndbg +p
        ;;
      dyndbg-off)
        run_dyndbg -p
        ;;
      dyndbg-status)
        if [ -r "$CONTROL" ]; then
          ${pkgs.gnugrep}/bin/grep '=p' "$CONTROL" || true
        else
          echo "$CONTROL is not readable"
        fi
        ;;
      trace-on)
        set_trace_events 1
        ;;
      trace-off)
        set_trace_events 0
        ;;
      trace)
        ${pkgs.coreutils}/bin/cat "$TRACE/trace"
        ;;
      cpuidle-disable-configured)
        ${writeCpuidleStatesScript "1"}
        ;;
      cpuidle-enable-configured)
        ${writeCpuidleStatesScript "0"}
        ;;
      *)
        echo "Usage: rock5c-stall-debug [status|dyndbg-on|dyndbg-off|dyndbg-status|trace-on|trace-off|trace|cpuidle-disable-configured|cpuidle-enable-configured]" >&2
        exit 2
        ;;
    esac
  '';
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !(cfg.dynamicDebug.boot && selectedDynamicDebugQueries == [ ]);
            message = "rock5c.cpuStalls.dynamicDebug.boot requires at least one dynamic debug category or query.";
          }
          {
            assertion = !(cfg.trace.enable && cfg.trace.events == [ ]);
            message = "rock5c.cpuStalls.trace.enable requires at least one trace event.";
          }
        ];

        environment.systemPackages = [ stallDebugTool ];

        boot.kernelParams = lib.mkAfter (
          lib.optionals cfg.recovery.enable (
            [
              (boolParam "softlockup_panic" cfg.recovery.softlockupPanic)
              (boolParam "hardlockup_panic" cfg.recovery.hardlockupPanic)
              (boolParam "hung_task_panic" cfg.recovery.hungTaskPanic)
            ]
            ++ lib.optional (cfg.recovery.panicTimeout != null) "panic=${toString cfg.recovery.panicTimeout}"
          )
          ++ lib.optionals cfg.watchdog.enable (
            [ "nmi_watchdog=1" ]
            ++ lib.optional (
              cfg.watchdog.threshold != null
            ) "watchdog_thresh=${toString cfg.watchdog.threshold}"
          )
          ++ lib.optionals cfg.rcu.enable (
            [ "rcupdate.rcu_cpu_stall_suppress=0" ]
            ++ lib.optional (
              cfg.rcu.stallTimeout != null
            ) "rcupdate.rcu_cpu_stall_timeout=${toString cfg.rcu.stallTimeout}"
            ++ lib.optional cfg.rcu.cpuStallCpuTime "rcupdate.rcu_cpu_stall_cputime=1"
            ++ lib.optional cfg.rcu.expStallTaskDetails "rcupdate.rcu_exp_stall_task_details=1"
          )
          ++ lib.optionals cfg.logging.verbose [
            "loglevel=7"
            "printk.time=1"
          ]
          ++ lib.optional cfg.cpuidle.disable "cpuidle.off=1"
          ++ lib.optional (cfg.cpuidle.governor != null) "cpuidle.governor=${cfg.cpuidle.governor}"
          ++ lib.optional (cfg.dynamicDebug.enable && cfg.dynamicDebug.boot) dynamicDebugBootParam
        );

        boot.kernel.sysctl = lib.mkIf cfg.rcu.enable (
          {
            "kernel.panic_on_rcu_stall" = if cfg.rcu.panicOnStall then 1 else 0;
          }
          // lib.optionalAttrs (cfg.rcu.maxStallsToPanic != null) {
            "kernel.max_rcu_stall_to_panic" = cfg.rcu.maxStallsToPanic;
          }
        );

        boot.kernelPatches = lib.optionals cfg.logging.kernelConfig [
          {
            name = "rock5c-cpu-stall-debug-config";
            patch = null;
            structuredExtraConfig =
              with lib.kernel;
              {
                PSTORE = yes;
                PSTORE_CONSOLE = yes;
                PSTORE_PMSG = yes;
                PSTORE_RAM = yes;
              }
              // lib.optionalAttrs cfg.dynamicDebug.enable {
                DYNAMIC_DEBUG = yes;
                DEBUG_FS = yes;
              };
          }
        ];
      }

      (lib.mkIf (cfg.cpuidle.disableStates != [ ]) {
        systemd.services.rock5c-cpuidle-states = {
          description = "Apply Rock 5C cpuidle state debug overrides";
          wantedBy = [ "multi-user.target" ];
          after = [ "sysinit.target" ];
          path = [ pkgs.coreutils ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = writeCpuidleStatesScript "1";
        };
      })

      (lib.mkIf cfg.trace.enable {
        systemd.services.rock5c-stall-trace = {
          description = "Enable Rock 5C CPU stall trace events";
          wantedBy = [ "multi-user.target" ];
          after = [ "sysinit.target" ];
          path = [
            pkgs.coreutils
            pkgs.util-linux
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            if [ ! -d /sys/kernel/tracing ]; then
              mkdir -p /sys/kernel/tracing 2>/dev/null || true
            fi
            if ! mountpoint -q /sys/kernel/tracing; then
              mount -t tracefs tracefs /sys/kernel/tracing 2>/dev/null || true
            fi

            ${lib.concatMapStringsSep "\n" (path: ''
              if [ -e '${path}' ]; then
                echo 1 > '${path}' || true
              else
                echo "trace event not present: ${path}" >&2
              fi
            '') traceEventPaths}
          '';
        };
      })
    ]
  );
}
