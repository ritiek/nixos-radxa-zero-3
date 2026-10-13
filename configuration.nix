# Minimal system for the SD image. Works on both the ZERO 3W and 3E.
{ lib, pkgs, ... }:

let
  # Optional WiFi network baked into the image. Read from the environment so
  # it never lands in git; needs `--impure`. The PSK ends up in the Nix store
  # and the image in plain text.
  ssid = builtins.getEnv "WIFI_SSID";
  psk = builtins.getEnv "WIFI_PSK";
in
{
  networking.hostName = "radxa-zero-3";
  networking.useDHCP = lib.mkDefault true;

  networking.wireless = {
    enable = true;
    networks = lib.optionalAttrs (ssid != "") { ${ssid}.psk = psk; };
    # Also read /etc/wpa_supplicant.conf, and allow `wpa_cli` to add networks.
    allowAuxiliaryImperativeNetworks = true;
    userControlled = true;
  };

  # SSH over the USB-C OTG port: give the host side 10.0.0.1/24.
  boot.kernelModules = [ "g_ether" ];
  networking.interfaces.usb0.ipv4.addresses = [{
    address = "10.0.0.2";
    prefixLength = 24;
  }];

  # radxa-zero-3.local
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  users.users.root.initialPassword = "nixos";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  zramSwap.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [ htop iw usbutils vim ];

  system.stateVersion = "26.05";
}
