# rock5c-nixos

Nix flake support for running NixOS on the Radxa ROCK 5C.

This repository is a reusable module and package set. It does not define a
complete `nixosConfigurations` target by itself; instead, import its NixOS
modules from your own system flake and build the resulting system or image
there.

## What is included

- ROCK 5C board defaults:
  - `aarch64-linux` host platform
  - U-Boot firmware from `pkgs.ubootRock5ModelC`
  - generic extlinux boot configuration
  - ROCK 5C device-tree overlays for HDMI audio, HDMI CEC, and ramoops/pstore
- SD-card image construction for `config.system.build.sdImage`
- Rockchip media packages and kernel support:
  - patched `rockchip_mpp`
  - FFmpeg 8 with RKMPP support
  - Kodi 22 Wayland build with ROCK 5C RKMPP and Dolby Vision patches
  - optional mainline `rkvdec` backports
  - optional vendor-style MPP device-tree/kernel patch path
- AIC8800 Wi-Fi/Bluetooth support
- CPU stall and RCU debug/recovery options
- optional Hyprland/Kodi session helpers
- flash helpers for SD and eMMC images

## Flake outputs

Useful exported outputs:

- `nixosModules.default`: import this in most ROCK 5C systems. It composes the
  board defaults, AIC8800 support, CPU-stall helpers, Kodi/media helpers,
  flash tools, and video-backend modules behind the `rock5c.*` option tree.
- `nixosModules.rock5c`: defines the shared `rock5c.*` options. Use it only
  when composing a custom subset of the modules yourself.
- `nixosModules.rock5c-base`: minimal board/image support. It selects the
  `aarch64-linux` host platform, U-Boot/extlinux boot path, device-tree
  overlays, firmware, and `sdImage` builder.
- `nixosModules.rock5c-aic8800`: enables the AIC8800 Wi-Fi/Bluetooth driver
  stack and optional stable WLAN MAC handling.
- `nixosModules.rock5c-cpu-stalls`: adds kernel parameters, sysctls, pstore,
  dynamic-debug, tracefs, and cpuidle controls for diagnosing or recovering
  from CPU lockups and RCU stalls.
- `nixosModules.rock5c-flash-tools`: installs `rock5c-flash-image`,
  `flash-rock5c-sd`, and `flash-rock5c-emmc` into the target system.
- `nixosModules.rock5c-gstreamer-hwdec`: installs GStreamer stateless decode
  tools for testing mainline V4L2/media hardware decode paths.
- `nixosModules.rock5c-hyprland-session`: configures a ROCK 5C Hyprland/greetd
  session suitable for launching the media stack.
- `nixosModules.rock5c-kodi`: installs the ROCK 5C Kodi/media packages and
  optional Kodi autostart service.
- `nixosModules.rock5c-rkvdec`: applies Collabora RK3588 `rkvdec` kernel
  backports and enables the `rockchip_vdec` module for the mainline video path.
- `homeManagerModules.default`: provides the user-side Hyprland config shim for
  systems that enable the ROCK 5C Hyprland session.
- `homeManagerModules.rock5c-hyprland`: imports just the user-side Hyprland
  config shim, useful when composing Home Manager modules explicitly.
- `overlays.default`: exposes this repository's package overrides through
  `pkgs`, which is useful when you want `pkgs.rockchip_mpp`,
  `pkgs.ffmpeg_8-full-rkmpp`, `pkgs.kodi_22`, or the flash tools outside the
  bundled NixOS modules.
- `formatter.${system}`: the repository's Nix formatter, useful for keeping
  local edits in the same style with `nix fmt`.
- `packages.${system}.ffmpeg_8-full-rkmpp`: FFmpeg 8 with Rockchip MPP support
  and ROCK 5C-specific RKMPP patches; useful for hardware decode testing and
  media tooling.
- `packages.${system}.flash-rock5c-emmc`: convenience wrapper that runs
  `rock5c-flash-image --target-type emmc`.
- `packages.${system}.flash-rock5c-sd`: convenience wrapper that runs
  `rock5c-flash-image --target-type sd`.
- `packages.${system}.kodi_22`: Kodi 22 Wayland build with RKMPP, DRM PRIME,
  and ROCK 5C media patches; useful for a dedicated media-center setup.
- `packages.${system}.libcrossguid-with-pc`: `libcrossguid` with pkg-config
  metadata, useful as a Kodi build dependency.
- `packages.${system}.mali-g610-firmware`: firmware blob package for the
  ROCK 5C Mali G610 GPU.
- `packages.${system}.rock5c-flash-image`: the underlying image flashing tool
  that can build or write ROCK 5C images, grow the root filesystem, and copy
  selected files into the flashed image.
- `packages.${system}.rockchip_mpp`: patched Rockchip MPP userspace library,
  used by the RKMPP FFmpeg/Kodi stack and useful for direct MPP development.
- `checks.${system}.eval-images`: evaluates a minimal ROCK 5C system and
  confirms the SD-image outputs are present.
- `checks.${system}.eval-mpp`: evaluates a ROCK 5C system with
  `rock5c.videoBackend = "mpp"` to catch option and kernel-patch regressions.
- `checks.${system}.eval-aic8800-stable-mac`: evaluates AIC8800 stable-MAC
  configuration, useful for guarding the Wi-Fi/Bluetooth option path.
- `checks.${system}.eval-cpu-stalls`: evaluates the CPU-stall diagnostics
  option set, useful for catching regressions in the debug/recovery module.
- `checks.${system}.rockchip-mpp`: builds the patched MPP userspace library,
  useful as a focused package-level verification target.

Inspect the full flake surface with:

```sh
nix flake show
```

## Minimal consuming flake

Create a system flake that imports this repository and enables the ROCK 5C
module. The example below assumes this repository is available as a flake input
named `rock5c-nixos`.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    rock5c-nixos.url = "github:johnrichardrinehart/rock5c-nixos";
  };

  outputs =
    { nixpkgs, rock5c-nixos, ... }:
    {
      nixosConfigurations.rock5c = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          rock5c-nixos.nixosModules.default
          {
            rock5c.enable = true;

            fileSystems."/" = {
              device = "/dev/disk/by-label/NIXOS_SD";
              fsType = "ext4";
            };

            system.stateVersion = "25.11";
          }
        ];
      };
    };
}
```

For local development, replace the input URL with a path:

```nix
rock5c-nixos.url = "path:/path/to/rock5c-nixos";
```

## Build an SD image

From the consuming flake, build the ROCK 5C SD image:

```sh
nix build .#nixosConfigurations.rock5c.config.system.build.sdImage
```

The build result is an image file symlinked at `./result`.

The module also wires the image into NixOS image modules, so consumers that use
the newer image interface can build:

```sh
nix build .#nixosConfigurations.rock5c.config.system.build.images.sdImage
```

Cross-building from `x86_64-linux` to `aarch64-linux` requires a working Nix
cross or remote-builder setup. Native `aarch64-linux` builds can build the image
directly.

## Flash an SD card

The flake provides wrappers around `rock5c-flash-image`:

```sh
nix run github:johnrichardrinehart/rock5c-nixos#flash-rock5c-sd -- \
  --image ./result \
  --device /dev/mmcblkX
```

The flash tool must run as root because it writes a block device:

```sh
sudo nix run github:johnrichardrinehart/rock5c-nixos#flash-rock5c-sd -- \
  --image ./result \
  --device /dev/mmcblkX
```

If `--image` is omitted, the flash tool builds:

```text
.#nixosConfigurations.<config>.config.system.build.sdImage
```

The default configuration name is `rock5c`; override it with `--config NAME`.
When `--device` is omitted, the tool tries to infer the SD or eMMC device from
`/sys/block/mmcblk*/device/type`. It refuses to overwrite the disk backing the
current root filesystem and refuses mounted targets.

For eMMC, use:

```sh
sudo nix run github:johnrichardrinehart/rock5c-nixos#flash-rock5c-emmc -- \
  --config rock5c
```

Note that the current repository defines the SD-image builder. The flash script
also has an eMMC path, but a consuming configuration must provide
`config.system.build.eMMCImage` for that path to build without `--image`.

## Common module options

Enable the base board support:

```nix
rock5c.enable = true;
```

Select the video stack:

```nix
rock5c.videoBackend = "mainline"; # default
rock5c.videoBackend = "mpp";
```

Use the mainline/stateless rkvdec backports:

```nix
rock5c.rkvdec.enable = true;
```

Use the vendor-style MPP path:

```nix
rock5c.videoBackend = "mpp";
rock5c.mpp.disabledDrivers = [ "RKVDEC2" ];
```

Enable AIC8800 support:

```nix
rock5c.aic8800.enable = true;
rock5c.aic8800.stableMac = {
  enable = true;
  address = "02:00:00:00:00:01";
};
```

Enable media packages and Kodi helpers:

```nix
rock5c.media = {
  enable = true;
  kodi.autostart.enable = true;
  kodi.disableCecStandbyOnExit = true;
};
```

Enable the ROCK 5C flash helpers in the target system:

```nix
rock5c.enable = true;
# included by nixosModules.default:
# environment.systemPackages includes rock5c-flash-image, flash-rock5c-sd,
# and flash-rock5c-emmc when rock5c.enable is true.
```

## Development

Format Nix files:

```sh
nix fmt
```

Evaluate the module checks:

```sh
nix flake check
```

Run a focused image evaluation check:

```sh
nix build .#checks.x86_64-linux.eval-images --no-link
```

Build exported packages directly, for example:

```sh
nix build .#rockchip_mpp
nix build .#ffmpeg_8-full-rkmpp
nix build .#kodi_22
```
