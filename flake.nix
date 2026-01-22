{
  description = "NixOS configuration with flakes for VexHTPC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.vex-htpc = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        /etc/nixos/hardware-configuration.nix
      ];
    };
  };
}
