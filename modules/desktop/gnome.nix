{ config, pkgs, ... }:

{
  # Enable GNOME Desktop Environment with GDM
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Enable Wayland on GDM (default)
  services.displayManager.gdm.wayland = true;

  # Configure keymap
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
