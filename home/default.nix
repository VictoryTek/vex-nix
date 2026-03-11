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

  # Wayland session environment variables.
  # NIXOS_OZONE_WL forces Electron apps (VS Code, etc.) to use the Wayland backend.
  # MOZ_ENABLE_WAYLAND forces Firefox to use the Wayland backend.
  # QT_QPA_PLATFORM ensures Qt apps prefer Wayland with XCB as fallback.
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
  };

  # Starship cross-shell prompt
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  # Cursor theme for X11 and Wayland cursor rendering (env vars, xcursor, .icons/default).
  # gtk.enable is intentionally omitted here — cursor theme for GTK is handled below
  # to avoid activation-script conflicts that cause the icon theme to revert after reboot.
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
  };

  # GTK theming — writes gtk-3/4 config files for non-GNOME apps.
  # Declaring both iconTheme and cursorTheme here in one place prevents conflicts
  # between Home Manager's pointer-cursor activation scripts and dconf settings.
  gtk.enable = true;
  gtk.iconTheme = {
    name = "kora";
    package = pkgs.kora-icon-theme;
  };
  gtk.cursorTheme = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
  };

  # Explicit dconf overrides so GNOME picks up the correct theme names.
  # (GNOME reads icon/cursor theme from dconf, not just GTK config files.)
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      icon-theme = "kora";
      cursor-theme = "Bibata-Modern-Classic";
      cursor-size = 24;
    };
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}
