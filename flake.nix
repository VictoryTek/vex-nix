{
  description = "VexOS - NixOS configurations for desktop, HTPC, and server variants";

  inputs = {
    # NixOS stable channel
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    
    # Unstable for bleeding-edge packages when needed
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # CachyOS kernel
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, chaotic, ... }@inputs:
    let
      # Supported systems
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      
      # Helper to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      # Common specialArgs passed to all configurations
      mkSpecialArgs = system: {
        inherit inputs;
        # Access to unstable packages when needed
        pkgs-unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
      
      # Helper function to create NixOS configurations
      mkHost = { hostname, system ? "x86_64-linux", variant }: 
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = mkSpecialArgs system;
          modules = [
            # CachyOS kernel module
            chaotic.nixosModules.default
            
            # Host-specific configuration
            ./hosts/${hostname}
            
            # Set the hostname
            { networking.hostName = hostname; }
          ];
        };
    in
    {
      # NixOS configurations for each variant
      nixosConfigurations = {
        # Desktop variant (main workstation)
        vex-os = mkHost {
          hostname = "vex-os";
          variant = "desktop";
        };
        
        # HTPC variant (home theater PC)
        vex-htpc = mkHost {
          hostname = "vex-htpc";
          variant = "htpc";
        };
        
        # Server variant
        vex-svr = mkHost {
          hostname = "vex-svr";
          variant = "server";
        };
        
        # Virtual Machine variant (auto-detects QEMU, VirtualBox, VMware, Hyper-V)
        vex-vm = mkHost {
          hostname = "vex-vm";
          variant = "vm";
        };
      };
      
      # Development shells for working on this flake
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nil           # Nix LSP
              nixfmt-rfc-style  # Nix formatter
            ];
          };
        }
      );
    };
}
