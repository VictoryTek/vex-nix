{
  description = "VexOS - Personal NixOS Configuration with GNOME";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Flatpak management
    # Provides: nixosModules.nix-flatpak, homeManagerModules.nix-flatpak
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # CachyOS kernels for NixOS
    # Provides: overlays.default (pkgs.cachyosKernels.*)
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      # Do NOT override nixpkgs — kernel patches depend on nix-cachyos-kernel's nixpkgs
    };

    # Up — modern Linux system update & upgrade GUI (GTK4 + libadwaita)
    # Provides: packages.${system}.default
    up = {
      url = "github:VictoryTek/Up";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # TODO: Uncomment when the vex-kernels repo is ready.
    # Bazzite and custom kernels for NixOS.
    # Provides: overlays.default (pkgs.vexKernels.*)
    # vex-kernels = {
    #   url = "github:<owner>/vex-kernels";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, home-manager, nix-flatpak, ... }@inputs:
  let
    # ── lib.mkVexosSystem ──────────────────────────────────────────────
    # Builds a complete VexOS NixOS system configuration.
    #
    # Arguments:
    #   hardwareModule — a NixOS module (path or inline attrset) that
    #                    provides hardware-specific configuration.
    #                    MUST set nixpkgs.hostPlatform or the system
    #                    defaults to "x86_64-linux".
    #   system         — override the default platform string.
    #                    Ignored if hardwareModule sets nixpkgs.hostPlatform.
    #
    # Usage from a thin local flake:
    #   nixosConfigurations.myhostname = vexos.lib.mkVexosSystem {
    #     hardwareModule = ./hardware-configuration.nix;
    #   };
    mkVexosSystem = { hardwareModule, system ? "x86_64-linux" }:
      let
        pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs pkgs-unstable; };
        modules = [
          hardwareModule
          ./hosts/default/configuration.nix

          # CachyOS kernel overlay — exposes pkgs.cachyosKernels.*
          { nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.default ]; }

          # TODO: Uncomment when vex-kernels input is added above.
          # Bazzite kernel overlay — exposes pkgs.vexKernels.*
          # { nixpkgs.overlays = [ inputs.vex-kernels.overlays.default ]; }

          # nix-gaming NixOS modules
          inputs.nix-gaming.nixosModules.pipewireLowLatency
          inputs.nix-gaming.nixosModules.platformOptimizations

          # nix-flatpak declarative Flatpak management
          nix-flatpak.nixosModules.nix-flatpak

          # Home Manager integration
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable; };
            home-manager.users.nimda = import ./home/default.nix;
          }
        ];
      };
  in
  {
    # ── Library output ────────────────────────────────────────────────
    # Exposed for consumption by thin local flakes on target machines.
    lib.mkVexosSystem = mkVexosSystem;

    # ── CI / nix flake check configuration ───────────────────────────
    # Uses the in-repo template hardware-configuration.nix.
    # This is NOT the configuration deployed to real machines.
    nixosConfigurations = {
      vexos = mkVexosSystem {
        hardwareModule = ./hosts/default/hardware-configuration.nix;
      };
    };
  };
}
