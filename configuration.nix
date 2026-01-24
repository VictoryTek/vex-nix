{ config, pkgs, ... }:

{
  # NixOS configuration for vex-nix

  # Import modules
  imports = [
    ./modules/packages/packages.nix
    ./modules/packages/flatpak.nix
    ./modules/desktop/gnome.nix
    ./modules/desktop/gnome-extensions.nix
    ./modules/system/system.nix
    # GPU acceleration is imported by flake variant
  ];

  # Bootloader configuration (add to hardware-configuration.nix if auto-generated one is missing it)
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # For legacy BIOS systems

  # Plymouth boot splash
  boot.plymouth.enable = true;
  # boot.initrd.systemd.enable = true;  # Temporarily disabled - may cause boot issues

  # Networking
  networking.hostName = "vex-htpc";
  networking.networkmanager.enable = true;

  # Time zone and localization
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # User account
  users.users.nimda = {
    isNormalUser = true;
    description = "nimda";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable flakes and configure binary cache
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    auto-optimise-store = true;
    # Automatically free disk space when it gets low during builds
    min-free = 1073741824;  # 1GB - trigger GC if less than this free
    max-free = 3221225472;  # 3GB - GC until this much is free
  };

  # Automatic garbage collection to prevent disk space issues
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Limit number of generations to keep
  boot.loader.grub.configurationLimit = 10;

  # System state version
  system.stateVersion = "24.11";
}
