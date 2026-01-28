# Common system packages
{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    # Default Apps
    gnome-extensions-manager
    
    # Essential utilities
    curl
    fastfetch
    git
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
  
  # Enable starship prompt
  programs.starship.enable = true;
}
