{ ... }:

{
  # ── Enable Flatpak ────────────────────────────────────────────────────
  services.flatpak.enable = true;

  # ── XDG Portal (explicit for clarity; GNOME already enables this) ─────
  xdg.portal.enable = true;

  # ── Declarative Flatpak applications (all from Flathub) ───────────────
  # nix-flatpak default remote is Flathub; no explicit remote declaration needed.
  services.flatpak.packages = [
    "com.bitwarden.desktop"
    "io.github.pol_rivero.github-desktop-plus"
    "com.github.tchx84.Flatseal"
    "it.mijorus.gearlever"
    "org.gimp.GIMP"
    "io.missioncenter.MissionCenter"
    "org.onlyoffice.desktopeditors"
    "org.prismlauncher.PrismLauncher"
    "com.simplenote.Simplenote"
    "io.github.flattool.Warehouse"
    "app.zen_browser.zen"
    #"com.discordapp.Discord"
    "com.mattjakeman.ExtensionManager"
    "com.rustdesk.RustDesk"
    "io.github.kolunmi.Bazaar"
  ];

  # ── Update policy ─────────────────────────────────────────────────────
  # false = install missing apps on rebuild, but do not auto-update existing ones.
  services.flatpak.update.onActivation = false;
}
