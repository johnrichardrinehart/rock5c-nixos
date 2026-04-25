{
  config,
  lib,
  pkgs,
  ...
}:
let
  media = import ./rock5c-media-context.nix { inherit config pkgs; };

  kodiAutostartLauncher = pkgs.writeShellScriptBin "rock5c-kodi-autostart" ''
    set -eu

    unset DISPLAY
    if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi

    wayland_display="''${WAYLAND_DISPLAY:-}"
    if [ -z "$wayland_display" ]; then
      for candidate in wayland-0 wayland-1 "$(${lib.getExe' pkgs.findutils "find"} "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' 2>/dev/null | ${lib.getExe' pkgs.coreutils "sort"} | head -n 1)"; do
        if [ -n "$candidate" ] && [ -S "$XDG_RUNTIME_DIR/$candidate" ]; then
          wayland_display="$candidate"
          break
        fi
      done
    fi

    if [ -z "$wayland_display" ]; then
      echo "rock5c-kodi-autostart: no Wayland socket found in $XDG_RUNTIME_DIR" >&2
      exit 1
    fi

    wayland_socket="$XDG_RUNTIME_DIR/$wayland_display"

    for _ in $(seq 1 40); do
      if [ -S "$wayland_socket" ]; then
        break
      fi
      sleep 0.5
    done

    if [ ! -S "$wayland_socket" ]; then
      echo "rock5c-kodi-autostart: timed out waiting for $wayland_socket" >&2
      exit 1
    fi

    exec ${lib.getExe media.selectedKodiPkg}
  '';
in
{
  config = lib.mkIf (media.cfg.enable && media.cfg.kodi.enable) {
    environment.systemPackages = lib.optionals media.cfg.kodi.autostart.enable [
      kodiAutostartLauncher
    ];

    systemd.user.services.rock5c-kodi-autostart = lib.mkIf media.cfg.kodi.autostart.enable {
      description = "Autostart Kodi after the graphical session is ready";
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${kodiAutostartLauncher}/bin/rock5c-kodi-autostart";
        Restart = "on-failure";
        RestartSec = "3s";
      };
    };
  };
}
