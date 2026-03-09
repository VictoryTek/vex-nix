{ config, pkgs, ... }:

{
  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable touchpad support (uncomment if needed)
  # services.xserver.libinput.enable = true;

  # GNOME-specific packages
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
  ];

  # Exclude some default GNOME packages (optional)
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    epiphany  # GNOME Web browser
    geary     # Email client
    # Add more packages to exclude if desired
  ];

  # Enable GNOME keyring
  services.gnome.gnome-keyring.enable = true;
}
