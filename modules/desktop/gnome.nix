{ config, pkgs, ... }:

{
  # Enable GNOME Desktop Environment with GDM
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Enable Wayland on GDM (default)
  services.xserver.displayManager.gdm.wayland = true;

  # Configure keymap
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
