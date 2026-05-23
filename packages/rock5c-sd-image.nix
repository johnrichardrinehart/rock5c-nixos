{
  firmware,
  genericExtlinuxPopulateCmd,
  modulesPath,
  rootfsLabel,
  stdenv,
  systemToplevel,
  util-linux,
  volumeLabel ? rootfsLabel,
  callPackage,
}:
let
  runtimeRootDevice = "/dev/disk/by-label/${rootfsLabel}";
  imageRootDevice = "/dev/disk/by-label/${volumeLabel}";
  rootfsImage = callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
    storePaths = [ systemToplevel ];
    inherit volumeLabel;
    populateImageCommands = ''
      ${genericExtlinuxPopulateCmd} \
        -c ${systemToplevel} \
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
  };
in
stdenv.mkDerivation {
  name = "rock-5c-sdcard-image";
  nativeBuildInputs = [ util-linux ];
  buildCommand = ''
    set -x
    export img=$out;
    root_fs=${rootfsImage};

    rootSizeSectors=$(du -B 512 --apparent-size $root_fs | awk '{print $1}');
    imageSize=$((512*(rootSizeSectors + 0x8000)));

    truncate -s $imageSize $img;
    echo "$((0x8000)),,,*" | sfdisk $img

    dd if=${firmware}/idbloader.img of=$img seek=$((0x40)) oflag=sync status=progress
    dd if=${firmware}/u-boot.itb of=$img seek=$((0x4000)) oflag=sync status=progress
    dd bs=$((2**20)) if=${rootfsImage} of=$img seek=$((512*0x8000))B oflag=sync status=progress
  '';
}
