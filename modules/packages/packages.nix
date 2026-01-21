{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages
  environment.systemPackages = with pkgs; [
    # Default packages
    wget
    git
    firefox

    # System Utilities
    blivet-gui
    fastfetch
    inxi
    pavucontrol
    tailscale
    tmux

    # GNOME & Theming
    bibata-cursors
    gnome-tweaks

    # Terminal & Shell Enhancements
    ghostty
    starship
  ];
}
