{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.rock5c;

  makeRock5cImage =
    {
      name,
      volumeLabel ? cfg.rootfsLabel,
    }:
    pkgs.callPackage (
      { ... }:
      let
        runtimeRootDevice = "/dev/disk/by-label/${cfg.rootfsLabel}";
        imageRootDevice = "/dev/disk/by-label/${volumeLabel}";
        rootfsImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" ({
          storePaths = [ config.system.build.toplevel ];
          inherit volumeLabel;
          populateImageCommands = ''
            ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
              -c ${config.system.build.toplevel} \
              -d ./files/boot \
              -n "rockchip/rk3588s-rock-5c.dtb" \
            ;

            if [ "${imageRootDevice}" != "${runtimeRootDevice}" ]; then
              matchingFiles=$(grep -rl -- "${runtimeRootDevice}" ./files/boot || true)
              for bootFile in $matchingFiles; do
                substituteInPlace "$bootFile" \
                  --replace-fail "${runtimeRootDevice}" "${imageRootDevice}"
              done
            fi
          '';
        });
      in
      pkgs.stdenv.mkDerivation {
        inherit name;
        nativeBuildInputs = [ pkgs.util-linux ];
        buildCommand = ''
          set -x
          export img=$out;
          root_fs=${rootfsImage};

          rootSizeSectors=$(du -B 512 --apparent-size $root_fs | awk '{print $1}');
          imageSize=$((512*(rootSizeSectors + 0x8000)));

          truncate -s $imageSize $img;
          echo "$((0x8000)),,,*" | sfdisk $img

          dd if=${config.system.build.firmware}/idbloader.img of=$img seek=$((0x40)) oflag=sync status=progress
          dd if=${config.system.build.firmware}/u-boot.itb of=$img seek=$((0x4000)) oflag=sync status=progress
          dd bs=$((2**20)) if=${rootfsImage} of=$img seek=$((512*0x8000))B oflag=sync status=progress
        '';
      }
    ) { };
in
{
  config = lib.mkIf cfg.enable {
    system.build.images.rock5c_raw_image = makeRock5cImage {
      name = "rock-5c-raw-image";
      volumeLabel = cfg.rootfsLabel;
    };
  };
}
