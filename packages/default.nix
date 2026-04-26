{ pkgs }:
let
  lib = pkgs.lib;

  libcrossguidWithPc = pkgs.callPackage ./libcrossguid-with-pc.nix { };
  maliG610Firmware = pkgs.callPackage ./mali-g610-firmware.nix { };

  rockchipMpp = pkgs.stdenv.mkDerivation {
    pname = "rockchip_mpp";
    version = "unstable-2026-03-27";
    src = pkgs.fetchFromGitHub {
      owner = "rockchip-linux";
      repo = "mpp";
      rev = "develop";
      hash = "sha256-eZ3XOSWh2Bvib+OHGtrXw41BK6yh5pMJnSrA7tRR0YI=";
    };
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
      pkgs.perl
    ];
    buildInputs = [ pkgs.libdrm ];
    cmakeFlags = [ "-DBUILD_TEST=ON" ];
    postPatch = ''
      patch --batch -p1 < ${../patches/rockchip-mpp/0001-h265d-spliter-fix-ring-resize-check.patch}

      # The upstream static archive target runs a custom POST_BUILD merge step
      # that fails under Nix. Keep the library targets/install rules, but drop
      # only the fragile repack command block.
      perl -0pi -e 's/\nadd_custom_command\(TARGET \$\{MPP_STATIC\} POST_BUILD\n(?:    COMMAND .*?\n)+    \)\n/\n/s' mpp/CMakeLists.txt

      # The pkg-config templates prepend prefix to an absolute install dir
      # under Nix, which produces broken //nix/store/... paths.
      perl -0pi -e 's#libdir=\$\{prefix\}/\@CMAKE_INSTALL_LIBDIR\@#libdir=\@CMAKE_INSTALL_LIBDIR\@#' pkgconfig/rockchip_mpp.pc.cmake pkgconfig/rockchip_vpu.pc.cmake
      perl -0pi -e 's#includedir=\$\{prefix\}/\@CMAKE_INSTALL_INCLUDEDIR\@#includedir=\@CMAKE_INSTALL_INCLUDEDIR\@/rockchip#' pkgconfig/rockchip_mpp.pc.cmake pkgconfig/rockchip_vpu.pc.cmake
    '';
  };

  ffmpeg8Rkmpp = pkgs.ffmpeg_8-full.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/ffmpeg-rkmpp/0001-rkmpp-retain-packets-on-decoder-backpressure.patch
      ../patches/ffmpeg-rkmpp/0002-rkmpp-export-rockchip-10-bit-as-nv15.patch
      ../patches/ffmpeg-rkmpp/0004-rkmpp-use-non-blocking-output-polling.patch
      ../patches/ffmpeg-rkmpp/0005-rkmpp-carry-dolby-vision-rpu-metadata.patch
    ];
    configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-rkmpp" ];
    buildInputs = (old.buildInputs or [ ]) ++ [ rockchipMpp ];
  });

  kodi22WaylandRkmppDovi =
    (pkgs.kodi-wayland.override {
      ffmpeg = ffmpeg8Rkmpp;
      gbmSupport = true;
    }).overrideAttrs
      (old: {
        version = "22.0a3";
        kodiReleaseName = "Piers";

        src = pkgs.fetchFromGitHub {
          owner = "xbmc";
          repo = "xbmc";
          rev = "22.0a3-Piers";
          hash = "sha256-z9MnqMvo2jChmogYOmVz4D42NLgGbmjL19/sRs1AZSI=";
        };

        patches = (old.patches or [ ]) ++ [
          ../patches/kodi/0003-rock5c-prefer-rkmpp-drm-prime-decoders.patch
          ../patches/kodi/0005-rock5c-accept-p010-on-wayland-drm-prime.patch
          ../patches/kodi/0011-rock5c-force-drm-prime-decode-on-wayland.patch
          ../patches/kodi/0012-rock5c-include-winsystem-for-forced-drm-prime.patch
          ../patches/kodi/0013-rock5c-drop-const-winsystem-for-name-lookup.patch
          ../patches/kodi/0014-rock5c-wayland-rkmpp-dovi-profile5-libplacebo.patch
          ../patches/kodi/0015-rock5c-drm-prime-allow-six-render-references.patch
        ];

        buildInputs = (old.buildInputs or [ ]) ++ [
          libcrossguidWithPc
          pkgs.libplacebo
          pkgs.libunwind.dev
          pkgs.xorg.libxcb.dev
          pkgs.shaderc.dev
          pkgs.vulkan-loader.dev
          pkgs.libdovi
          pkgs.libsysprof-capture
          pkgs.pcre2
          pkgs.exiv2
          pkgs.libxslt.out
          pkgs.nlohmann_json
        ];
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.pkg-config ];
        cmakeFlags =
          lib.filter (
            flag: !(lib.hasPrefix "-DAPP_RENDER_SYSTEM=" flag) && !(lib.hasPrefix "-DCORE_PLATFORM_NAME=" flag)
          ) (old.cmakeFlags or [ ])
          ++ [
            "-DAPP_RENDER_SYSTEM=gles"
            "-DENABLE_INTERNAL_CROSSGUID=OFF"
            "-DENABLE_INTERNAL_EXIV2=OFF"
            "-DENABLE_INTERNAL_NLOHMANNJSON=OFF"
            "-DEXIV2_INCLUDE_DIR=${pkgs.exiv2}/include"
            "-DEXIV2_LIBRARY=${pkgs.exiv2}/lib/libexiv2.so"
            "-DEXIV2_LIBRARY_RELEASE=${pkgs.exiv2}/lib/libexiv2.so"
            "-DLIBXSLT_INCLUDE_DIR=${pkgs.libxslt.dev}/include"
            "-DLIBXSLT_LIBRARY=${pkgs.libxslt.out}/lib/libxslt.so"
            "-DLIBXSLT_EXSLT_LIBRARY=${pkgs.libxslt.out}/lib/libexslt.so"
            "-DLIBXSLT_XSLTPROC_EXECUTABLE=${pkgs.libxslt.bin}/bin/xsltproc"
          ];
        passthru = (old.passthru or { }) // {
          ffmpeg = ffmpeg8Rkmpp;
          frontend = "wayland";
          providedSessions = [ "kodi-wayland" ];
        };
      });

  rock5cFlashImage = pkgs.callPackage ./flash-image.nix { };
  flashRock5cSd = pkgs.writeShellScriptBin "flash-rock5c-sd" ''
    exec ${rock5cFlashImage}/bin/rock5c-flash-image --target-type sd "$@"
  '';
  flashRock5cEmmc = pkgs.writeShellScriptBin "flash-rock5c-emmc" ''
    exec ${rock5cFlashImage}/bin/rock5c-flash-image --target-type emmc "$@"
  '';
in
{
  aic8800 = pkgs.callPackage ./aic8800.nix { };
  ffmpeg_8-full-rkmpp = ffmpeg8Rkmpp;
  flash-rock5c-emmc = flashRock5cEmmc;
  flash-rock5c-sd = flashRock5cSd;
  kodi_22 = kodi22WaylandRkmppDovi;
  libcrossguid-with-pc = libcrossguidWithPc;
  mali-g610-firmware = maliG610Firmware;
  rock5c-flash-image = rock5cFlashImage;
  rockchip_mpp = rockchipMpp;
}
