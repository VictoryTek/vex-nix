{
  description = "NixOS configuration with flakes for nimda";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.vex-nix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix
        /etc/nixos/hardware-configuration.nix
      ];
    };
  };
}
