# Desktop module - imports all desktop-related modules
# Used by desktop and HTPC variants
{ config, pkgs, lib, ... }:

{
  imports = [
    ./gnome.nix
    ./gnome-extensions.nix
    ./audio.nix
    ./fonts.nix
  ];
}
