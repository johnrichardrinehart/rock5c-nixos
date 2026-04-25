{
  config,
  lib,
  pkgs,
  ...
}:
let
  media = import ./rock5c-media-context.nix { inherit config lib pkgs; };

  ffmpegWrapper = pkgs.writeShellApplication {
    name = "rock5c-ffmpeg-rkmpp";
    runtimeInputs = [ pkgs.ffmpeg_8-full-rkmpp ];
    text = ''
      exec ffmpeg "$@"
    '';
  };

  ffprobeWrapper = pkgs.writeShellApplication {
    name = "rock5c-ffprobe-rkmpp";
    runtimeInputs = [ pkgs.ffmpeg_8-full-rkmpp ];
    text = ''
      exec ffprobe "$@"
    '';
  };

  ffplayWrapper = pkgs.writeShellApplication {
    name = "rock5c-ffplay-rkmpp";
    runtimeInputs = [ pkgs.ffmpeg_8-full-rkmpp ];
    text = ''
      exec ffplay "$@"
    '';
  };

  h264Test = pkgs.writeShellApplication {
    name = "rock5c-ffmpeg-h264-rkmpp-test";
    runtimeInputs = [ pkgs.ffmpeg_8-full-rkmpp ];
    text = ''
      set -eu

      if [ "$#" -ne 1 ]; then
        echo "usage: rock5c-ffmpeg-h264-rkmpp-test /path/to/h264-file" >&2
        exit 2
      fi

      exec ffmpeg \
        -hide_banner \
        -loglevel verbose \
        -c:v h264_rkmpp \
        -i "$1" \
        -an \
        -frames:v 300 \
        -f null -
    '';
  };

  hevcTest = pkgs.writeShellApplication {
    name = "rock5c-ffmpeg-hevc-rkmpp-test";
    runtimeInputs = [ pkgs.ffmpeg_8-full-rkmpp ];
    text = ''
      set -eu

      if [ "$#" -ne 1 ]; then
        echo "usage: rock5c-ffmpeg-hevc-rkmpp-test /path/to/hevc-file" >&2
        exit 2
      fi

      exec ffmpeg \
        -hide_banner \
        -loglevel verbose \
        -c:v hevc_rkmpp \
        -i "$1" \
        -an \
        -frames:v 300 \
        -f null -
    '';
  };
in
{
  config = lib.mkIf media.cfg.enable {
    environment.systemPackages = (
      lib.optionals media.cfg.ffmpegTools.enable [
        pkgs.ffmpeg_8-full-rkmpp
        ffmpegWrapper
        ffprobeWrapper
        ffplayWrapper
        h264Test
        hevcTest
      ]
      ++ lib.optionals media.cfg.mpv.enable [ media.selectedMpvPkg ]
    );

    environment.shellAliases = lib.mkIf media.cfg.ffmpegTools.enable {
      "ffmpeg-rkmpp" = "${ffmpegWrapper}/bin/rock5c-ffmpeg-rkmpp";
      "ffprobe-rkmpp" = "${ffprobeWrapper}/bin/rock5c-ffprobe-rkmpp";
      "ffplay-rkmpp" = "${ffplayWrapper}/bin/rock5c-ffplay-rkmpp";
    };
  };
}
