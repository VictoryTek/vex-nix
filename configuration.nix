{ config, pkgs, ... }:

{
  # NixOS configuration for vex-nix

  # Import modules
  imports = [
    ./modules/packages/packages.nix
    ./modules/packages/flatpak.nix
    ./modules/desktop/gnome.nix
    ./modules/desktop/gnome-extensions.nix
  ];

  # Bootloader configuration (add to hardware-configuration.nix if auto-generated one is missing it)
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # For legacy BIOS systems

  # Networking
  networking.hostName = "vex-nix";
  networking.networkmanager.enable = true;

  # Time zone and localization
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the X11 windowing system
  services.xserver.enable = true;

  # User account
  users.users.nimda = {
    isNormalUser = true;
    description = "nimda";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System state version
  system.stateVersion = "24.11";
}
