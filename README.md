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
