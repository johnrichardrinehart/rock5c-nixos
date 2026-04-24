{ pkgs }:
let
  lib = pkgs.lib;

  unsupportedRockchipLibFlags = [
    "libdvdnav"
    "libdvdread"
    "liblc3"
    "liblcevc-dec"
    "liboapv"
    "libqrencode"
    "libquirc"
    "libsvtav1"
    "libvvenc"
    "libxevd"
    "libxeve"
  ];
  unsupportedRockchipFlags = unsupportedRockchipLibFlags ++ [
    "vulkan"
    "whisper"
  ];

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

  ffmpegV4l2RequestPatches = [
    ../patches/ffmpeg-v4l2request/0001-h264-slice-bitsize.patch
    ../patches/ffmpeg-v4l2request/0002-hwdevice-v4l2request.patch
    ../patches/ffmpeg-v4l2request/0003-common-v4l2request.patch
    ../patches/ffmpeg-v4l2request/0004-probe-capable-devices.patch
    ../patches/ffmpeg-v4l2request/0005-common-decode-support.patch
    ../patches/ffmpeg-v4l2request/0006-mpeg2-v4l2request.patch
    ../patches/ffmpeg-v4l2request/0007-h264-v4l2request.patch
    ../patches/ffmpeg-v4l2request/0008-hevc-v4l2request.patch
    ../patches/ffmpeg-v4l2request/0009-ffmpeg8-v4l2-request-compat.patch
    ../patches/ffmpeg-v4l2request/0010-hevc-v4l2request-submit-ext-sps-rps.patch
  ];

  ffmpegRkmppPatches = [
    ../patches/ffmpeg-rkmpp/0001-rkmpp-retain-packets-on-decoder-backpressure.patch
    ../patches/ffmpeg-rkmpp/0002-rkmpp-export-rockchip-10-bit-as-nv15.patch
    ../patches/ffmpeg-rkmpp/0004-rkmpp-use-non-blocking-output-polling.patch
  ];

  mkV4l2RequestFfmpeg =
    ffmpegPkg:
    ffmpegPkg.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ ffmpegV4l2RequestPatches;
      configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-v4l2-request" ];
      buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.systemd ];
    });

  mkRkmppFfmpeg =
    ffmpegPkg:
    ffmpegPkg.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ ffmpegRkmppPatches;
      configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-rkmpp" ];
      buildInputs = (old.buildInputs or [ ]) ++ [ rockchipMpp ];
    });

  mkRockchipFfmpeg =
    ffmpegPkg:
    ffmpegPkg.overrideAttrs (old: {
      pname = "ffmpeg-rockchip";
      version = "unstable-2026-04-23";
      src = pkgs.fetchFromGitHub {
        owner = "nyanmisaka";
        repo = "ffmpeg-rockchip";
        rev = "40c412daccf08164493da0de990eb99a8948116b";
        hash = "sha256-EdQT2skG2VTLqxc9mvn/tOgNOPpkopYx79Hi8I6Nx9w=";
      };
      patches = lib.filter (p: !(lib.hasSuffix "lcevcdec-4.0.0-compat.patch" (toString p))) (old.patches or [ ]);
      configureFlags =
        (lib.filter
          (
            f:
            !(builtins.any (name: builtins.elem f [ "--enable-${name}" "--disable-${name}" ]) unsupportedRockchipFlags)
          )
          (old.configureFlags or [ ]))
        ++ [ "--enable-rkmpp" ];
      buildInputs = (old.buildInputs or [ ]) ++ [ rockchipMpp ];
    });

  mkRockchipV4l2RequestFfmpeg =
    ffmpegPkg:
    (mkRockchipFfmpeg ffmpegPkg).overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.systemd ];
      postPatch =
        (old.postPatch or "")
        + ''
          mkdir -p libavcodec/hevc
          cp libavcodec/hevcdec.c libavcodec/hevc/hevcdec.c

          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0001-h264-slice-bitsize.patch}
          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0002-hwdevice-v4l2request.patch} || true

          grep -q '    v4l2_request$' configure || \
            perl -0pi -e 's/(    rkmpp\n)/$1    v4l2_request\n/' configure
          grep -q 'hwcontext_v4l2request.h' libavutil/Makefile || \
            perl -0pi -e 's/(          hwcontext_opencl\.h[[:space:]]+\\\n)/$1          hwcontext_v4l2request.h                                       \\\n/' libavutil/Makefile
          grep -q 'AV_HWDEVICE_TYPE_V4L2REQUEST' libavutil/hwcontext.h || \
            perl -0pi -e 's/(    AV_HWDEVICE_TYPE_VULKAN,\n)/$1    AV_HWDEVICE_TYPE_V4L2REQUEST,\n/' libavutil/hwcontext.h
          grep -q 'ff_hwcontext_type_v4l2request' libavutil/hwcontext.c || \
            perl -0pi -e 's/(#if CONFIG_VULKAN\n    &ff_hwcontext_type_vulkan,\n#endif\n)/$1#if CONFIG_V4L2_REQUEST\n    \&ff_hwcontext_type_v4l2request,\n#endif\n/' libavutil/hwcontext.c

          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0003-common-v4l2request.patch} || true
          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0004-probe-capable-devices.patch}
          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0005-common-decode-support.patch} || true

          grep -q 'HWACCEL_V4L2REQUEST' libavcodec/hwconfig.h || \
            perl -0pi -e 's/(#define HWACCEL_D3D11VA\(codec\) \\\n    HW_CONFIG_HWACCEL\(0, 0, 1, D3D11VA_VLD,  NONE,         ff_ ## codec ## _d3d11va_hwaccel\)\n)/$1#define HWACCEL_V4L2REQUEST(codec) \\\n    HW_CONFIG_HWACCEL(1, 0, 0, DRM_PRIME,    V4L2REQUEST,  ff_ ## codec ## _v4l2request_hwaccel)\n/' libavcodec/hwconfig.h

          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0006-mpeg2-v4l2request.patch} || true
          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0007-h264-v4l2request.patch}
          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0008-hevc-v4l2request.patch}
          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0009-ffmpeg8-v4l2-request-compat.patch}
          patch --batch -p1 < ${../patches/ffmpeg-v4l2request/0010-hevc-v4l2request-submit-ext-sps-rps.patch}

          rm -f libavcodec/hevc/hevcdec.c
          rmdir --ignore-fail-on-non-empty libavcodec/hevc || true
          find . \( -name '*.orig' -o -name '*.rej' \) -delete
        '';
    });

  ffmpeg8V4l2Request = mkV4l2RequestFfmpeg pkgs.ffmpeg_8;
  ffmpeg8FullV4l2Request = mkV4l2RequestFfmpeg pkgs.ffmpeg_8-full;
  ffmpeg8Rkmpp = mkRkmppFfmpeg pkgs.ffmpeg_8;
  ffmpeg8FullRkmpp = mkRkmppFfmpeg pkgs.ffmpeg_8-full;
  ffmpeg8RkmppV4l2Request = mkRkmppFfmpeg ffmpeg8V4l2Request;
  ffmpeg8FullRkmppV4l2Request = mkRkmppFfmpeg ffmpeg8FullV4l2Request;
  ffmpeg8Rockchip = mkRockchipFfmpeg pkgs.ffmpeg_8;
  ffmpeg8FullRockchip = mkRockchipFfmpeg pkgs.ffmpeg_8-full;
  ffmpeg8RockchipV4l2Request = mkRockchipV4l2RequestFfmpeg pkgs.ffmpeg_8;
  ffmpeg8FullRockchipV4l2Request = mkRockchipV4l2RequestFfmpeg pkgs.ffmpeg_8-full;

  mpvUnwrappedV4l2Request = pkgs.mpv-unwrapped.override {
    ffmpeg = ffmpeg8FullV4l2Request;
  };
  mpvV4l2Request = (mpvUnwrappedV4l2Request.wrapper {
    mpv = mpvUnwrappedV4l2Request;
  }).overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      ffmpeg = ffmpeg8FullV4l2Request;
      unwrapped = mpvUnwrappedV4l2Request;
    };
  });

  mpvUnwrappedRockchip = pkgs.mpv-unwrapped.override {
    ffmpeg = ffmpeg8Rockchip;
  };
  mpvRockchip = (mpvUnwrappedRockchip.wrapper {
    mpv = mpvUnwrappedRockchip;
  }).overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      ffmpeg = ffmpeg8Rockchip;
      unwrapped = mpvUnwrappedRockchip;
    };
  });

  mkKodi22Variant =
    {
      baseName,
      ffmpegPkg,
      backendName,
      hasV4l2Request ? false,
      disableCecStandbyOnExit ? false,
    }:
    let
      basePkg = (builtins.getAttr baseName pkgs).override {
        ffmpeg = ffmpegPkg;
      };
      commonKodiPatches =
        [
          ../patches/kodi/0003-rock5c-prefer-rkmpp-drm-prime-decoders.patch
          ../patches/kodi/0004-rock5c-add-drm-prime-oes-finishing-path.patch
          ../patches/kodi/0005-rock5c-accept-p010-on-wayland-drm-prime.patch
        ]
        ++ lib.optionals disableCecStandbyOnExit [ ../patches/kodi/0002-rock5c-dont-send-cec-standby-on-exit.patch ];
      variantKodiPatches =
        lib.optionals (baseName == "kodi-gbm") [ ../patches/kodi/0001-rock5c-force-drm-prime-defaults-on-gbm.patch ]
        ++ lib.optionals (baseName == "kodi-wayland") [
          ../patches/kodi/0011-rock5c-force-drm-prime-decode-on-wayland.patch
          ../patches/kodi/0012-rock5c-include-winsystem-for-forced-drm-prime.patch
          ../patches/kodi/0013-rock5c-drop-const-winsystem-for-name-lookup.patch
        ]
        ++ lib.optionals hasV4l2Request [ ../patches/kodi/0000-rock5c-enable-v4l2request-drm-prime-codec.patch ]
        ++ commonKodiPatches;
    in
    basePkg.overrideAttrs (old: {
      version = "22.0a3";
      kodiReleaseName = "Piers";

      src = pkgs.fetchFromGitHub {
        owner = "xbmc";
        repo = "xbmc";
        rev = "22.0a3-Piers";
        hash = "sha256-z9MnqMvo2jChmogYOmVz4D42NLgGbmjL19/sRs1AZSI=";
      };

      patches = (old.patches or [ ]) ++ variantKodiPatches;
      buildInputs = (old.buildInputs or [ ]) ++ [
        libcrossguidWithPc
        pkgs.libsysprof-capture
        pkgs.pcre2
        pkgs.exiv2
        pkgs.libxslt.out
        pkgs.nlohmann_json
      ];
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.pkg-config ];
      cmakeFlags =
        lib.filter (flag: !(lib.hasPrefix "-DAPP_RENDER_SYSTEM=" flag)) (old.cmakeFlags or [ ])
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
        ffmpeg = ffmpegPkg;
        frontend = baseName;
        backend = backendName;
        providedSessions =
          if baseName == "kodi-gbm" then
            [ "kodi-gbm" ]
          else if baseName == "kodi-wayland" then
            [ "kodi-gbm" ]
          else if baseName == "kodi" then
            [ "kodi" ]
          else
            [ ];
      };
    });

  kodi22WaylandFfmpeg8RkmppV4l2Request = mkKodi22Variant {
    baseName = "kodi-wayland";
    ffmpegPkg = ffmpeg8FullRkmppV4l2Request;
    backendName = "ffmpeg8-rkmpp-v4l2request";
    hasV4l2Request = true;
  };
  kodi22X11Ffmpeg8RkmppV4l2Request = mkKodi22Variant {
    baseName = "kodi";
    ffmpegPkg = ffmpeg8FullRkmppV4l2Request;
    backendName = "ffmpeg8-rkmpp-v4l2request";
    hasV4l2Request = true;
  };
  kodi22GbmFfmpeg8RkmppV4l2Request = mkKodi22Variant {
    baseName = "kodi-gbm";
    ffmpegPkg = ffmpeg8FullRkmppV4l2Request;
    backendName = "ffmpeg8-rkmpp-v4l2request";
    hasV4l2Request = true;
  };

  kodi22WaylandFfmpeg8Rkmpp = mkKodi22Variant {
    baseName = "kodi-wayland";
    ffmpegPkg = ffmpeg8FullRkmpp;
    backendName = "ffmpeg8-rkmpp";
  };
  kodi22X11Ffmpeg8Rkmpp = mkKodi22Variant {
    baseName = "kodi";
    ffmpegPkg = ffmpeg8FullRkmpp;
    backendName = "ffmpeg8-rkmpp";
  };
  kodi22GbmFfmpeg8Rkmpp = mkKodi22Variant {
    baseName = "kodi-gbm";
    ffmpegPkg = ffmpeg8FullRkmpp;
    backendName = "ffmpeg8-rkmpp";
  };

  kodi22WaylandFfmpegRockchip = mkKodi22Variant {
    baseName = "kodi-wayland";
    ffmpegPkg = ffmpeg8FullRockchip;
    backendName = "ffmpeg-rockchip";
  };
  kodi22X11FfmpegRockchip = mkKodi22Variant {
    baseName = "kodi";
    ffmpegPkg = ffmpeg8FullRockchip;
    backendName = "ffmpeg-rockchip";
  };
  kodi22GbmFfmpegRockchip = mkKodi22Variant {
    baseName = "kodi-gbm";
    ffmpegPkg = ffmpeg8FullRockchip;
    backendName = "ffmpeg-rockchip";
  };

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
  ffmpeg_8-full-rkmpp = ffmpeg8FullRkmpp;
  ffmpeg_8-full-rkmpp-v4l2request = ffmpeg8FullRkmppV4l2Request;
  ffmpeg_8-full-rockchip = ffmpeg8FullRockchip;
  ffmpeg_8-full-rockchip-v4l2request = ffmpeg8FullRockchipV4l2Request;
  ffmpeg_8-full-v4l2request = ffmpeg8FullV4l2Request;
  ffmpeg_8-rkmpp = ffmpeg8Rkmpp;
  ffmpeg_8-rkmpp-v4l2request = ffmpeg8RkmppV4l2Request;
  ffmpeg_8-rockchip = ffmpeg8Rockchip;
  ffmpeg_8-rockchip-v4l2request = ffmpeg8RockchipV4l2Request;
  ffmpeg_8-v4l2request = ffmpeg8V4l2Request;
  flash-rock5c-emmc = flashRock5cEmmc;
  flash-rock5c-sd = flashRock5cSd;
  kodi_22-gbm-ffmpeg-rockchip = kodi22GbmFfmpegRockchip;
  kodi_22-gbm-ffmpeg8-rkmpp = kodi22GbmFfmpeg8Rkmpp;
  kodi_22-gbm-ffmpeg8-rkmpp-v4l2request = kodi22GbmFfmpeg8RkmppV4l2Request;
  kodi_22-wayland-ffmpeg-rockchip = kodi22WaylandFfmpegRockchip;
  kodi_22-wayland-ffmpeg8-rkmpp = kodi22WaylandFfmpeg8Rkmpp;
  kodi_22-wayland-ffmpeg8-rkmpp-v4l2request = kodi22WaylandFfmpeg8RkmppV4l2Request;
  kodi_22-x11-ffmpeg-rockchip = kodi22X11FfmpegRockchip;
  kodi_22-x11-ffmpeg8-rkmpp = kodi22X11Ffmpeg8Rkmpp;
  kodi_22-x11-ffmpeg8-rkmpp-v4l2request = kodi22X11Ffmpeg8RkmppV4l2Request;
  kodi_22_gbm_ffmpeg_rockchip = kodi22GbmFfmpegRockchip;
  kodi_22_gbm_ffmpeg8_rkmpp = kodi22GbmFfmpeg8Rkmpp;
  kodi_22_gbm_ffmpeg8_rkmpp_v4l2request = kodi22GbmFfmpeg8RkmppV4l2Request;
  kodi_22_wayland_ffmpeg_rockchip = kodi22WaylandFfmpegRockchip;
  kodi_22_wayland_ffmpeg8_rkmpp = kodi22WaylandFfmpeg8Rkmpp;
  kodi_22_wayland_ffmpeg8_rkmpp_v4l2request = kodi22WaylandFfmpeg8RkmppV4l2Request;
  kodi_22_x11_ffmpeg_rockchip = kodi22X11FfmpegRockchip;
  kodi_22_x11_ffmpeg8_rkmpp = kodi22X11Ffmpeg8Rkmpp;
  kodi_22_x11_ffmpeg8_rkmpp_v4l2request = kodi22X11Ffmpeg8RkmppV4l2Request;
  libcrossguid-with-pc = libcrossguidWithPc;
  libcrossguid_with_pc = libcrossguidWithPc;
  mali-g610-firmware = maliG610Firmware;
  mali_g610_firmware = maliG610Firmware;
  mpv_rockchip = mpvRockchip;
  mpv_v4l2request = mpvV4l2Request;
  provision-emmc = flashRock5cEmmc;
  provision-sd = flashRock5cSd;
  rock5c-flash-image = rock5cFlashImage;
  rockchip_mpp = rockchipMpp;
}
