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
  
  # Install Flatpak packages on activation
  # Add Flatpak app IDs here (find them on flathub.org)
  system.activationScripts.flatpak-install = ''
    # Example: ${pkgs.flatpak}/bin/flatpak install -y flathub com.spotify.Client
    
    flatpak install -y flathub com.brave.Browser
    flatpak install -y flathub app.zen_browser.zen
    
  '';
}
