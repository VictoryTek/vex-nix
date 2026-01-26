{ config, pkgs, lib, ... }:

{
  # ============================================================
  # NixOS configuration for vex-htpc
  # ============================================================

  # ------------------------------------------------------------
  # Imports
  # ------------------------------------------------------------
  # hardware-configuration.nix is LOCAL and NOT tracked in git
  # It is automatically provided by /etc/nixos on each machine
  imports = [
    ./modules/packages/packages.nix
    ./modules/packages/flatpak.nix

    ./modules/desktop/gnome.nix
    ./modules/desktop/gnome-extensions.nix

    ./modules/system/system.nix
    ./modules/system/gpu-autodetect.nix
    ./modules/system/rollback.nix
  ];

  # ------------------------------------------------------------
  # Bootloader
  # ------------------------------------------------------------
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # adjust per machine
  boot.loader.grub.configurationLimit = 5;

  # Plymouth boot splash
  boot.plymouth.enable = true;

  # ------------------------------------------------------------
  # Networking
  # ------------------------------------------------------------
  networking.hostName = "vex-htpc";
  networking.networkmanager.enable = true;

  # ------------------------------------------------------------
  # Time & Locale
  # ------------------------------------------------------------
  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";

  # ------------------------------------------------------------
  # Users
  # ------------------------------------------------------------
  # This does NOT override installer-created users
  # It only adds configuration if the user exists
  users.users.nimda = lib.mkIf (config.users.users ? nimda) {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # ------------------------------------------------------------
  # Audio (PipeWire)
  # ------------------------------------------------------------
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ------------------------------------------------------------
  # Printing
  # ------------------------------------------------------------
  services.printing.enable = true;

  # ------------------------------------------------------------
  # Nix Settings (Flakes + Disk Safety)
  # ------------------------------------------------------------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    auto-optimise-store = true;

    # Prevent disk exhaustion during builds
    min-free = 1073741824;   # 1 GiB
    max-free = 4294967296;   # 4 GiB

    substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  # ------------------------------------------------------------
  # Reduce Disk Usage
  # ------------------------------------------------------------
  environment.enableDebugInfo = false;

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 3d";
  };

  # ------------------------------------------------------------
  # Allow Unfree Packages (required for NVIDIA)
  # ------------------------------------------------------------
  nixpkgs.config.allowUnfree = true;

  # ------------------------------------------------------------
  # System Version
  # ------------------------------------------------------------
  system.stateVersion = "24.11";
}
