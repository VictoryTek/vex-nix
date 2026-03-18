# PhotoGIMP Icon Fix — Specification (Revised)

**Feature:** `photogimp_icon_fix`
**Target file:** `home/photogimp.nix`
**Date:** 2026-03-17
**Iteration:** 2 (replaces previous spec that misdiagnosed root cause)

---

## 1. Current Configuration Analysis

### What is configured in `home/photogimp.nix`

| Component | Current Code | Status |
|-----------|-------------|--------|
| GIMP config copy | `home.activation.installPhotoGIMP` — copies `.var/app/org.gimp.GIMP/config/GIMP/3.0/` into `~/.config/GIMP/3.0/` | Working |
| Icon installation | `xdg.dataFile."icons/hicolor"` (recursive=true) — should create symlinks from PhotoGIMP source | **NOT APPLIED** — files on disk are regular files, not HM symlinks |
| Icon cache rebuild | `home.activation.updatePhotogimpIconCache` — runs `gtk-update-icon-cache --ignore-theme-index --force` | **NOT APPLIED** — no `icon-theme.cache` exists on disk |
| Desktop entry | `xdg.desktopEntries."org.gimp.GIMP"` with `icon = "photogimp"` and `exec = "flatpak run org.gimp.GIMP %U"` | **NOT APPLIED** — file on disk has old `--command=gimp-3.0` Exec |

### Critical: The current code already has the icon cache fix, but it was never applied

The previous spec (now superseded) recommended adding `gtk-update-icon-cache` —
but **this activation script already exists in the current code**. The real
problem is that Home Manager has never successfully activated the current
config for the PhotoGIMP-related files.

### Evidence from the live system (March 17, 2026)

| Check | Expected (from current code) | Actual on disk |
|-------|------------------------------|----------------|
| `readlink ~/.local/share/applications/org.gimp.GIMP.desktop` | Nix store symlink | **NOT a symlink** (regular file, 11126 bytes) |
| `grep ^Exec= org.gimp.GIMP.desktop` | `flatpak run org.gimp.GIMP %U` | `/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=gimp-3.0 ...` |
| `readlink ~/.local/share/icons/hicolor/128x128/apps/photogimp.png` | Nix store symlink | **NOT a symlink** (regular file) |
| `ls ~/.local/share/icons/hicolor/256x256/apps/photogimp.png` | Exists as symlink | **DOES NOT EXIST** |
| `ls ~/.local/share/icons/hicolor/icon-theme.cache` | Exists (from activation) | **DOES NOT EXIST** |

### Flatpak GIMP state

| Property | Value |
|----------|-------|
| Desktop file | `/var/lib/flatpak/exports/share/applications/org.gimp.GIMP.desktop` |
| Desktop `Name=` | `GNU Image Manipulation Program` |
| Desktop `Icon=` | `org.gimp.GIMP` |
| Desktop `Exec=` | `... --command=gimp-3.2 ...` |
| Icon files | `/var/lib/flatpak/exports/share/icons/hicolor/{size}/apps/org.gimp.GIMP.png` |

### User icon theme

The user's icon theme is **kora** (`gtk.iconTheme.name = "kora"` and
`dconf icon-theme = "kora"`). The kora theme does NOT contain a `photogimp`
icon. For `Icon=photogimp` to resolve, GTK must fall back to hicolor.

---

## 2. Root Cause Analysis

### Root Cause 1 (CRITICAL): Orphaned regular files block Home Manager symlink creation

Previous configuration iterations placed files via `cp` (activation scripts)
or `xdg.dataFile` from an earlier approach. These left **regular files** (not
symlinks) at the paths where the current Home Manager config wants to create
its managed symlinks.

When Home Manager runs `checkLinkTargets`, it detects that:
- `~/.local/share/applications/org.gimp.GIMP.desktop` is a regular file
  where HM wants to place a symlink
- `~/.local/share/icons/hicolor/*/apps/photogimp.png` are regular files
  where HM wants to place symlinks

Home Manager **refuses to overwrite regular files** that it didn't create.
It silently skips these files (or reports a warning that was likely missed
during `nixos-rebuild switch`). As a result, the entire PhotoGIMP icon and
desktop entry configuration is never applied.

**This is the primary reason ALL previous fixes failed** — none of them
addressed the orphaned files that block HM.

### Root Cause 2 (CRITICAL): `Icon=photogimp` relies on fragile theme fallback

Even if Root Cause 1 is fixed and HM applies the config, the desktop entry uses
`Icon=photogimp` (a theme icon name). GNOME Shell must resolve this through:

1. Look in active theme (kora) → **NOT found** (confirmed: no `photogimp` in kora)
2. Fall back to hicolor → must find in `~/.local/share/icons/hicolor/{size}/apps/`

This fallback is fragile on NixOS because:
- The hicolor `index.theme` lives in the Nix store, not `/usr/share/icons/`
- `XDG_DATA_DIRS` varies between the GNOME session and terminal sessions
- The user's `~/.local/share/icons/hicolor/` has no `index.theme`
- Some GTK implementations may not properly merge user-local hicolor icons
  with system-installed hicolor icons

### Root Cause 3: Missing 256×256 icon file

The `256x256/apps/photogimp.png` icon is **missing** from the user's hicolor
directory, while all other sizes (16, 32, 48, 64, 128, 512) are present.
This is the resolution GNOME Shell typically uses for app grid icons on HiDPI.

A stray file `256x256/256x256.png` (wrong filename, not inside `apps/`)
exists instead — from a previous iteration or the main branch of the repo.

### Root Cause 4: GIMP version mismatch in Exec

The desktop file on disk uses `--command=gimp-3.0` but the Flatpak GIMP is
now at version 3.2. The current code correctly uses `flatpak run org.gimp.GIMP %U`
without hardcoding a version, but this fix was never applied (see Root Cause 1).

---

## 3. Proposed Solution

### Strategy: Absolute icon path + orphan cleanup + keep existing icon theme integration

**Three changes** to `home/photogimp.nix`:

1. **Add orphan cleanup activation script** — Remove non-symlink files at paths
   HM wants to manage, running BEFORE `checkLinkTargets`
2. **Change `Icon=` to absolute Nix store path** — Bypass icon theme lookup entirely
3. **Remove `updatePhotogimpIconCache` activation script** — No longer needed with
   absolute path; simplifies the module

### Why absolute path instead of icon theme name

| Approach | Reliability | Complexity |
|----------|-------------|------------|
| `Icon=photogimp` (theme name) | Depends on kora→hicolor fallback, `XDG_DATA_DIRS`, `icon-theme.cache`, `index.theme` presence | High (many moving parts) |
| `Icon=/nix/store/.../photogimp.png` (absolute path) | GNOME reads file directly from Nix store | Very low |

The Nix store path is stable (changes only when PhotoGIMP source hash changes).
The HM generation keeps a GC root to the PhotoGIMP derivation, preventing
garbage collection while the config is active.

---

## 4. Exact Code Changes

### File: `home/photogimp.nix`

#### Change 1: Add orphan cleanup activation script

**Add** this new activation script inside `config = lib.mkIf config.photogimp.enable { ... };`:

```nix
# ── Cleanup orphaned files from previous config iterations ──────────
# Removes regular files (not symlinks) that block Home Manager from
# creating its managed symlinks. Must run BEFORE checkLinkTargets.
home.activation.cleanupPhotogimpOrphanFiles =
  lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
    if [ -f "$DESKTOP_FILE" ] && [ ! -L "$DESKTOP_FILE" ]; then
      $VERBOSE_ECHO "PhotoGIMP: removing orphaned desktop file (not a symlink)"
      $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
    fi

    for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
      ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
      if [ -f "$ICON_FILE" ] && [ ! -L "$ICON_FILE" ]; then
        $VERBOSE_ECHO "PhotoGIMP: removing orphaned icon $size/apps/photogimp.png"
        $DRY_RUN_CMD rm -f "$ICON_FILE"
      fi
    done

    for stray in \
      "$HOME/.local/share/icons/hicolor/photogimp.png" \
      "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
      if [ -f "$stray" ] && [ ! -L "$stray" ]; then
        $VERBOSE_ECHO "PhotoGIMP: removing stray file $stray"
        $DRY_RUN_CMD rm -f "$stray"
      fi
    done
  '';
```

#### Change 2: Change Icon= to absolute path

**Replace** in `xdg.desktopEntries."org.gimp.GIMP"`:

```nix
# BEFORE:
icon = "photogimp";

# AFTER:
icon = "${photogimp}/.local/share/icons/hicolor/256x256/apps/photogimp.png";
```

#### Change 3: Remove icon cache activation script

**Remove** the entire `home.activation.updatePhotogimpIconCache` block.
With an absolute icon path, the icon theme cache is not needed for the
desktop entry to display correctly. The `xdg.dataFile."icons/hicolor"`
still installs icons into hicolor for any third-party tools that look up
the `photogimp` icon name by theme, and GTK can discover those without
a cache (slower but functional).

#### No other changes needed

- `home.activation.installPhotoGIMP` — Keep as-is (GIMP config copy works correctly)
- `xdg.dataFile."icons/hicolor"` — Keep as-is (provides icons for theme-based lookup as secondary measure; will now create proper symlinks after orphan cleanup)
- `xdg.desktopEntries."org.gimp.GIMP"` remaining fields — Keep as-is

### Files NOT modified

- `home/default.nix` — No changes
- `modules/gnome.nix` — No changes
- `modules/flatpak.nix` — No changes
- `flake.nix` — No changes
- `hosts/default/configuration.nix` — No changes

---

## 5. Complete Revised Module

```nix
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
    hash = "sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=";
  };
in
{
  options.photogimp.enable = lib.mkEnableOption "PhotoGIMP GIMP configuration overlay";

  config = lib.mkIf config.photogimp.enable {

    # ── Cleanup orphaned files from previous config iterations ──────────
    # Previous configs placed regular files (via cp) where Home Manager now
    # needs to create symlinks. HM refuses to overwrite non-HM-managed files,
    # so this script removes them before checkLinkTargets runs.
    home.activation.cleanupPhotogimpOrphanFiles =
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
        if [ -f "$DESKTOP_FILE" ] && [ ! -L "$DESKTOP_FILE" ]; then
          $VERBOSE_ECHO "PhotoGIMP: removing orphaned desktop file (not a symlink)"
          $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
        fi

        for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
          ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
          if [ -f "$ICON_FILE" ] && [ ! -L "$ICON_FILE" ]; then
            $VERBOSE_ECHO "PhotoGIMP: removing orphaned icon $size/apps/photogimp.png"
            $DRY_RUN_CMD rm -f "$ICON_FILE"
          fi
        done

        for stray in \
          "$HOME/.local/share/icons/hicolor/photogimp.png" \
          "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
          if [ -f "$stray" ] && [ ! -L "$stray" ]; then
            $VERBOSE_ECHO "PhotoGIMP: removing stray file $stray"
            $DRY_RUN_CMD rm -f "$stray"
          fi
        done
      '';

    # ── PhotoGIMP GIMP config files ─────────────────────────────────────
    # Copies all files from PhotoGIMP's .var/app/org.gimp.GIMP/config/GIMP/3.0/
    # into the user's GIMP config directory. Only runs when the PhotoGIMP
    # version changes (or on first install) to preserve user's runtime
    # GIMP customisations.
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

    # ── PhotoGIMP icons (secondary — for theme-based icon lookup) ───────
    # Installs PhotoGIMP icons into the user hicolor icon theme so tools
    # that look up icons by theme name can find "photogimp". The desktop
    # entry uses an absolute path (below), so this is a supplementary measure.
    xdg.dataFile."icons/hicolor" = {
      source    = photogimp + "/.local/share/icons/hicolor";
      recursive = true;
    };

    # ── PhotoGIMP .desktop entry ─────────────────────────────────────────
    # Overrides the Flatpak GIMP launcher with PhotoGIMP branding.
    # Uses an absolute Nix store path for Icon= to bypass icon theme
    # lookup entirely — the most reliable approach on NixOS where the
    # kora→hicolor fallback chain can break due to non-standard
    # XDG_DATA_DIRS, missing index.theme, or absent icon-theme.cache.
    xdg.desktopEntries."org.gimp.GIMP" = {
      name          = "PhotoGIMP";
      genericName   = "Image Editor";
      comment       = "Create images and edit photographs";
      exec          = "flatpak run org.gimp.GIMP %U";
      icon          = "${photogimp}/.local/share/icons/hicolor/256x256/apps/photogimp.png";
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
```

---

## 6. Implementation Steps

1. **Edit `home/photogimp.nix`** — Apply all three changes:
   - Add `cleanupPhotogimpOrphanFiles` activation script (before `checkLinkTargets`)
   - Change `icon` to absolute Nix store path
   - Remove `updatePhotogimpIconCache` activation script
2. **No changes** to any other files
3. **Build** — `nix flake check` and `sudo nixos-rebuild build --flake .#vexos`
4. **Apply** — `sudo nixos-rebuild switch --flake .#vexos`
5. **Verify** — Log out and back in, check GNOME app grid for blue PhotoGIMP icon

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Nix store icon path garbage-collected | Very Low | HM generation holds a GC root to the PhotoGIMP derivation |
| Cleanup script removes user-intentional files | Very Low | Only removes regular files (not symlinks) at known PhotoGIMP paths; checks `! -L` before removal |
| GIMP Flatpak changes app ID | Very Low | `org.gimp.GIMP` is the established Flatpak app ID, extremely unlikely to change |
| Absolute path looks unusual in desktop file | Cosmetic only | No functional impact; GNOME Shell handles absolute `Icon=` paths per freedesktop spec |
| First activation requires logout/login | Expected | GNOME Shell on Wayland cannot be restarted in-session; documented as expected behavior |

---

## 8. Why Previous Attempts Failed

| Attempt | Why It Failed |
|---------|---------------|
| Using `Icon=photogimp` with `xdg.dataFile` for icons | Orphaned regular files blocked HM symlink creation → icons never placed by HM → `photogimp` not found in theme → GNOME shows default GIMP icon |
| Adding `gtk-update-icon-cache` activation script | Script was added but never executed because HM config was never applied (same orphan file issue); even if it ran, the cache alone doesn't fix the theme fallback chain on NixOS |
| Placing `.desktop` file from PhotoGIMP repo via `xdg.dataFile` or `cp` | Creates regular files that block subsequent HM `xdg.desktopEntries`; Exec line hardcodes `gimp-3.0` but Flatpak GIMP is now at 3.2 |
| All previous approaches used `Icon=photogimp` (theme name) | Theme-name-based lookup requires kora→hicolor fallback, which is unreliable on NixOS due to non-standard `XDG_DATA_DIRS`, missing `index.theme` in user hicolor, and absent `icon-theme.cache` |

**Core insight:** The fundamental problem is twofold:
1. Orphaned regular files from early iterations permanently blocked all subsequent HM-based fixes
2. Icon theme name lookup is inherently fragile on NixOS — absolute path is the only reliable approach

---

## 9. Verification Checklist

After applying the fix and rebuilding:

- [ ] `readlink ~/.local/share/applications/org.gimp.GIMP.desktop` → points to Nix store (is a symlink)
- [ ] `grep ^Icon= ~/.local/share/applications/org.gimp.GIMP.desktop` → shows `/nix/store/.../photogimp.png`
- [ ] `grep ^Exec= ~/.local/share/applications/org.gimp.GIMP.desktop` → shows `flatpak run org.gimp.GIMP %U`
- [ ] `readlink ~/.local/share/icons/hicolor/256x256/apps/photogimp.png` → points to Nix store (HM symlink)
- [ ] `ls ~/.local/share/icons/hicolor/256x256/256x256.png` → file removed (stray)
- [ ] After logout/login: GNOME app grid shows blue PhotoGIMP icon, not orange GIMP icon

---

## 10. References

1. [XDG Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/latest/) — icon search paths, cache format, theme structure
2. [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) — `$XDG_DATA_HOME` > `$XDG_DATA_DIRS` precedence
3. [PhotoGIMP 3.0 icon files](https://github.com/Diolinux/PhotoGIMP/tree/3.0/.local/share/icons/hicolor) — confirmed `photogimp.png` in `{size}/apps/` subdirectories
4. [PhotoGIMP 3.0 desktop file](https://raw.githubusercontent.com/Diolinux/PhotoGIMP/3.0/.local/share/applications/org.gimp.GIMP.desktop) — `Icon=photogimp`, `Name=PhotoGIMP`
5. [Home Manager xdg.desktopEntries](https://nix-community.github.io/home-manager/options.xhtml#opt-xdg.desktopEntries) — generates files in `~/.local/share/applications/`
6. [Home Manager checkLinkTargets](https://github.com/nix-community/home-manager) — refuses to overwrite regular files not managed by HM
7. [Flatpak Command Reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html) — system exports to `/var/lib/flatpak/exports/share/`
8. [freedesktop.org Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/) — `Icon=` accepts both theme names and absolute paths
