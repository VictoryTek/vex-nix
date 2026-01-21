{ config, pkgs, ... }:

{
  # NixOS configuration for vex-nix

  # Import modules
  imports = [
    ./modules/packages/packages.nix
    ./modules/packages/flatpak.nix
    ./modules/desktop/gnome.nix
  ];

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
