{ config, pkgs, ... }:

{
  # Enable the X11 windowing system (still required for XKB keyboard config and XWayland)
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment with Wayland enforced
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  services.desktopManager.gnome.enable = true;

  # Auto-login — skips the GDM lock screen on boot
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "nimda";

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
    gnomeExtensions.alphabetical-app-grid
    gnomeExtensions.gamemode-shell-extension
    gnomeExtensions.gnome-40-ui-improvements
    gnomeExtensions.nothing-to-say
    gnomeExtensions.steal-my-focus-window
    gnomeExtensions.tailscale-status
    gnomeExtensions.caffeine
    gnomeExtensions.restart-to
    gnomeExtensions.blur-my-shell
    gnomeExtensions.appindicator
    gnomeExtensions.background-logo
    gnome-boxes
  ];

  # Virtualisation backend for GNOME Boxes and virt-manager
  virtualisation.libvirtd.enable = true;
  # Installs virt-manager with polkit rules so non-root users can manage VMs
  programs.virt-manager.enable = true;
  # USB passthrough support for virt-manager VMs
  virtualisation.spiceUSBRedirection.enable = true;

  # Exclude some default GNOME packages (optional)
  environment.gnome.excludePackages = with pkgs; [
    gnome-weather
    gnome-clocks
    gnome-contacts
    gnome-maps
    simple-scan        # Document scanner
    gnome-characters
    gnome-tour
    gnome-user-docs
    gnomeExtensions
    yelp               # GNOME Help
    epiphany           # GNOME Web browser

    # Additional exclusions
    # TODO: Exclude GNOME Extensions manager app once correct nixpkgs attribute is identified
    # (gnome-extensions-app and gnome-shell-extensions are both wrong for this nixpkgs revision)
    xterm                  # Legacy X11 terminal
    geary                  # GNOME email client
    gnome-music            # GNOME music player
    rhythmbox              # Alternative music player
  ];

  # Enable GNOME keyring
  services.gnome.gnome-keyring.enable = true;
}
