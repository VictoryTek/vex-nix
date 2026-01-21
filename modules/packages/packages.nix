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
    topgrade
    tailscale
    tmux

    # GNOME & Theming
    bazaar
    bibata-cursors
    kora-icon-theme
    gnome-tweaks

    # Terminal & Shell Enhancements
    ghostty
    starship
  ];

  systemd.user.services.spice-vdagent = {
    description = "SPICE Guest Session Agent";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.spice-vdagent}/bin/spice-vdagent -x";
      Restart = "on-failure";
    };
    unitConfig.ConditionVirtualization = "vm";
  };

  # Packages to remove/exclude
  environment.excludePackages = with pkgs; [
    waydroid
  ];
}
