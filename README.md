# NixOS for Radxa ZERO 3W / 3E

NixOS modules and a flashable SD card image for the Radxa ZERO 3W and ZERO 3E
(Rockchip RK3566). One image boots both boards.

The image runs the Rockchip BSP 6.1 kernel (Armbian's `rk-6.1-rkr7.2` tree and
kernel config), because mainline has no RK3566 video encoder, HEVC decoder or
NPU driver.

## Build the image

```bash
nix build .#sdImage
```

To have the 3W join a WiFi network on first boot, pass the credentials through
the environment (`--impure` is required for that):

```bash
WIFI_SSID="my-network" WIFI_PSK="my-password" nix build --impure .#sdImage
```

The credentials are never written to the repository, but they do end up in
plain text in the Nix store and inside the image. If you offload builds to a
remote builder, build the system without credentials first (see
[Remote builders](#remote-builders)).

Building needs an aarch64-linux machine or builder. The kernel takes about an
hour on two cores.

## Flash

```bash
sudo dd if=result/sd-image/nixos-image-sd-card-*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

On first boot the root partition and btrfs filesystem grow to fill the card.

Login: `root` / `nixos`. Change the password after first login.

Ways in:

- ZERO 3E: ethernet (DHCP).
- ZERO 3W: the WiFi network baked in at build time, or add one with
  `wpa_passphrase SSID PASSWORD >> /etc/wpa_supplicant.conf` and
  `systemctl restart wpa_supplicant`.
- Both: USB gadget ethernet on the USB-C OTG port. The board is `10.0.0.2`;
  give the host side `10.0.0.1/24`.
- Both: serial console on the debug UART (UART2, 1500000 baud, `ttyFIQ0`).
- mDNS: `ssh root@radxa-zero-3.local`.

## Use the modules in your own config

```nix
{
  inputs.radxa-zero-3.url = "github:ritiek/nixos-radxa-zero-3";

  outputs = { nixpkgs, radxa-zero-3, ... }: {
    nixosConfigurations.myboard = nixpkgs.lib.nixosSystem {
      modules = [
        radxa-zero-3.nixosModules.default # or just .radxa-zero-3 without the SD image parts
        ./configuration.nix
        { nixpkgs.hostPlatform = "aarch64-linux"; }
      ];
    };
  };
}
```

| Module | Contents |
|---|---|
| `radxa-zero-3` | Kernel, device tree overlays, AIC8800 WiFi/BT, VPU/RGA/NPU/GPU device access, `rk-top` |
| `sd-image` | SD image layout, U-Boot, btrfs root, first-boot resize |
| `default` | Both |

Extra packages under `packages.aarch64-linux`:

| Package | What |
|---|---|
| `sdImage` (default) | The SD card image |
| `kernel` | The vendor kernel |
| `uboot` | Mainline U-Boot with Rockchip BL31 and btrfs support |
| `rockchip-mpp`, `librga` | VPU and RGA userspace |
| `jellyfin-ffmpeg-rockchip` | jellyfin-ffmpeg with `rkmpp` decoders/encoders and `vpp_rkrga` |
| `librknnrt` | RKNN NPU runtime (v2.3.2) |

## How one image serves both boards

U-Boot reads the board ID from SARADC channel 1 and loads either
`rockchip/rk3566-radxa-zero-3w.dtb` or `rockchip/rk3566-radxa-zero-3e.dtb`.
Both files start from the same vendor `rk3566-radxa-zero3.dtb`; per-board
overlays then fix them up:

- 3W: ethernet off, root compatible `radxa,zero-3w`.
- 3E: WiFi SDIO and Bluetooth UART off, root compatible `radxa,zero-3e`.

The WiFi/BT services use `ConditionFirmware=device-tree-compatible(radxa,zero-3w)`,
so they never run on the 3E.

## Hardware status

| Feature | Status | Notes |
|---|---|---|
| Boot from SD (btrfs root) | Works | U-Boot 2026.04 with Rockchip BL31 |
| Ethernet (3E) | Works | |
| WiFi (3W, AIC8800DS2) | Works | Out-of-tree radxa-pkg driver. A watchdog restarts `wpa_supplicant` on the cold-boot association race |
| Bluetooth (3W) | Works | `hciattach` on `ttyS1` |
| USB gadget ethernet | Works | `g_ether` |
| GPU | Works | panfrost + Mesa, OpenCL via Rusticl |
| VPU (MPP) | Works | Use `jellyfin-ffmpeg-rockchip`; device nodes are in the `video` group |
| RGA | Works | `vpp_rkrga` in ffmpeg |
| NPU (RKNPU) | Works | Enabled by overlay; use `librknnrt` |
| Hardware watchdog | Works | systemd pets it, 360 s timeout |
| ZERO 3W with AP6212 WiFi (older revision) | Not supported | Needs the vendor `rk3566-radxa-zero3-ap6212.dtb` |

`sudo rk-top` shows live NPU, GPU, VPU, RGA and memory bus load.

## Known issues

- At SDR104 some SanDisk cards occasionally take longer than the 100 ms read
  timeout Linux asks for, which forces a card reset and can freeze the root
  filesystem. The kernel carries a patch that programs the controller's
  hardware maximum instead.
- Some cards fail the first SDR104 tuning and, after a warm reboot, fall back
  to 50 MHz high-speed mode. A cold power cycle restores SDR104.
- The boards have 1-8 GB of RAM; `zramSwap` is on in the example config.

## Remote builders

The image itself is cheap to build once the kernel exists. To keep WiFi
credentials off a remote builder, build the system without them remotely and
then build the image locally:

```bash
nix build .#nixosConfigurations.radxa-zero-3.config.system.build.toplevel --builders '...' -j0
WIFI_SSID=... WIFI_PSK=... nix build --impure .#sdImage -j auto --builders ''
```

## Credits

- [armbian/linux-rockchip](https://github.com/armbian/linux-rockchip) and Armbian's kernel config
- [radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800)
- [icefirex/nixos-radxa-zero3w](https://github.com/icefirex/nixos-radxa-zero3w) for the AIC8800 `skip_power_wait` patch (MIT)
- [nabam/nixos-rockchip](https://github.com/nabam/nixos-rockchip) for the SD image approach
- [nyanmisaka/rk-mirrors](https://github.com/nyanmisaka/rk-mirrors) for MPP and RGA
