{
  config,
  lib,
  ...
}:
let
  cfg = config.rock5c;
  mppDriverBits = {
    VDPU1 = 2;
    VEPU1 = 4;
    VDPU2 = 8;
    VEPU2 = 16;
    RKVDEC = 64;
    RKVENC = 128;
    IEP2 = 512;
    JPGDEC = 1024;
    RKVDEC2 = 2048;
    RKVENC2 = 4096;
    AV1DEC = 8192;
    VDPP = 16384;
    JPGENC = 32768;
  };
  mppDriverNames = builtins.attrNames mppDriverBits;
  mppMaskFromEnabledDrivers =
    names: lib.foldl' lib.bitOr 0 (map (name: mppDriverBits.${name}) names);
  mppMaskFromDisabledDrivers =
    names: mppMaskFromEnabledDrivers (lib.filter (name: !(builtins.elem name names)) mppDriverNames);
  effectiveMppDriverMask =
    if cfg.mpp.driverMask != null then
      cfg.mpp.driverMask
    else if cfg.mpp.disabledDrivers != [ ] then
      mppMaskFromDisabledDrivers cfg.mpp.disabledDrivers
    else
      null;
  kernelVersion = config.boot.kernelPackages.kernel.version;
  supportedKernelSeries = lib.versionAtLeast kernelVersion "6.19" && lib.versionOlder kernelVersion "6.20";
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.mpp.driverMask != null && cfg.videoBackend != "mpp");
          message = "rock5c.mpp.driverMask only applies when rock5c.videoBackend = \"mpp\".";
        }
        {
          assertion = !(cfg.mpp.disabledDrivers != [ ] && cfg.videoBackend != "mpp");
          message = "rock5c.mpp.disabledDrivers only applies when rock5c.videoBackend = \"mpp\".";
        }
        {
          assertion = !(cfg.mpp.driverMask != null && cfg.mpp.disabledDrivers != [ ]);
          message = "Use either rock5c.mpp.driverMask or rock5c.mpp.disabledDrivers, not both.";
        }
        {
          assertion = !(cfg.supportedKernelCheck.enable && cfg.videoBackend == "mpp" && !supportedKernelSeries);
          message = "rock5c.videoBackend = \"mpp\" currently supports Linux 6.19.x only. Disable rock5c.supportedKernelCheck.enable if you are carrying your own adapted kernel.";
        }
      ];
    }
    (lib.mkIf (cfg.enable && cfg.videoBackend == "mpp") {
      hardware.deviceTree.overlays = [
        {
          name = "rock5c-mpp-service";
          filter = "rockchip/rk3588s-rock-5c.dtb";
          dtsText = ''
            /dts-v1/;
            /plugin/;

            / {
              compatible = "radxa,rock-5c", "rockchip,rk3588s";
            };

            &{/} {
              mpp_srv: mpp-srv {
                compatible = "rockchip,mpp-service";
                rockchip,taskqueue-count = <12>;
                rockchip,resetgroup-count = <1>;
                status = "okay";
              };

              jpege_ccu: jpege-ccu {
                compatible = "rockchip,vpu-jpege-ccu";
                status = "okay";
              };

              rkvenc_ccu: rkvenc-ccu {
                compatible = "rockchip,rkv-encoder-v2-ccu";
                status = "okay";
              };

              rkvdec_ccu: rkvdec-ccu@fdc30000 {
                compatible = "rockchip,rkv-decoder-v2-ccu";
                reg = <0x0 0xfdc30000 0x0 0x100>;
                reg-names = "ccu";
                clocks = <&cru 383>;
                clock-names = "aclk_ccu";
                assigned-clocks = <&cru 383>;
                assigned-clock-rates = <600000000>;
                resets = <&cru 321>;
                reset-names = "video_ccu";
                rockchip,skip-pmu-idle-request;
                rockchip,ccu-mode = <1>;
                power-domains = <&power 14>;
                status = "okay";
              };

              vdpu: vdpu@fdb50400 {
                compatible = "rockchip,vpu-decoder-v2";
                reg = <0x0 0xfdb50400 0x0 0x400>;
                interrupts = <0 119 4 0>;
                interrupt-names = "irq_vdpu";
                clocks = <&cru 433>, <&cru 434>;
                clock-names = "aclk_vcodec", "hclk_vcodec";
                rockchip,normal-rates = <594000000>, <0>;
                assigned-clocks = <&cru 433>;
                assigned-clock-rates = <594000000>;
                resets = <&cru 353>, <&cru 354>;
                reset-names = "shared_video_a", "shared_video_h";
                rockchip,skip-pmu-idle-request;
                rockchip,disable-auto-freq;
                iommus = <&vpu121_mmu>;
                rockchip,srv = <&mpp_srv>;
                rockchip,taskqueue-node = <0>;
                rockchip,resetgroup-node = <0>;
                power-domains = <&power 21>;
                status = "okay";
              };

              jpegd: jpegd@fdb90000 {
                compatible = "rockchip,rkv-jpeg-decoder-v1";
                reg = <0x0 0xfdb90000 0x0 0x400>;
                interrupts = <0 129 4 0>;
                interrupt-names = "irq_jpegd";
                clocks = <&cru 421>, <&cru 422>;
                clock-names = "aclk_vcodec", "hclk_vcodec";
                rockchip,normal-rates = <600000000>, <0>;
                assigned-clocks = <&cru 421>;
                assigned-clock-rates = <600000000>;
                resets = <&cru 363>, <&cru 364>;
                reset-names = "video_a", "video_h";
                rockchip,skip-pmu-idle-request;
                iommus = <&jpegd_mmu>;
                rockchip,srv = <&mpp_srv>;
                rockchip,taskqueue-node = <1>;
                power-domains = <&power 21>;
                status = "okay";
              };

              jpegd_mmu: iommu@fdb90480 {
                compatible = "rockchip,rk3588-iommu", "rockchip,rk3568-iommu";
                reg = <0x0 0xfdb90480 0x0 0x40>;
                interrupts = <0 130 4 0>;
                interrupt-names = "irq_jpegd_mmu";
                clocks = <&cru 421>, <&cru 422>;
                clock-names = "aclk", "iface";
                power-domains = <&power 21>;
                #iommu-cells = <0>;
                status = "okay";
              };

              iep: iep@fdbb0000 {
                compatible = "rockchip,iep-v2";
                reg = <0x0 0xfdbb0000 0x0 0x500>;
                interrupts = <0 117 4 0>;
                interrupt-names = "irq_iep";
                clocks = <&cru 411>, <&cru 410>, <&cru 412>;
                clock-names = "aclk", "hclk", "sclk";
                rockchip,normal-rates = <594000000>, <0>;
                assigned-clocks = <&cru 411>;
                assigned-clock-rates = <594000000>;
                resets = <&cru 366>, <&cru 365>, <&cru 367>;
                reset-names = "rst_a", "rst_h", "rst_s";
                rockchip,skip-pmu-idle-request;
                rockchip,disable-auto-freq;
                power-domains = <&power 21>;
                rockchip,srv = <&mpp_srv>;
                rockchip,taskqueue-node = <6>;
                iommus = <&iep_mmu>;
                status = "okay";
              };

              iep_mmu: iommu@fdbb0800 {
                compatible = "rockchip,rk3588-iommu", "rockchip,rk3568-iommu";
                reg = <0x0 0xfdbb0800 0x0 0x100>;
                interrupts = <0 117 4 0>;
                interrupt-names = "irq_iep_mmu";
                clocks = <&cru 411>, <&cru 410>;
                clock-names = "aclk", "iface";
                #iommu-cells = <0>;
                power-domains = <&power 21>;
                status = "okay";
              };

              rkvenc0: rkvenc-core@fdbd0000 {
                compatible = "rockchip,rkv-encoder-v2-core";
                reg = <0x0 0xfdbd0000 0x0 0x6000>;
                interrupts = <0 101 4 0>;
                interrupt-names = "irq_rkvenc0";
                clocks = <&cru 438>, <&cru 437>, <&cru 439>;
                clock-names = "aclk_vcodec", "hclk_vcodec", "clk_core";
                rockchip,normal-rates = <500000000>, <0>, <800000000>;
                assigned-clocks = <&cru 438>, <&cru 439>;
                assigned-clock-rates = <500000000>, <800000000>;
                resets = <&cru 377>, <&cru 376>, <&cru 378>;
                reset-names = "video_a", "video_h", "video_core";
                rockchip,skip-pmu-idle-request;
                iommus = <&rkvenc0_mmu>;
                rockchip,srv = <&mpp_srv>;
                rockchip,ccu = <&rkvenc_ccu>;
                rockchip,taskqueue-node = <7>;
                rockchip,task-capacity = <8>;
                rockchip,rcb-iova = <0xFFD00000 0x100000>;
                power-domains = <&power 16>;
                operating-points-v2 = <&venc_opp_table>;
                status = "okay";
              };

              rkvenc0_mmu: iommu@fdbdf000 {
                compatible = "rockchip,rk3588-iommu", "rockchip,rk3568-iommu";
                reg = <0x0 0xfdbdf000 0x0 0x40>, <0x0 0xfdbdf040 0x0 0x40>;
                interrupts = <0 99 4 0>, <0 100 4 0>;
                interrupt-names = "irq_rkvenc0_mmu0", "irq_rkvenc0_mmu1";
                clocks = <&cru 438>, <&cru 437>;
                clock-names = "aclk", "iface";
                rockchip,disable-mmu-reset;
                rockchip,enable-cmd-retry;
                rockchip,shootdown-entire;
                #iommu-cells = <0>;
                power-domains = <&power 16>;
                status = "okay";
              };

              rkvenc1: rkvenc-core@fdbe0000 {
                compatible = "rockchip,rkv-encoder-v2-core";
                reg = <0x0 0xfdbe0000 0x0 0x6000>;
                interrupts = <0 104 4 0>;
                interrupt-names = "irq_rkvenc1";
                clocks = <&cru 443>, <&cru 442>, <&cru 444>;
                clock-names = "aclk_vcodec", "hclk_vcodec", "clk_core";
                rockchip,normal-rates = <500000000>, <0>, <800000000>;
                assigned-clocks = <&cru 443>, <&cru 444>;
                assigned-clock-rates = <500000000>, <800000000>;
                resets = <&cru 382>, <&cru 381>, <&cru 383>;
                reset-names = "video_a", "video_h", "video_core";
                rockchip,skip-pmu-idle-request;
                iommus = <&rkvenc1_mmu>;
                rockchip,srv = <&mpp_srv>;
                rockchip,ccu = <&rkvenc_ccu>;
                rockchip,taskqueue-node = <7>;
                rockchip,task-capacity = <8>;
                rockchip,rcb-iova = <0xFFC00000 0x100000>;
                power-domains = <&power 17>;
                operating-points-v2 = <&venc_opp_table>;
                status = "okay";
              };

              rkvenc1_mmu: iommu@fdbef000 {
                compatible = "rockchip,rk3588-iommu", "rockchip,rk3568-iommu";
                reg = <0x0 0xfdbef000 0x0 0x40>, <0x0 0xfdbef040 0x0 0x40>;
                interrupts = <0 102 4 0>, <0 103 4 0>;
                interrupt-names = "irq_rkvenc1_mmu0", "irq_rkvenc1_mmu1";
                clocks = <&cru 443>, <&cru 442>;
                clock-names = "aclk", "iface";
                rockchip,disable-mmu-reset;
                rockchip,enable-cmd-retry;
                rockchip,shootdown-entire;
                #iommu-cells = <0>;
                power-domains = <&power 17>;
                status = "okay";
              };

              rkvdec1: rkvdec-core@fdc48000 {
                compatible = "rockchip,rkv-decoder-v2";
                reg = <0x0 0xfdc48100 0x0 0x400>, <0x0 0xfdc48000 0x0 0x100>;
                reg-names = "regs", "link";
                interrupts = <0 97 4 0>;
                interrupt-names = "irq_rkvdec1";
                clocks = <&cru 390>, <&cru 389>, <&cru 393>, <&cru 391>, <&cru 392>;
                clock-names = "aclk_vcodec", "hclk_vcodec", "clk_core", "clk_cabac", "clk_hevc_cabac";
                rockchip,normal-rates = <800000000>, <0>, <600000000>, <600000000>, <1000000000>;
                assigned-clocks = <&cru 390>, <&cru 393>, <&cru 391>, <&cru 392>;
                assigned-clock-rates = <800000000>, <600000000>, <600000000>, <1000000000>;
                resets = <&cru 330>, <&cru 329>, <&cru 335>, <&cru 333>, <&cru 334>;
                reset-names = "video_a", "video_h", "video_core", "video_cabac", "video_hevc_cabac";
                rockchip,skip-pmu-idle-request;
                iommus = <&rkvdec1_mmu>;
                rockchip,srv = <&mpp_srv>;
                rockchip,ccu = <&rkvdec_ccu>;
                rockchip,core-mask = <0x00020002>;
                rockchip,task-capacity = <16>;
                rockchip,taskqueue-node = <9>;
                rockchip,sram = <&rkvdec1_sram>;
                rockchip,rcb-iova = <0xFFE00000 0x100000>;
                rockchip,rcb-info = <136 24576>, <137 49152>, <141 90112>, <140 49152>,
                                    <139 180224>, <133 49152>, <134 8192>, <135 4352>,
                                    <138 13056>, <142 291584>;
                rockchip,rcb-min-width = <512>;
                power-domains = <&power 15>;
                status = "okay";
              };

              rkvdec0: rkvdec-core@fdc38000 {
                compatible = "rockchip,rkv-decoder-v2";
                reg = <0x0 0xfdc38100 0x0 0x400>, <0x0 0xfdc38000 0x0 0x100>;
                reg-names = "regs", "link";
                interrupts = <0 95 4 0>;
                interrupt-names = "irq_rkvdec0";
                clocks = <&cru 385>, <&cru 384>, <&cru 388>, <&cru 386>, <&cru 387>;
                clock-names = "aclk_vcodec", "hclk_vcodec", "clk_core", "clk_cabac", "clk_hevc_cabac";
                rockchip,normal-rates = <800000000>, <0>, <600000000>, <600000000>, <1000000000>;
                assigned-clocks = <&cru 385>, <&cru 388>, <&cru 386>, <&cru 387>;
                assigned-clock-rates = <800000000>, <600000000>, <600000000>, <1000000000>;
                resets = <&cru 323>, <&cru 322>, <&cru 328>, <&cru 326>, <&cru 327>;
                reset-names = "video_a", "video_h", "video_core", "video_cabac", "video_hevc_cabac";
                rockchip,skip-pmu-idle-request;
                iommus = <&rkvdec0_mmu>;
                rockchip,srv = <&mpp_srv>;
                rockchip,ccu = <&rkvdec_ccu>;
                rockchip,core-mask = <0x00010001>;
                rockchip,task-capacity = <16>;
                rockchip,taskqueue-node = <9>;
                rockchip,sram = <&rkvdec0_sram>;
                rockchip,rcb-iova = <0xFFF00000 0x100000>;
                rockchip,rcb-info = <136 24576>, <137 49152>, <141 90112>, <140 49152>,
                                    <139 180224>, <133 49152>, <134 8192>, <135 4352>,
                                    <138 13056>, <142 291584>;
                rockchip,rcb-min-width = <512>;
                power-domains = <&power 14>;
                status = "okay";
              };

              rkvdec0_mmu: iommu@fdc38700 {
                compatible = "rockchip,iommu-v2";
                reg = <0x0 0xfdc38700 0x0 0x40>, <0x0 0xfdc38740 0x0 0x40>;
                interrupts = <0 96 4 0>;
                interrupt-names = "irq_rkvdec0_mmu";
                clocks = <&cru 385>, <&cru 384>;
                clock-names = "aclk", "iface";
                rockchip,skip-mmu-read;
                rockchip,disable-mmu-reset;
                rockchip,enable-cmd-retry;
                rockchip,shootdown-entire;
                rockchip,master-handle-irq;
                #iommu-cells = <0>;
                power-domains = <&power 14>;
                status = "okay";
              };

              rkvdec1_mmu: iommu@fdc48700 {
                compatible = "rockchip,iommu-v2";
                reg = <0x0 0xfdc48700 0x0 0x40>, <0x0 0xfdc48740 0x0 0x40>;
                interrupts = <0 98 4 0>;
                interrupt-names = "irq_rkvdec1_mmu";
                clocks = <&cru 390>, <&cru 389>;
                clock-names = "aclk", "iface";
                rockchip,skip-mmu-read;
                rockchip,disable-mmu-reset;
                rockchip,enable-cmd-retry;
                rockchip,shootdown-entire;
                rockchip,master-handle-irq;
                #iommu-cells = <0>;
                power-domains = <&power 15>;
                status = "okay";
              };

              av1d_mmu: iommu@fdca0000 {
                compatible = "rockchip,rk3588-iommu", "rockchip,rk3568-iommu";
                reg = <0x0 0xfdca0000 0x0 0x600>;
                interrupts = <0 109 4 0>;
                interrupt-names = "irq_av1d_mmu";
                clocks = <&cru 65>, <&cru 67>;
                clock-names = "aclk", "iface";
                #iommu-cells = <0>;
                power-domains = <&power 23>;
                status = "okay";
              };

              venc_opp_table: venc-opp-table {
                compatible = "operating-points-v2";
                nvmem-cells = <&codec_leakage>, <&venc_opp_info>;
                nvmem-cell-names = "leakage", "opp-info";
                rockchip,leakage-voltage-sel = <
                  1 15 0
                  16 25 1
                  26 254 2
                >;
                rockchip,grf = <&sys_grf>;
                volt-mem-read-margin = <
                  855000 1
                  765000 2
                  675000 3
                  495000 4
                >;

                opp-800000000 {
                  opp-hz = /bits/ 64 <800000000>;
                  opp-microvolt = <750000 750000 850000>, <750000 750000 850000>;
                  opp-microvolt-L0 = <800000 800000 850000>, <800000 800000 850000>;
                  opp-microvolt-L1 = <775000 775000 850000>, <775000 775000 850000>;
                  opp-microvolt-L2 = <750000 750000 850000>, <750000 750000 850000>;
                };
              };
            };

            &system_sram2 {
              rkvdec0_sram: rkvdec-sram@0 {
                reg = <0x0 0x78000>;
              };

              rkvdec1_sram: rkvdec-sram@78000 {
                reg = <0x78000 0x77000>;
              };
            };

            &{/aliases} {
              vdpu = "/vdpu@fdb50400";
              jpege0 = "/video-codec@fdba0000";
              jpege1 = "/video-codec@fdba4000";
              jpege2 = "/video-codec@fdba8000";
              jpege3 = "/video-codec@fdbac000";
              rkvdec0 = "/rkvdec-core@fdc38000";
              rkvdec1 = "/rkvdec-core@fdc48000";
              rkvenc0 = "/rkvenc-core@fdbd0000";
              rkvenc1 = "/rkvenc-core@fdbe0000";
            };

            &{/video-codec@fdba0000} {
              compatible = "rockchip,vpu-jpege-core";
              reg = <0x0 0xfdba0000 0x0 0x400>;
              interrupt-names = "irq_jpege0";
              clock-names = "aclk_vcodec", "hclk_vcodec";
              rockchip,normal-rates = <594000000>, <0>;
              assigned-clocks = <&cru 413>;
              assigned-clock-rates = <594000000>;
              resets = <&cru 355>, <&cru 356>;
              reset-names = "video_a", "video_h";
              rockchip,skip-pmu-idle-request;
              rockchip,disable-auto-freq;
              rockchip,srv = <&mpp_srv>;
              rockchip,taskqueue-node = <2>;
              rockchip,ccu = <&jpege_ccu>;
              status = "okay";
            };

            &{/video-codec@fdba4000} {
              compatible = "rockchip,vpu-jpege-core";
              reg = <0x0 0xfdba4000 0x0 0x400>;
              interrupt-names = "irq_jpege1";
              clock-names = "aclk_vcodec", "hclk_vcodec";
              rockchip,normal-rates = <594000000>, <0>;
              assigned-clocks = <&cru 415>;
              assigned-clock-rates = <594000000>;
              resets = <&cru 357>, <&cru 358>;
              reset-names = "video_a", "video_h";
              rockchip,skip-pmu-idle-request;
              rockchip,disable-auto-freq;
              rockchip,srv = <&mpp_srv>;
              rockchip,taskqueue-node = <2>;
              rockchip,ccu = <&jpege_ccu>;
              status = "okay";
            };

            &{/video-codec@fdba8000} {
              compatible = "rockchip,vpu-jpege-core";
              reg = <0x0 0xfdba8000 0x0 0x400>;
              interrupt-names = "irq_jpege2";
              clock-names = "aclk_vcodec", "hclk_vcodec";
              rockchip,normal-rates = <594000000>, <0>;
              assigned-clocks = <&cru 417>;
              assigned-clock-rates = <594000000>;
              resets = <&cru 359>, <&cru 360>;
              reset-names = "video_a", "video_h";
              rockchip,skip-pmu-idle-request;
              rockchip,disable-auto-freq;
              rockchip,srv = <&mpp_srv>;
              rockchip,taskqueue-node = <2>;
              rockchip,ccu = <&jpege_ccu>;
              status = "okay";
            };

            &{/video-codec@fdbac000} {
              compatible = "rockchip,vpu-jpege-core";
              reg = <0x0 0xfdbac000 0x0 0x400>;
              interrupt-names = "irq_jpege3";
              clock-names = "aclk_vcodec", "hclk_vcodec";
              rockchip,normal-rates = <594000000>, <0>;
              assigned-clocks = <&cru 419>;
              assigned-clock-rates = <594000000>;
              resets = <&cru 361>, <&cru 362>;
              reset-names = "video_a", "video_h";
              rockchip,skip-pmu-idle-request;
              rockchip,disable-auto-freq;
              rockchip,srv = <&mpp_srv>;
              rockchip,taskqueue-node = <2>;
              rockchip,ccu = <&jpege_ccu>;
              status = "okay";
            };

            &{/video-codec@fdc70000} {
              compatible = "rockchip,av1-decoder";
              reg = <0x0 0xfdc70000 0x0 0x800>, <0x0 0xfdc80000 0x0 0x400>,
                    <0x0 0xfdc90000 0x0 0x400>;
              reg-names = "vcd", "cache", "afbc";
              interrupts = <0 108 4 0>, <0 107 4 0>, <0 106 4 0>;
              interrupt-names = "irq_av1d", "irq_cache", "irq_afbc";
              clock-names = "aclk_vcodec", "hclk_vcodec";
              rockchip,normal-rates = <400000000>, <400000000>;
              assigned-clocks = <&cru 65>, <&cru 67>;
              assigned-clock-rates = <400000000>, <400000000>;
              resets = <&cru 510>, <&cru 512>;
              reset-names = "video_a", "video_h";
              iommus = <&av1d_mmu>;
              rockchip,srv = <&mpp_srv>;
              rockchip,taskqueue-node = <11>;
              power-domains = <&power 23>;
              status = "okay";
            };

            &{/efuse@fecc0000} {
              venc_opp_info: venc-opp-info@67 {
                reg = <0x67 0x6>;
              };
            };


            &{/video-codec@fdb50000} {
              status = "disabled";
            };

          '';
        }
      ];

      boot.blacklistedKernelModules = lib.optionals (cfg.videoBackend == "mpp") [
        "rockchip_vdec"
        "hantro_vpu"
      ];

      assertions = [
        {
          assertion = !(cfg.mpp.driverMask != null && cfg.videoBackend != "mpp");
          message = "rock5c.mpp.driverMask only applies when rock5c.videoBackend = \"mpp\".";
        }
        {
          assertion = !(cfg.mpp.disabledDrivers != [ ] && cfg.videoBackend != "mpp");
          message = "rock5c.mpp.disabledDrivers only applies when rock5c.videoBackend = \"mpp\".";
        }
        {
          assertion = !(cfg.mpp.driverMask != null && cfg.mpp.disabledDrivers != [ ]);
          message = "Use either rock5c.mpp.driverMask or rock5c.mpp.disabledDrivers, not both.";
        }
        {
          assertion = !(cfg.supportedKernelCheck.enable && cfg.videoBackend == "mpp" && !supportedKernelSeries);
          message = "rock5c.videoBackend = \"mpp\" currently supports Linux 6.19.x only. Disable rock5c.supportedKernelCheck.enable if you are carrying your own adapted kernel.";
        }
      ];

      boot.extraModprobeConfig = lib.mkIf (cfg.videoBackend == "mpp" && effectiveMppDriverMask != null) ''
        options rk_vcodec mpp_driver_mask=${toString effectiveMppDriverMask}
      '';

      # The MPP stack is now stable enough to autoload for the MPP backend.
      # Kodi/libmpp expects /dev/mpp_service to exist before attempting RKMPP
      # init; leaving rk_vcodec manual-load only causes silent fallback to the
      # software HEVC decoder when the device node is absent.
      boot.kernelModules = lib.optionals (cfg.videoBackend == "mpp") [ "rk_vcodec" ];

      boot.kernelPatches = [
        {
          name = "device-mapper-debug";
          patch = null;
          structuredExtraConfig = {
            DM_DEBUG = lib.kernel.yes;
          };
        }
        {
          name = "zram-memory-tracking";
          patch = null;
          structuredExtraConfig = {
            ZRAM_MEMORY_TRACKING = lib.kernel.yes;
          };
        }
      ] ++ lib.optionals (cfg.videoBackend == "mpp") [
        {
          name = "rock5c-mpp-video-kconfig";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            VIDEO_ROCKCHIP_VDEC = no;
            VIDEO_HANTRO = no;
            ROCKCHIP_MPP_SERVICE = module;
            ROCKCHIP_MPP_PROC_FS = yes;
            ROCKCHIP_MPP_RKVDEC = yes;
            ROCKCHIP_MPP_RKVDEC2 = yes;
            ROCKCHIP_MPP_RKVENC = yes;
            ROCKCHIP_MPP_RKVENC2 = yes;
            ROCKCHIP_MPP_VDPU1 = yes;
            ROCKCHIP_MPP_VDPU2 = yes;
            ROCKCHIP_MPP_VEPU1 = yes;
            ROCKCHIP_MPP_VEPU2 = yes;
            ROCKCHIP_MPP_IEP2 = yes;
            ROCKCHIP_MPP_JPGDEC = yes;
            ROCKCHIP_MPP_JPGENC = yes;
            ROCKCHIP_MPP_AV1DEC = yes;
            ROCKCHIP_MPP_VDPP = yes;
            PSTORE = yes;
            PSTORE_CONSOLE = yes;
            PSTORE_PMSG = yes;
            PSTORE_RAM = yes;
          };
        }
        {
          name = "rockchip-mpp-6.19.7";
          patch = ../patches/mpp-kernel/rockchip-mpp-6.19.7.patch;
        }
        {
          name = "rockchip-pmu-mpp-compat";
          patch = ../patches/mpp-kernel/rockchip-pmu-mpp-compat.patch;
        }
        {
          name = "rockchip-iommu-mpp-compat";
          patch = ../patches/mpp-kernel/rockchip-iommu-mpp-compat.patch;
        }
        {
          name = "rockchip-mpp-iommu-fault-hook";
          patch = ../patches/mpp-kernel/rockchip-mpp-iommu-fault-hook.patch;
        }
        {
          name = "rockchip-mpp-legacy-vpu-ioctl-compat";
          patch = ../patches/mpp-kernel/rockchip-mpp-legacy-vpu-ioctl-compat.patch;
        }
        {
          name = "rockchip-mpp-legacy-vpu-reg-ioctl-compat";
          patch = ../patches/mpp-kernel/rockchip-mpp-legacy-vpu-reg-ioctl-compat.patch;
        }
        {
          name = "rockchip-mpp-iommu-cookie-layout";
          patch = ../patches/mpp-kernel/rockchip-mpp-iommu-cookie-layout.patch;
        }
        {
          name = "rockchip-mpp-rkvdec2-reserve-rcb-iova";
          patch = ../patches/mpp-kernel/rockchip-mpp-rkvdec2-reserve-rcb-iova.patch;
        }
        {
          name = "rockchip-mpp-probe-cleanup";
          patch = ../patches/mpp-kernel/rockchip-mpp-probe-cleanup.patch;
        }
        {
          name = "rockchip-mpp-driver-mask";
          patch = ../patches/mpp-kernel/rockchip-mpp-driver-mask.patch;
        }
        {
          name = "rockchip-mpp-rkvdec2-ccu-defer";
          patch = ../patches/mpp-kernel/rockchip-mpp-rkvdec2-ccu-defer.patch;
        }
      ];

    })
  ];
}
