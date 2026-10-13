{
  description = "NixOS for Radxa ZERO 3W / 3E (RK3566) on the Rockchip vendor kernel";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }: {
    nixosModules = {
      # Kernel, device tree, WiFi/BT, VPU/RGA/NPU/GPU access.
      radxa-zero-3 = ./modules/radxa-zero-3.nix;
      # SD card image with U-Boot and a btrfs root.
      sd-image = ./modules/sd-image.nix;
      default.imports = [ self.nixosModules.radxa-zero-3 self.nixosModules.sd-image ];
    };

    nixosConfigurations.radxa-zero-3 = nixpkgs.lib.nixosSystem {
      modules = [
        self.nixosModules.default
        ./configuration.nix
        { nixpkgs.hostPlatform = "aarch64-linux"; }
      ];
    };

    packages.aarch64-linux = let
      config = self.nixosConfigurations.radxa-zero-3.config;
    in import ./pkgs { pkgs = nixpkgs.legacyPackages.aarch64-linux; } // {
      default = config.system.build.sdImage;
      sdImage = config.system.build.sdImage;
      kernel = config.boot.kernelPackages.kernel;
    };
  };
}
