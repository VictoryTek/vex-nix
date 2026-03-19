{ config, lib, pkgs, ... }:

{
  # Enable the X11 windowing system (still required for XKB keyboard config and XWayland)
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment with Wayland enforced
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  services.desktopManager.gnome.enable = true;

  # Auto-login — skips the GDM password prompt on boot (convenience feature).
  # SECURITY INVARIANT: auto-login must NEVER be combined with
  # `lock-enabled = false` in dconf. The screen lock in home/default.nix
  # MUST remain enabled to prevent physical-access bypasses when the
  # session is unattended. Do not set lock-enabled = false downstream.
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
  # daemon shutdown"). For VM guests where this occurs, apply these overrides
  # per-machine in hardware-configuration.nix rather than globally:
  #
  #   virtualisation.libvirtd.extraOptions = lib.mkForce [ "--timeout" "0" ];
  #   systemd.services.libvirtd.serviceConfig.TimeoutStartSec = lib.mkForce "infinity";
  #
  #   security_driver = "none" (in qemu.verbatimConfig) — skips SELinux/AppArmor
  #                              probing (absent in VirtualBox), reducing init latency.
  virtualisation.libvirtd = {
    enable = true;
    # extraOptions is intentionally omitted — libvirtd's default 120 s idle
    # timeout is correct for bare-metal machines with KVM.
    # If running VexOS inside a VM without nested KVM (slow TCG probing),
    # add this override in hardware-configuration.nix:
    #   virtualisation.libvirtd.extraOptions = lib.mkForce [ "--timeout" "0" ];
    qemu.verbatimConfig = ''
      namespaces = []
      security_driver = "none"
    '';
  };

  # Give libvirtd 120 s to start — matches its own idle timeout on bare metal.
  # VM users who set --timeout 0 above should also set TimeoutStartSec = "infinity".
  systemd.services.libvirtd.serviceConfig.TimeoutStartSec = lib.mkDefault "120";

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
