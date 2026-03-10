{ config, pkgs, ... }:

{
  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

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
    gnome-weather
    gnome-clocks
    gnome-maps
    simple-scan        # Document scanner
    gnome-characters
    gnome-tour
    gnome-user-docs
    yelp               # GNOME Help
    epiphany           # GNOME Web browser
  ];

  # Enable GNOME keyring
  services.gnome.gnome-keyring.enable = true;
}
