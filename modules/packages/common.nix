# Common system packages
{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    # Essential utilities
    git
    curl
    wget
    unzip
    zip
    
    # File management
    tree
    fd
    ripgrep
    
    # System monitoring
    inxi
    htop
    btop
    
    # Text editors
    nano
    
    # Network tools
    dig
  ];
  
  # Remove unwanted default packages
  environment.excludePackages = with pkgs; [
    # Add packages to exclude here
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
    gnome-extension-manager       # extensions app (using Extension Manager flatpak instead)
  ];
  
  # Enable starship prompt
  programs.starship.enable = true;
}
