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
    # Copies all files from PhotoGIMP's .config/GIMP/3.0/ into the user's
    # GIMP config directory. Only runs when the PhotoGIMP version changes
    # (or on first install) to preserve user's runtime GIMP customisations.
    home.activation.installPhotoGIMP = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      GIMP_CONFIG="$HOME/.config/GIMP/3.0"
      VERSION_FILE="$GIMP_CONFIG/.photogimp-version"

      if [ ! -f "$VERSION_FILE" ] || \
         [ "$(${pkgs.coreutils}/bin/cat "$VERSION_FILE" 2>/dev/null)" != "${photogimpVersion}" ]; then
        $VERBOSE_ECHO "PhotoGIMP: installing version ${photogimpVersion} config files"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$GIMP_CONFIG"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rf \
          ${photogimp}/.config/GIMP/3.0/. \
          "$GIMP_CONFIG/"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$GIMP_CONFIG/"
        if [ -z "$DRY_RUN_CMD" ]; then
          ${pkgs.coreutils}/bin/printf '%s' "${photogimpVersion}" > "$VERSION_FILE"
        fi
      fi
    '';

    # ── PhotoGIMP icons ─────────────────────────────────────────────────────
    # Installs PhotoGIMP-branded icons into the user hicolor icon theme.
    # Uses recursive = true so individual per-file symlinks are created,
    # which is safe alongside other icon themes already in hicolor/.
    #
    # NOTE: The .desktop file override (org.gimp.GIMP.desktop) is intentionally
    # omitted. VexOS installs GIMP via Flatpak (nix-flatpak), and the Flatpak
    # runtime will overwrite any user-local .desktop file when GIMP is installed
    # or updated. The GIMP layout/shortcuts/theme changes still apply — only the
    # launcher name ("PhotoGIMP") and icon in the app grid are cosmetically skipped.
    xdg.dataFile."icons/hicolor" = {
      source    = photogimp + "/.local/share/icons/hicolor";
      recursive = true;
    };
  };
}
