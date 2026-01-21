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
      flatpak install -y flathub com.bitwarden.desktop
      flatpak install -y flathub com.mattjakeman.ExtensionManager
      flatpak install -y flathub com.github.tchx84.Flatseal
      flatpak install -y flathub io.freetubeapp.FreeTube
      flatpak install -y flathub it.mijorus.gearlever
      flatpak install -y flathub org.gnome.TextEditor
      flatpak install -y flathub io.missioncenter.MissionCenter
      flatpak install -y flathub com.rustdesk.RustDesk
      flatpak install -y flathub org.gnome.seahorse.Application
      flatpak install -y flathub com.github.unrud.VideoDownloader
      flatpak install -y flathub io.github.flattool.Warehouse
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
