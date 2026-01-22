{ config, pkgs, lib, ... }:

let
  ge = pkgs.gnomeExtensions;
  desiredExtAttrs = [
    "alphabetical-app-grid"
    "appindicatorsupport"
    "background-logo"
    "blur-my-shell"
    "caffeine"
    "dash-to-dock"
    "gnome-ui-tune"
    "just-perfection-desktop"
    "nothing-to-say"
    "quick-settings-tweaks"
    "steal-my-focus-window"
    "tailscale"
    "tilingshell"
  ];

  getUuid = name: if builtins.hasAttr name ge then (
      if builtins.hasAttr "extensionUuid" (ge.${name}) then ge.${name}.extensionUuid else name
    ) else name;

  enabledList = lib.filter (x: x != null) (lib.map getUuid desiredExtAttrs);
  enabledExtsText = "[" + lib.concatStringsSep ", " (lib.map (x: "'" + x + "'") enabledList) + "]";
in

{
  # Install custom wallpapers
  environment.etc."wallpapers/vex-bb-light.jxl".source = ../../assets/wallpapers/vex-bb-light.jxl;
  environment.etc."wallpapers/vex-bb-dark.jxl".source = ../../assets/wallpapers/vex-bb-dark.jxl;

  # Install Starship configuration system-wide
  environment.etc."starship.toml".source = ../../assets/system/etc/starship.toml;
  environment.etc."profile.d/starship.sh".source = ../../assets/system/etc/profile.d/starship.sh;

  # Install custom os-release for VexHTPC branding (override NixOS default)
  environment.etc."os-release".source = lib.mkForce ../../assets/system/etc/os-release;

  # Install logos and icons to /usr/share paths
  environment.etc."usr/share/pixmaps/vex.png".source = ../../assets/system/usr/share/pixmaps/vex.png;
  environment.etc."usr/share/pixmaps/fedora-gdm-logo.png".source = ../../assets/system/usr/share/pixmaps/fedora-gdm-logo.png;
  environment.etc."usr/share/pixmaps/fedora-logo-small.png".source = ../../assets/system/usr/share/pixmaps/fedora-logo-small.png;
  environment.etc."usr/share/pixmaps/fedora-logo-sprite.png".source = ../../assets/system/usr/share/pixmaps/fedora-logo-sprite.png;
  environment.etc."usr/share/pixmaps/fedora-logo-sprite.svg".source = ../../assets/system/usr/share/pixmaps/fedora-logo-sprite.svg;
  environment.etc."usr/share/pixmaps/fedora-logo.png".source = ../../assets/system/usr/share/pixmaps/fedora-logo.png;
  environment.etc."usr/share/pixmaps/fedora_logo_med.png".source = ../../assets/system/usr/share/pixmaps/fedora_logo_med.png;
  environment.etc."usr/share/pixmaps/fedora_whitelogo_med.png".source = ../../assets/system/usr/share/pixmaps/fedora_whitelogo_med.png;
  environment.etc."usr/share/pixmaps/system-logo-white.png".source = ../../assets/system/usr/share/pixmaps/system-logo-white.png;

  # Install update icon
  environment.etc."usr/share/vex/update.png".source = ../../assets/system/usr/share/vex/update.png;

  # Install hicolor icon
  environment.etc."usr/share/icons/hicolor/256x256/vex-logo-icon.png".source = ../../assets/system/usr/share/icons/hicolor/256x256/vex-logo-icon.png;

  # Install fedora logos
  environment.etc."usr/share/fedora-logos/fedora_darkbackground.svg".source = ../../assets/system/usr/share/fedora-logos/fedora_darkbackground.svg;
  environment.etc."usr/share/fedora-logos/fedora_lightbackground.svg".source = ../../assets/system/usr/share/fedora-logos/fedora_lightbackground.svg;

  # Install Plymouth watermark
  environment.etc."usr/share/plymouth/themes/spinner/watermark.png".source = ../../assets/system/usr/share/plymouth/themes/spinner/watermark.png;

  # Enable dconf
  programs.dconf.enable = true;

  # Configure dconf database for GNOME system-wide defaults
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        # GDM Login Logo
        "org/gnome/login-screen" = {
          logo = "/usr/share/pixmaps/vex.png";
        };

        # Desktop Interface Settings
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          accent-color = "teal";
          icon-theme = "kora";
          cursor-theme = "Bibata-Modern-Classic";
          cursor-size = lib.gvariant.mkInt32 24;
        };

        # Desktop Background
        "org/gnome/desktop/background" = {
          picture-uri = "file:///etc/wallpapers/vex-bb-light.jxl";
          picture-uri-dark = "file:///etc/wallpapers/vex-bb-dark.jxl";
          picture-options = "zoom";
        };

        # Screensaver Settings
        "org/gnome/desktop/screensaver" = {
          picture-uri = "file:///etc/wallpapers/vex-bb-dark.jxl";
          picture-options = "zoom";
          lock-enabled = lib.gvariant.mkBoolean false;
        };

        # Power Settings
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-type = "nothing";
          sleep-inactive-battery-type = "nothing";
        };

        # Window Manager Preferences
        "org/gnome/desktop/wm/preferences" = {
          button-layout = "appmenu:minimize,maximize,close";
        };

        # Shell Settings
        "org/gnome/shell" = {
          disable-user-extensions = lib.gvariant.mkBoolean false;
          enabled-extensions = enabledList;
          favorite-apps = [
            "com.brave.Browser.desktop"
            "io.gitlab.librewolf-community.desktop"
            "tv.plex.PlexDesktop.desktop"
            "io.freetubeapp.FreeTube.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "system-update.desktop"
          ];
        };

        # Logo Widget Extension
        "org/gnome/shell/extensions/logo-widget" = {
          logo-file = "/usr/share/pixmaps/vex.png";
          logo-file-dark = "/usr/share/pixmaps/vex.png";
        };

        # Dash to Dock Extension
        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-position = "LEFT";
        };

        # Touchpad Settings
        "org/gnome/desktop/peripherals/touchpad" = {
          tap-to-click = lib.gvariant.mkBoolean true;
        };

        # Privacy Settings
        "org/gnome/desktop/privacy" = {
          remember-recent-files = lib.gvariant.mkBoolean true;
        };
      };
    }
  ];
}
