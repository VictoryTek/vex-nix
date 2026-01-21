{ config, pkgs, lib, ... }:

let
  ge = pkgs.gnomeExtensions;
  desired = [
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

  installable = lib.filter (x: x != null) (lib.map (n: if lib.attrExists n ge then ge.${n} else null) desired);
in
{
  # GNOME Extensions: install packaged extensions when available
  environment.systemPackages = with pkgs; installable;
}
