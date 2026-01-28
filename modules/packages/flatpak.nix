# Flatpak support
{ config, pkgs, lib, ... }:

{
  # Enable Flatpak
  services.flatpak.enable = true;

  # Add Flathub repository
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # List of Flatpak packages to install
  systemd.services.flatpak-installer = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "flatpak-repo.service" ];
    after = [ "flatpak-repo.service" ];
    path = [ pkgs.flatpak ];
    script = ''
      # Wait for remote to be ready
      until flatpak remotes | grep -q flathub; do
        echo "Waiting for flathub remote..."
        sleep 2
      done

      # Install Flatpak applications
      flatpak install -y flathub com.brave.Browser || true
      flatpak install -y flathub app.zen_browser.zen || true
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # Install required XDG desktop portals for Flatpak
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
