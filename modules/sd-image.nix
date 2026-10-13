# Bootable SD card image: U-Boot in the gap before the first partition,
# extlinux on a btrfs root (U-Boot reads /boot from it).
{ config, lib, pkgs, modulesPath, ... }:

let
  inherit (import ../pkgs { inherit pkgs; }) uboot;
in
{
  imports = [ "${modulesPath}/installer/sd-card/sd-image.nix" ];

  # sd-image.nix turns on enableAllHardware, which pulls in linux-firmware
  # (~800MiB). Neither board loads anything from it; aic8800 firmware is
  # passed to the driver directly.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  fileSystems."/" = {
    fsType = lib.mkForce "btrfs";
    options = [ "noatime" "compress-force=zstd:3" ];
  };

  sdImage = {
    compressImage = lib.mkDefault false;
    # U-Boot lives at sector 64 up to 8MiB; the FAT partition is unused.
    firmwarePartitionOffset = 8;
    firmwareSize = 8;
    populateFirmwareCommands = "";
    rootFilesystemCreator = ./make-btrfs-fs.nix;
    # -g 0: emit only this system's boot entry. Otherwise the extlinux
    # builder copies the *build host's* other system generations into the
    # image.
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./files/boot -g 0
    '';
    postBuildCommands = ''
      sfdisk --part-type "$img" 1 DA
      dd if=${uboot}/u-boot-rockchip.bin of="$img" conv=fsync,notrunc bs=512 seek=64
    '';
  };

  # Upstream's version takes the partition number from the minor number
  # (wrong for mmcblk1) and runs resize2fs.
  systemd.services.expand-root-partition.script = lib.mkForce ''
    rootPart=$(${lib.getExe' pkgs.util-linux "findmnt"} -n -o SOURCE /)
    bootDevice=$(${lib.getExe' pkgs.util-linux "lsblk"} -npo PKNAME $rootPart)
    partNum=$(cat /sys/class/block/$(basename $rootPart)/partition)
    echo ",+," | ${lib.getExe' pkgs.util-linux "sfdisk"} -N$partNum --no-reread $bootDevice
    ${lib.getExe' pkgs.parted "partprobe"}
    ${lib.getExe' pkgs.btrfs-progs "btrfs"} filesystem resize max /
  '';
}
