# GNOME Desktop Environment configuration
{ config, pkgs, lib, ... }:

{
  # Enable X11 and GNOME
  services.xserver = {
    enable = true;
    displayManager.gdm = {
      enable = true;
      wayland = true;  # Enable Wayland by default
    };
    desktopManager.gnome.enable = true;
  };

  # Exclude some default GNOME packages
  environment.gnome.excludePackages = with pkgs; [
    gnome-photos
    gnome-tour
    cheese                        # webcam tool
    gnome-music
    epiphany                      # web browser
    geary                         # email reader
    evince                        # document viewer
    gnome-characters
    totem                         # video player
    tali                          # poker game
    iagno                         # go game
    hitori                        # sudoku game
    atomix                        # puzzle game
    gnome-maps
    gnome-clocks
    gnome-weather
    simple-scan                   # document scanner
  ];

  # GNOME-specific packages
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
  ];
}
