{ config, pkgs, ... }:

{
  # Home Manager configuration for user-specific settings
  # This is managed by Home Manager and controls user environment

  home.username = "nimda";
  home.homeDirectory = "/home/nimda";

  # This value determines the Home Manager release which the
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # User-specific packages
  home.packages = with pkgs; [
    # Development tools
    vscode

    # Browsers
    brave

    # Terminal emulators
    ghostty

    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    tmux

    # Themes
    bibata-cursors
    kora-icon-theme

    # System utilities
    fastfetch
    btop
    inxi
    pavucontrol
    blivet-gui
  ];

  # Git configuration
  #programs.git = {
  #  enable = true;
  #  settings = {
  #    user.name = "Nimda";
  #    user.email = "vex@example.com";  # Change this
  #    init.defaultBranch = "main";
  #    pull.rebase = false;
  #  };
  #};

  # Bash configuration
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      ".." = "cd ..";
      update = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
      rebuild = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
      
      # Tailscale shortcuts
      ts = "tailscale";
      tss = "tailscale status";
      tsip = "tailscale ip";
      
      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };

  # Starship cross-shell prompt
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  # Cursor theme (applies to both X11 and Wayland)
  home.pointerCursor = {
    gtk.enable = true;
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
  };

  # GTK theming — enable = true writes gtk-3/4 config files for non-GNOME apps.
  # Icon and cursor theme are set via dconf.settings below (what GNOME actually reads).
  gtk.enable = true;
  gtk.iconTheme = {
    name = "Kora";
    package = pkgs.kora-icon-theme;
  };

  # Explicit dconf overrides so GNOME picks up the correct theme names.
  # (GNOME reads icon/cursor theme from dconf, not just GTK config files.)
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      icon-theme = "Kora";
      cursor-theme = "Bibata-Modern-Classic";
      cursor-size = 24;
    };
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}
