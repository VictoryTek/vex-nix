# home/photogimp.nix
#
# PhotoGIMP: Transforms GIMP's interface to resemble Adobe Photoshop.
# Source: https://github.com/Diolinux/PhotoGIMP
#
# Strategy: fetch PhotoGIMP at build time (pkgs.fetchFromGitHub), then copy
# config files into ~/.config/GIMP/3.0/ at activation time. Copy (not
# symlink) is required because GIMP writes to its own config directory at
# runtime. A version sentinel file prevents re-copying on every switch,
# preserving any runtime changes the user makes to GIMP settings.
#
# Works with: GIMP 3.0+ (Flatpak org.gimp.GIMP or native pkgs.gimp)
# Config target: ~/.config/GIMP/3.0/

{ config, lib, pkgs, ... }:

let
  photogimpVersion = "3.0";

  photogimp = pkgs.fetchFromGitHub {
    owner = "Diolinux";
    repo  = "PhotoGIMP";
    rev   = photogimpVersion;
    # Obtain the correct hash by running:
    #   nix-prefetch-url --unpack \
    #     "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
    # OR: set hash = ""; and Nix will report the correct hash on the first
    # failed build attempt — replace the empty string with the reported value.
    hash = "sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=";
  };
in
{
  options.photogimp.enable = lib.mkEnableOption "PhotoGIMP GIMP configuration overlay";

  config = lib.mkIf config.photogimp.enable {
    # ── PhotoGIMP GIMP config files ─────────────────────────────────────────
    # Copies all files from PhotoGIMP's .var/app/org.gimp.GIMP/config/GIMP/3.0/
    # (the layout used in the 3.0 tag) into the user's GIMP config directory.
    # Only runs when the PhotoGIMP version changes
    # (or on first install) to preserve user's runtime GIMP customisations.
    home.activation.installPhotoGIMP = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      GIMP_CONFIG="$HOME/.config/GIMP/3.0"
      VERSION_FILE="$GIMP_CONFIG/.photogimp-version"

      if [ ! -f "$VERSION_FILE" ] || \
         [ "$(${pkgs.coreutils}/bin/cat "$VERSION_FILE" 2>/dev/null)" != "${photogimpVersion}" ]; then
        $VERBOSE_ECHO "PhotoGIMP: installing version ${photogimpVersion} config files"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$GIMP_CONFIG"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rf \
          ${photogimp}/.var/app/org.gimp.GIMP/config/GIMP/3.0/. \
          "$GIMP_CONFIG/"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$GIMP_CONFIG/"
        if [ -z "$DRY_RUN_CMD" ]; then
          ${pkgs.coreutils}/bin/printf '%s' "${photogimpVersion}" > "$VERSION_FILE"
        fi
      fi
    '';

    # ── PhotoGIMP icon theme cache ───────────────────────────────────────────
    # Rebuilds the GTK hicolor icon theme cache after xdg.dataFile places the
    # PhotoGIMP icon symlinks. Without this, GTK cannot find Icon=photogimp
    # and silently falls back to the GIMP icon.
    home.activation.updatePhotogimpIconCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $VERBOSE_ECHO "PhotoGIMP: updating hicolor icon theme cache"
      if [ -d "$HOME/.local/share/icons/hicolor" ]; then
        $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache \
          --ignore-theme-index \
          --force \
          "$HOME/.local/share/icons/hicolor"
      fi
    '';

    # ── PhotoGIMP icons ─────────────────────────────────────────────────────
    # Installs PhotoGIMP-branded icons into the user hicolor icon theme.
    # Uses recursive = true so individual per-file symlinks are created,
    # which is safe alongside other icon themes already in hicolor/.
    xdg.dataFile."icons/hicolor" = {
      source    = photogimp + "/.local/share/icons/hicolor";
      recursive = true;
    };

    # ── PhotoGIMP .desktop entry ─────────────────────────────────────────────
    # Overrides the GIMP launcher name and icon with the PhotoGIMP branding.
    # Uses xdg.desktopEntries (Home Manager declarative API) instead of
    # xdg.dataFile to avoid:
    #   1. Shadowing the Flatpak export via $XDG_DATA_HOME
    #   2. Broken Exec=/usr/bin/flatpak (nonexistent on NixOS)
    #   3. Stale --command=gimp-2.10 (GIMP 3.0 uses 'gimp')
    # Generated via pkgs.makeDesktopItem; installed with lib.hiPrio.
    xdg.desktopEntries."org.gimp.GIMP" = {
      name          = "PhotoGIMP";
      genericName   = "Image Editor";
      comment       = "Create images and edit photographs";
      exec          = "flatpak run org.gimp.GIMP %U";
      icon          = "photogimp";
      terminal      = false;
      startupNotify = true;
      categories    = [ "Graphics" "2DGraphics" "RasterGraphics" "GTK" ];
      mimeType      = [
        "image/bmp"
        "image/g3fax"
        "image/gif"
        "image/jpeg"
        "image/png"
        "image/tiff"
        "image/webp"
        "image/heif"
        "image/heic"
        "image/svg+xml"
        "image/x-bmp"
        "image/x-compressed-xcf"
        "image/x-exr"
        "image/x-gimp-gbr"
        "image/x-gimp-gih"
        "image/x-gimp-pat"
        "image/x-icon"
        "image/x-pcx"
        "image/x-portable-anymap"
        "image/x-portable-bitmap"
        "image/x-portable-graymap"
        "image/x-portable-pixmap"
        "image/x-psd"
        "image/x-sgi"
        "image/x-tga"
        "image/x-wmf"
        "image/x-xcf"
        "image/x-xcursor"
        "image/x-xpixmap"
        "image/x-xwindowdump"
        "image/jp2"
        "application/pdf"
        "application/postscript"
      ];
    };
  };
}
