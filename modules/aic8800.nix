# AIC8800DS2 WiFi + Bluetooth on the Radxa ZERO 3W, set up the way Armbian
# does it (radxa-pkg/aic8800 SDIO driver + aic-bluetooth hciattach service).
# Everything here is skipped on the 3E (no module, uart1/sdmmc1 disabled).
{ config, lib, pkgs, ... }:

let
  src = pkgs.fetchFromGitHub {
    owner = "radxa-pkg";
    repo = "aic8800";
    rev = "d13d07963cd15d731e2895e8288a04cca6152ac9"; # 5.0+git20260123.5f7be68d-9
    hash = "sha256-7p3aa4gR622icOaSQKNtgp974f2ijGxa/l3I2+8RIYo=";
  };

  # Flat and uncompressed: the driver uses filp_open, not request_firmware.
  firmware = pkgs.stdenvNoCC.mkDerivation {
    pname = "aic8800-firmware";
    version = "5.0-unstable-2026-01-23";
    inherit src;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/lib/firmware/aic8800_fw/SDIO
      cp -r src/SDIO/driver_fw/fw/aic8800D80/* $out/lib/firmware/aic8800_fw/SDIO/
    '';
  };

  driver = config.boot.kernelPackages.callPackage ({ stdenv, kernel, patchutils }:
    stdenv.mkDerivation {
      pname = "aic8800-driver";
      version = "5.0-unstable-2026-01-23-${kernel.version}";
      inherit src;
      nativeBuildInputs = kernel.moduleBuildDependencies ++ [ patchutils ];
      hardeningDisable = [ "pic" ];

      # Debian's full series, SDIO parts only (some USB/PCIE hunks are CRLF and
      # don't apply with plain patch).
      patchPhase = ''
        runHook prePatch
        for p in $(grep -v '^#' debian/patches/series); do
          filterdiff -p1 -i 'src/SDIO/*' "debian/patches/$p" | patch -p1 --no-backup-if-mismatch
        done
        patch -p1 < ${./patches/aic8800-gpio-power.patch}
        runHook postPatch
      '';

      preBuild = "cd src/SDIO/driver_fw/driver/aic8800";

      buildPhase = ''
        runHook preBuild
        make KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
             ARCH=arm64 CROSS_COMPILE= modules
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/wireless/aic8800
        find . -name '*.ko' -exec cp {} $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/wireless/aic8800/ \;
        runHook postInstall
      '';
    }
  ) { };

  onlyOn3W.ConditionFirmware = "device-tree-compatible(radxa,zero-3w)";
in
{
  boot.extraModulePackages = [ driver ];
  boot.extraModprobeConfig = ''
    options aic8800_bsp aic_fw_path=${firmware}/lib/firmware/aic8800_fw/SDIO skip_power_wait=1
    options aic8800_fdrv aicwf_dbg_level=0 custregd=0 ps_on=0
  '';

  # Loaded here instead of boot.kernelModules so the 3E never loads it.
  # wpa_supplicant picks up wlan0 when it appears.
  systemd.services.aic8800 = {
    description = "Load AIC8800 WiFi/BT driver";
    unitConfig = onlyOn3W;
    wantedBy = [ "multi-user.target" ];
    before = [ "network-pre.target" ];
    wants = [ "network-pre.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.kmod}/bin/modprobe -a aic8800_bsp aic8800_fdrv aic8800_btlpm";
    };
  };

  hardware.wirelessRegulatoryDatabase = true;
  hardware.bluetooth.enable = true;

  # Port of Armbian's packages/bsp/aic8800/aic-bluetooth: BT is on uart1 (ttyS1).
  systemd.services.aic-bluetooth = {
    description = "AIC8800 Bluetooth (hciattach on ttyS1)";
    unitConfig = onlyOn3W;
    after = [ "bluetooth.service" "aic8800.service" ];
    requires = [ "bluetooth.service" "aic8800.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ bluez util-linux procps coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      rfkill unblock all
      hciattach -r -s 1500000 /dev/ttyS1 any 1500000 flow nosleep
      sleep .5
      pkill -f /dev/ttyS1 || true
      sleep .5
      hciattach -s 1500000 /dev/ttyS1 any 1500000 flow nosleep
      rfkill unblock all
    '';
  };

  # Cold-boot race: the firmware is still settling when wpa_supplicant first
  # associates, which then sits in a TEMP-DISABLED loop while the unit stays
  # active. A restart once the firmware has settled recovers it.
  systemd.services.wifi-watchdog = lib.mkIf config.networking.wireless.enable {
    description = "Restart wpa_supplicant until wlan0 gets a real IP (aic8800 cold-boot race)";
    unitConfig = onlyOn3W;
    after = [ "wpa_supplicant.service" "network.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ iproute2 systemd gnugrep coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      sleep 30
      for i in $(seq 1 6); do
        if ip -4 addr show wlan0 2>/dev/null | grep inet | grep -vq 'inet 169\.254\.'; then
          exit 0
        fi
        echo "wifi-watchdog: no IPv4 on wlan0, restarting wpa_supplicant ($i/6)"
        systemctl restart wpa_supplicant.service || true
        sleep 20
      done
      echo "wifi-watchdog: gave up"
    '';
  };
}
