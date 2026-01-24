{
  description = "NixOS configuration with flakes for VexHTPC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, ... }@inputs: 
    let
      system = "x86_64-linux";
      baseModules = [
        ./configuration.nix
        ./hardware-configuration.nix
      ];
    in
    {
      nixosConfigurations = {
        # Intel GPU variant (default)
        vex-htpc = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = baseModules ++ [ ./modules/system/intel-acceleration.nix ];
        };
        
        # Intel GPU variant (explicit)
        vex-htpc-intel = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = baseModules ++ [ ./modules/system/intel-acceleration.nix ];
        };
        
        # AMD GPU variant
        vex-htpc-amd = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = baseModules ++ [ ./modules/system/amd-acceleration.nix ];
        };
        
        # NVIDIA GPU variant
        vex-htpc-nvidia = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = baseModules ++ [ ./modules/system/nvidia-acceleration.nix ];
        };
        
        # No GPU acceleration (fallback)
        vex-htpc-basic = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = baseModules;
        };
      };
    };
}
