{
  config,
  lib,
  pkgs,
  ...
}:
let
  media = import ./rock5c-media-context.nix { inherit config lib pkgs; };

  kodiGbmSessionCommand = "${pkgs.writeShellScript "rock5c-kodi-gbm-session" ''
    export KODI_DRMPRIME_TRACE=1
    exec ${lib.getExe' media.selectedKodiPkg "kodi-standalone"} --windowing=gbm
  ''}";

  kodiAutostartLauncher = pkgs.writeShellScriptBin "rock5c-kodi-autostart" ''
    set -eu

    ${lib.optionalString (media.effectiveKodiVariant == "wayland") ''
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

      ${lib.optionalString (lib.attrByPath [ "programs" "niri" "enable" ] false config) ''
        for _ in $(seq 1 40); do
          if ${lib.getExe config.programs.niri.package} msg --json outputs 2>/dev/null \
            | ${lib.getExe pkgs.jq} -e 'length > 0 and any(.[]; .current_mode != null)' >/dev/null; then
            break
          fi
          sleep 0.5
        done
      ''}
    ''}

    exec ${lib.getExe media.selectedKodiPkg}
  '';
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(media.cfg.enable && media.cfg.kodi.enable && media.effectiveKodiVariant == "gbm" && media.cfg.kodi.sessionUser == null);
          message = "rock5c.media.kodi.sessionUser must be set when using the GBM Kodi session.";
        }
      ];
    }
    (lib.mkIf (media.cfg.enable && media.cfg.kodi.enable) {
      environment.systemPackages = (
        lib.optionals (media.cfg.kodi.autostart.enable && media.effectiveKodiVariant != "gbm") [ kodiAutostartLauncher ]
      );

      services.displayManager.sessionPackages = lib.mkIf (media.effectiveKodiVariant == "gbm") [
        media.selectedKodiPkg
      ];

      programs.dconf.enable = lib.mkIf (media.effectiveKodiVariant == "gbm") true;
      services.displayManager.defaultSession =
        lib.mkIf (media.effectiveKodiVariant == "gbm") (lib.mkForce "kodi-gbm");

      services.displayManager.sddm.enable =
        lib.mkIf (media.effectiveKodiVariant == "gbm") (lib.mkForce false);
      services.displayManager.sddm.wayland.enable =
        lib.mkIf (media.effectiveKodiVariant == "gbm") (lib.mkForce false);
      services.displayManager.autoLogin.enable =
        lib.mkIf (media.effectiveKodiVariant == "gbm") (lib.mkForce false);
      services.desktopManager.plasma6.enable =
        lib.mkIf (media.effectiveKodiVariant == "gbm") (lib.mkForce false);

      services.greetd = lib.mkIf (media.effectiveKodiVariant == "gbm") {
        enable = true;
        settings.default_session = {
          command = kodiGbmSessionCommand;
          user = media.cfg.kodi.sessionUser;
        };
      };

      warnings = lib.optionals (media.cfg.kodi.autostart.enable && media.effectiveKodiVariant == "gbm") [
        "Rock 5C Kodi autostart is disabled for the GBM variant because GBM Kodi must run as a direct greetd session, not inside an existing desktop session."
      ];

      systemd.user.services.rock5c-kodi-autostart =
        lib.mkIf (media.cfg.kodi.autostart.enable && media.effectiveKodiVariant != "gbm") {
          description = "Autostart Kodi after the graphical session is ready";
          after =
            [ "graphical-session.target" ]
            ++ lib.optionals (lib.attrByPath [ "programs" "niri" "enable" ] false config) [ "niri.service" ];
          wants =
            [ "graphical-session.target" ]
            ++ lib.optionals (lib.attrByPath [ "programs" "niri" "enable" ] false config) [ "niri.service" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            Environment = [ "KODI_DRMPRIME_TRACE=1" ];
            ExecStart = "${kodiAutostartLauncher}/bin/rock5c-kodi-autostart";
            Restart = "on-failure";
            RestartSec = "3s";
          };
        };

      users.users = lib.mkIf (media.effectiveKodiVariant == "gbm" && media.cfg.kodi.sessionUser != null) {
        ${media.cfg.kodi.sessionUser}.extraGroups = [ "seat" ];
      };
    })
  ];
}
