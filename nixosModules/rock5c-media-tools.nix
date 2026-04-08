{
  config,
  lib,
  pkgs,
  ...
}:
let
  media = import ./rock5c-media-context.nix { inherit config lib pkgs; };

  ffmpegWrapper = pkgs.writeShellApplication {
    name = "rock5c-ffmpeg-v4l2request";
    runtimeInputs = [ pkgs.ffmpeg_8-full-v4l2request ];
    text = ''
      exec ffmpeg "$@"
    '';
  };

  ffprobeWrapper = pkgs.writeShellApplication {
    name = "rock5c-ffprobe-v4l2request";
    runtimeInputs = [ pkgs.ffmpeg_8-full-v4l2request ];
    text = ''
      exec ffprobe "$@"
    '';
  };

  ffplayWrapper = pkgs.writeShellApplication {
    name = "rock5c-ffplay-v4l2request";
    runtimeInputs = [ pkgs.ffmpeg_8-full-v4l2request ];
    text = ''
      exec ffplay "$@"
    '';
  };

  h264Test = pkgs.writeShellApplication {
    name = "rock5c-ffmpeg-h264-v4l2request-test";
    runtimeInputs = [ pkgs.ffmpeg_8-full-v4l2request ];
    text = ''
      set -eu

      if [ "$#" -ne 1 ]; then
        echo "usage: rock5c-ffmpeg-h264-v4l2request-test /path/to/h264-file" >&2
        exit 2
      fi

      exec ffmpeg \
        -hide_banner \
        -loglevel verbose \
        -hwaccel v4l2request \
        -hwaccel_output_format drm_prime \
        -i "$1" \
        -an \
        -frames:v 300 \
        -f null -
    '';
  };

  hevcTest = pkgs.writeShellApplication {
    name = "rock5c-ffmpeg-hevc-v4l2request-test";
    runtimeInputs = [ pkgs.ffmpeg_8-full-v4l2request ];
    text = ''
      set -eu

      if [ "$#" -ne 1 ]; then
        echo "usage: rock5c-ffmpeg-hevc-v4l2request-test /path/to/hevc-file" >&2
        exit 2
      fi

      exec ffmpeg \
        -hide_banner \
        -loglevel verbose \
        -hwaccel v4l2request \
        -hwaccel_output_format drm_prime \
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
        pkgs.ffmpeg_8-full-v4l2request
        ffmpegWrapper
        ffprobeWrapper
        ffplayWrapper
        h264Test
        hevcTest
      ]
      ++ lib.optionals media.cfg.mpv.enable [ media.selectedMpvPkg ]
    );

    environment.shellAliases = lib.mkIf media.cfg.ffmpegTools.enable {
      "ffmpeg-v4l2request" = "${ffmpegWrapper}/bin/rock5c-ffmpeg-v4l2request";
      "ffprobe-v4l2request" = "${ffprobeWrapper}/bin/rock5c-ffprobe-v4l2request";
      "ffplay-v4l2request" = "${ffplayWrapper}/bin/rock5c-ffplay-v4l2request";
    };
  };
}
