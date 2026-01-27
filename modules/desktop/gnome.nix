# GNOME Desktop Environment configuration
{ config, pkgs, lib, ... }:

{
  # Enable X11 and GNOME
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  # Exclude some default GNOME packages
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    epiphany      # web browser
    geary         # email client
    gnome-music
  ];

  # GNOME-specific packages
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
  ];
}
