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
  # Install custom wallpapers and logos to system
  environment.etc."wallpapers/vex-bb-light.jxl".source = ../../assets/wallpapers/vex-bb-light.jxl;
  environment.etc."wallpapers/vex-bb-dark.jxl".source = ../../assets/wallpapers/vex-bb-dark.jxl;
  environment.etc."usr/share/pixmaps/vex.png".source = ../../assets/logo/vex.png;  # Install logo to /usr/share/pixmaps/

  # Enable dconf
  programs.dconf.enable = true;

  # Install gschema override file for GNOME defaults
  environment.etc."dconf/db/local.d/01-vex".text = ''
    # GDM Login Logo
    [org/gnome/login-screen]
    logo='/usr/share/pixmaps/vex.png'

    # Desktop Interface Settings
    [org/gnome/desktop/interface]
    color-scheme='prefer-dark'
    accent-color='teal'
    icon-theme='kora'
    cursor-theme='Bibata-Modern-Classic'
    cursor-size=24

    # Desktop Background
    [org/gnome/desktop/background]
    picture-uri='file:///etc/wallpapers/vex-bb-light.jxl'
    picture-uri-dark='file:///etc/wallpapers/vex-bb-dark.jxl'
    picture-options='zoom'

    # Screensaver Settings
    [org/gnome/desktop/screensaver]
    picture-uri='file:///etc/wallpapers/vex-bb-dark.jxl'
    picture-options='zoom'
    lock-enabled=false

    # Power Settings
    [org/gnome/settings-daemon/plugins/power]
    sleep-inactive-ac-type='nothing'
    sleep-inactive-battery-type='nothing'

    # Window Manager Preferences
    [org/gnome/desktop/wm/preferences]
    button-layout='appmenu:minimize,maximize,close'

    # Shell Settings
    [org/gnome/shell]
    disable-user-extensions=false
    enabled-extensions=${enabledExtsText}
    favorite-apps=['com.brave.Browser.desktop', 'io.gitlab.librewolf-community.desktop', 'tv.plex.PlexDesktop.desktop', 'io.freetubeapp.FreeTube.desktop', 'org.gnome.Nautilus.desktop', 'com.mitchellh.ghostty.desktop', 'system-update.desktop']

    # Logo Widget Extension
    [org/gnome/shell/extensions/logo-widget]
    logo-file='/usr/share/pixmaps/vex.png'
    logo-file-dark='/usr/share/pixmaps/vex.png'

    # Dash to Dock Extension
    [org/gnome/shell/extensions/dash-to-dock]
    dock-position='LEFT'

    # Touchpad Settings
    [org/gnome/desktop/peripherals/touchpad]
    tap-to-click=true

    # Privacy Settings
    [org/gnome/desktop/privacy]
    remember-recent-files=true
  '';

  # Update dconf database after changes
  system.activationScripts.dconf-update = lib.mkAfter ''
    if [ -x "$(command -v dconf)" ]; then
      ${pkgs.dconf}/bin/dconf update
    fi
  '';
}
