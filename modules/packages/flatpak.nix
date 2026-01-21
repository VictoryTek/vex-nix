{ config, pkgs, ... }:

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
  };

  # List of Flatpak packages to install
  systemd.services.flatpak-installer = {
    wantedBy = [ "multi-user.target" ];
    after = [ "flatpak-repo.service" ];
    path = [ pkgs.flatpak ];
    script = ''
      # Install Flatpak applications
      flatpak install -y flathub com.brave.Browser
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
