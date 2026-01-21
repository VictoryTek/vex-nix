{ config, pkgs, ... }:

{
  # Install custom wallpapers and logos to system
  environment.etc."wallpapers/vex-bb-light.jxl".source = ../../assets/wallpaper/vex-bb-light.jxl;
  environment.etc."wallpapers/vex-bb-dark.jxl".source = ../../assets/wallpaper/vex-bb-dark.jxl;
  # environment.etc."pixmaps/vex.png".source = ../../assets/logos/vex.png;  # Uncomment and adjust path if you have a logo

  # GNOME dconf settings
  programs.dconf.enable = true;

  # System-wide dconf settings for GNOME
  programs.dconf.profiles.user.databases = [{
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
        cursor-size = 24;
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
        lock-enabled = false;
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
        disable-user-extensions = false;
        enabled-extensions = [
          "AlphabeticalAppGrid@stuarthayhurst"
          "appindicatorsupport@rgcjonas.gmail.com"
          "background-logo@fedorahosted.org"
          "blur-my-shell@aunetx"
          "caffeine@patapon.info"
          "dash-to-dock@micxgx.gmail.com"
          "gnome-ui-tune@itstime.tech"
          "just-perfection-desktop@just-perfection"
          "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
          "quick-settings-tweaks@qwreey"
          "steal-my-focus-window@steal-my-focus-window"
          "tailscale@joaophi.github.com"
          "tilingshell@ferrarodomenico.com"
        ];
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
        tap-to-click = true;
      };

      # Privacy Settings
      "org/gnome/desktop/privacy" = {
        remember-recent-files = true;
      };
    };
  }];
}
