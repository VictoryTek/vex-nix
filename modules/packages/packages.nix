{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages
  environment = {
    systemPackages = with pkgs; [
    # Default packages
      firefox
      git
      wget

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
  };

  systemd.user.services.spice-vdagent = {
    description = "SPICE Guest Session Agent";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.spice-vdagent}/bin/spice-vdagent -x";
      Restart = "on-failure";
    };
    unitConfig.ConditionVirtualization = "vm";
  };

  # Packages to be removed
  environment = {
    gnome = {
      excludePackages = with pkgs; [
        gnome-photos
        gnome-tour
        cheese                        # webcam tool
        gnome-music
        epiphany                      # web browser
        geary                         # email reader
        evince                        # document viewer
        gnome-characters
        totem                         # video player
        tali                          # poker game
        iagno                         # go game
        hitori                        # sudoku game
        atomix                        # puzzle game
        gnome-maps
        gnome-clocks
        gnome-weather
      ];
    };
  };
}