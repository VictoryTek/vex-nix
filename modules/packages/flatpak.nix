# Flatpak support
{ config, pkgs, lib, ... }:

{
  # Enable Flatpak
  services.flatpak.enable = true;
  
  # Add Flathub repository on activation
  # Note: This runs on each rebuild, but flatpak handles duplicates gracefully
  system.activationScripts.flatpak-repo = ''
    ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  '';
}
