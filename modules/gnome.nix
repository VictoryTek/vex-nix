{ config, lib, pkgs, ... }:

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

  # Virtualisation backend for GNOME Boxes and virt-manager.
  #
  # Without KVM (e.g. VirtualBox with no nested virtualization enabled),
  # QEMU falls back to TCG (software emulation) for capability probing.
  # TCG probing inside a VM is 10–30× slower than native; it takes > 120 s.
  # The default "--timeout 120" idle timer fires before probing completes,
  # causing libvirtd to exit mid-init with status=1/FAILURE ("Make forcefull
  # daemon shutdown"). The three settings below fix this:
  #
  #   extraOptions "--timeout" "0"  — disables idle timeout; probing can
  #                                   complete regardless of how long it takes.
  #   security_driver = "none"      — skips SELinux/AppArmor probing (absent
  #                                   in VirtualBox), reducing init latency.
  #   TimeoutStartSec = "infinity"  — systemd never pre-empts a slow startup.
  #
  # All three are safe on bare-metal-with-KVM (probing is fast; settings are
  # no-ops in that context).
  virtualisation.libvirtd = {
    enable = true;
    extraOptions = [ "--timeout" "0" ];
    qemu.verbatimConfig = ''
      namespaces = []
      security_driver = "none"
    '';
  };

  # Unlimited systemd startup window — defense-in-depth for slow TCG probing.
  systemd.services.libvirtd.serviceConfig.TimeoutStartSec = lib.mkDefault "infinity";

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
    yelp               # GNOME Help
    epiphany           # GNOME Web browser

    # Additional exclusions
    xterm                  # Legacy X11 terminal
    geary                  # GNOME email client
    gnome-music            # GNOME music player
    rhythmbox              # Alternative music player
  ];

  # Enable GNOME keyring
  services.gnome.gnome-keyring.enable = true;

  # The GNOME Extensions app (green puzzle piece, org.gnome.Extensions) is bundled
  # inside gnome-shell (a mandatory package) and cannot be removed via excludePackages.
  # Patch the derivation to drop its desktop file so it never appears in the app grid.
  nixpkgs.overlays = [
    (final: prev: {
      gnome-shell = prev.gnome-shell.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -f $out/share/applications/org.gnome.Extensions.desktop
        '';
      });
    })
  ];
}
