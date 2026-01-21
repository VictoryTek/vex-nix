{ config, pkgs, ... }:

{
  # GNOME Extensions
  environment.systemPackages = with pkgs.gnomeExtensions; [
    # Add GNOME extensions here
    alphabetical-app-grid
    dash-to-dock
    gnome-40-ui-improvements
    steal-my-focus-window
    background-logo
  ];
}
