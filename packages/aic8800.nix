{
  pkgs,
  stdenv,
  lib,
  fetchFromGitHub,
  kernel ? pkgs.linuxPackages.kernel,
  kmod,
  buildPackages,
  kernelModuleMakeFlags ? [ ],
}:
let
  src = import ./aic8800-src.nix { inherit fetchFromGitHub; };
in
stdenv.mkDerivation rec {
  name = "aic8800-${version}-module-${kernel.modDirVersion}";
  version = src.rev;
  inherit src;

  hardeningDisable = [
    "pic"
    "format"
  ];

  nativeBuildInputs = [ kmod ] ++ kernel.moduleBuildDependencies;
  depsBuildBuild = [ buildPackages.stdenv.cc ];
  makeFlags = [ "CONFIG_PLATFORM_UBUNTU=n" ];

  env = {
    KERNELDIR = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
    KERNELVERSION = kernel.modDirVersion;
  };

  buildPhase = ''
    cp -r "$KERNELDIR" ./build; # need it to be writeable
    chmod -R u+w ./build;

    make -C "./build" M=../src/USB/driver_fw/drivers/aic8800 ARCH=${kernel.karch} CROSS_COMPILE=${stdenv.cc.targetPrefix};
    make -C "./build" M=../src/USB/driver_fw/drivers/aic_btusb ARCH=${kernel.karch} CROSS_COMPILE=${stdenv.cc.targetPrefix};
  '';

  installPhase = ''
    dest="$out/lib/modules/$KERNELVERSION/misc";
    mkdir -p "$dest";
    find ./build -name '*.ko' -exec mv {} "$dest/" \;
  '';

  patches =
    let
      patchFiles = lib.strings.filter (x: x != "") (
        lib.strings.splitStringBy (prev: cur: cur == "\n") false (
          builtins.readFile "${src}/debian/patches/series"
        )
      );
      vendorPatches = builtins.map (x: "${src}/debian/patches/${x}") patchFiles;
    in
    vendorPatches ++ [ ../patches/aic8800/0001-fix-remove-unnecessary-path-segment-from-aic_fw_path.patch ];

  meta = {
    description = "A kernel module to create V4L2 loopback devices";
    homepage = "https://github.com/aramg/droidcam";
    license = lib.licenses.gpl2;
    maintainers = [ lib.maintainers.makefu ];
    platforms = lib.platforms.linux;
  };
}
