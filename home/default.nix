{ config, pkgs, pkgs-unstable, inputs, ... }:

{
  imports = [
    ./photogimp.nix
  ];

  # Home Manager configuration for user-specific settings
  # This is managed by Home Manager and controls user environment

  photogimp.enable = true;

  home.username = "nimda";
  home.homeDirectory = "/home/nimda";

  # This value determines the Home Manager release which the
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # User-specific packages
  home.packages = with pkgs; [
    # Development tools
    vscode
    rustup
    pkgs-unstable.nodejs_25

    # Browsers
    brave

    # Gaming Utilities
    protonplus

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
    just

    # Themes
    bibata-cursors
    kora-icon-theme

    # System utilities
    fastfetch
    btop
    inxi
    pavucontrol
    blivet-gui
    inputs.up.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Bash configuration
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      ".." = "cd ..";

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

  # Wallpapers — copied from the repo into ~/Pictures/Wallpapers/ at activation.
  # JXL format requires a gdk-pixbuf loader; if wallpapers don't appear,
  # add jxl-pixbuf-loader (or equivalent) to modules/gnome.nix environment.systemPackages.
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ../wallpapers/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ../wallpapers/vex-bb-dark.jxl;

  # Explicit dconf overrides so GNOME picks up the correct theme names.
  # (GNOME reads icon/cursor theme from dconf, not just GTK config files.)
  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
        "AlphabeticalAppGrid@stuarthayhurst"
        "gamemodeshellextension@trsnaqe.com"
        "gnome-ui-tune@itstime.tech"
        "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
        "steal-my-focus-window@steal-my-focus-window"
        "tailscale-status@maxgallup.github.com"
        "caffeine@patapon.info"
        pkgs.gnomeExtensions.restart-to.extensionUuid
        "blur-my-shell@aunetx"
        "background-logo@fedorahosted.org"
      ];
      favorite-apps = [
        "brave-browser.desktop"
        "app.zen_browser.zen.desktop"
        "org.gnome.Nautilus.desktop"
        "com.mitchellh.ghostty.desktop"
        "io.github.up.desktop"
        "org.gnome.Boxes.desktop"
        "code.desktop"
        "discord.desktop"
      ];
    };
    "org/gnome/desktop/interface" = {
      clock-format = "12h";
      cursor-size = 24;
      cursor-theme = "Bibata-Modern-Classic";
      icon-theme = "kora";
    };
    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };
    "org/gnome/desktop/background" = {
      picture-uri      = "file://${config.home.homeDirectory}/Pictures/Wallpapers/vex-bb-light.jxl";
      picture-uri-dark = "file://${config.home.homeDirectory}/Pictures/Wallpapers/vex-bb-dark.jxl";
      picture-options  = "zoom";
    };
    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-position = "LEFT";
    };
    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
    };
    
    
    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Games" "Office" "Utilities" "System" ];
    };
    "org/gnome/desktop/app-folders/folders/Games" = {
      name = "Games";
      apps = [
        "org.prismlauncher.PrismLauncher.desktop"
      ];
    };
    "org/gnome/desktop/app-folders/folders/Office" = {
      name = "Office";
      apps = [
        "org.onlyoffice.desktopeditors.desktop"
        "org.gnome.TextEditor.desktop"
        "org.gnome.Papers.desktop"
      ];
    };
    "org/gnome/desktop/app-folders/folders/Utilities" = {
      name = "Utilities";
      apps = [
        "com.mattjakeman.ExtensionManager.desktop"
        "it.mijorus.gearlever.desktop"
        "org.gnome.tweaks.desktop"
        "io.github.flattool.Warehouse.desktop"
        "io.missioncenter.MissionCenter.desktop"
        "com.github.tchx84.Flatseal.desktop"
      ];
    };
    "org/gnome/desktop/app-folders/folders/System" = {
      name = "System";
      apps = [
        "org.pulseaudio.pavucontrol.desktop"
        "rog-control-center.desktop"
        "org.gnome.SystemMonitor.desktop"
        "org.gnome.Settings.desktop"
        "org.gnome.seahorse.Application.desktop"
        "nixos-manual.desktop"
        "cups.desktop"
        "blivet-gui.desktop"
        "blueman-manager.desktop"
        "btop.desktop"
        "ca.desrt.dconf-editor.desktop"
        "org.gnome.baobab.desktop"
        "org.gnome.DiskUtility.desktop"
        "org.gnome.font-viewer.desktop"
        "htop.desktop"
      ];
    };

  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}
