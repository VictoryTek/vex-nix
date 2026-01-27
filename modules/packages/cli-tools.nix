# Common CLI tools
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
