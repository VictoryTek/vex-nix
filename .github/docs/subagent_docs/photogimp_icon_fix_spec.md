# PhotoGIMP Icon & Name Override — Root Cause Analysis & Fix Specification

**Feature:** `photogimp_icon_fix`  
**Target file:** `home/photogimp.nix`  
**Date:** 2026-03-17  
**Researcher:** Orchestrator Research Agent

---

## 1. Current Configuration Analysis

### What is set up

| Component | Current State |
|-----------|--------------|
| GIMP config copy | `home.activation.installPhotoGIMP` copies `.var/app/org.gimp.GIMP/config/GIMP/3.0/` into `~/.config/GIMP/3.0/` via an `entryAfter ["writeBoundary"]` activation script |
| Icon installation | `xdg.dataFile."icons/hicolor"` (recursive=true) places all icon files from `.local/share/icons/hicolor/` into `~/.local/share/icons/hicolor/` as per-file Nix-store symlinks |
| Desktop entry override | `xdg.desktopEntries."org.gimp.GIMP"` generates `~/.local/share/applications/org.gimp.GIMP.desktop` with `Name=PhotoGIMP`, `Icon=photogimp` |
| Flatpak package | `services.flatpak.packages` includes `"org.gimp.GIMP"` via the **system-level** `nix-flatpak.nixosModules.nix-flatpak` |
| Icon cache update | **NOT CALLED** — no activation hook invokes `gtk-update-icon-cache` |

### What is failing

- GNOME shows the original GIMP icon and name ("GIMP") despite the Home Manager `.desktop` entry declaring `Name=PhotoGIMP` and `Icon=photogimp`.
- The PhotoGIMP-branded icon is not displayed in the GNOME Activities Overview, taskbar, or application grid.

---

## 2. Root Cause Analysis

### Root Cause 1 (CRITICAL): Missing `gtk-update-icon-cache` activation

**How GTK/GNOME finds icons:**

GTK's icon theme engine uses an `icon-theme.cache` binary cache file (one per theme directory) to speed up icon lookups. At GNOME Shell startup or on icon theme reload, the theme engine constructs an in-memory lookup table from these cache files. The search path for icons is:

```
$HOME/.icons/                  (legacy fallback)
$XDG_DATA_HOME/icons/           → ~/.local/share/icons/
$XDG_DATA_DIRS/icons/           → /var/lib/flatpak/exports/share/icons/, /usr/share/icons/, ...
/usr/share/pixmaps/
```

The `hicolor` fallback theme is always searched. GTK looks in `~/.local/share/icons/hicolor/` for the icon named `photogimp`.

**What `xdg.dataFile` does:**

With `recursive = true`, Home Manager creates per-file Nix-store symlinks:
```
~/.local/share/icons/hicolor/128x128/apps/photogimp.png  → /nix/store/...
~/.local/share/icons/hicolor/256x256/apps/photogimp.png  → /nix/store/...
... (and other sizes)
~/.local/share/icons/hicolor/photogimp.png               → /nix/store/... (misplaced root-level file)
```

The icons ARE placed in the correct sub-paths. However:

- **No `~/.local/share/icons/hicolor/icon-theme.cache` is generated.**
- GNOME Shell's GTK icon engine, once loaded, uses the cached theme data. Without a user-directory cache file, GNOME Shell cannot efficiently detect new icons added to that path.
- Even if GTK performs a slow directory traversal (fallback when no cache exists), GNOME Shell's **in-process icon theme singleton** may not re-scan until the `icon-theme.cache`'s modification time changes.
- Result: `photogimp` lookup fails; the `.desktop` entry's `Icon=photogimp` resolves to a blank/generic icon **or** the lookup falls entirely to the Flatpak-exported GIMP desktop file's icon.

**Evidence from PhotoGIMP repo:**

The PhotoGIMP 3.0 release has icons at the correct XDG paths:
```
.local/share/icons/hicolor/128x128/apps/photogimp.png
.local/share/icons/hicolor/16x16/apps/photogimp.png
.local/share/icons/hicolor/256x256/apps/photogimp.png
.local/share/icons/hicolor/32x32/apps/photogimp.png
.local/share/icons/hicolor/48x48/apps/photogimp.png
.local/share/icons/hicolor/512x512/apps/photogimp.png
.local/share/icons/hicolor/64x64/apps/photogimp.png
.local/share/icons/hicolor/photogimp.png   ← misplaced root file (valid fallback for some tools, not XDG compliant)
```

The icon name `photogimp` in the `.desktop` file matches the actual filenames. **The icon name is correct.** The problem is the missing cache, not the name.

---

### Root Cause 2 (CRITICAL): GNOME Shell in-memory icon theme not refreshed

GNOME Shell loads the icon theme into memory once per session (or when the theme setting changes). Even after `gtk-update-icon-cache` updates the on-disk cache:

- A **running** GNOME Shell instance does not automatically re-read the icon cache for changed user directories.
- GNOME Shell monitors the `icon-theme.cache` file's mtime (on some versions); updating it via `gtk-update-icon-cache --force` causes a reload.
- Without the cache file being present at all, GNOME Shell cannot detect the mtime change and never reloads.

**Fix impact:** Once `gtk-update-icon-cache` is called during HM activation AND a session logout/login occurs (or GNOME Shell is restarted via `Alt+F2 → r`), the icon becomes visible. On subsequent switches (where the cache already exists), GNOME Shell detects the mtime change and refreshes.

---

### Root Cause 3: Desktop file lookup priority — Flatpak system exports vs. user overrides

**How nix-flatpak installs GIMP:**

The `services.flatpak.packages` in `modules/flatpak.nix` uses `nix-flatpak.nixosModules.nix-flatpak` — a **NixOS system module**, not a Home Manager module. This installs Flatpak apps system-wide. System Flatpak exports desktop files to:

```
/var/lib/flatpak/exports/share/applications/org.gimp.GIMP.desktop
```

This path is included in `$XDG_DATA_DIRS` for all users.

**XDG precedence rule:**

Per the XDG Base Directory Specification:
- `$XDG_DATA_HOME` (= `~/.local/share`) **has higher priority** than all directories in `$XDG_DATA_DIRS`
- Therefore: `~/.local/share/applications/org.gimp.GIMP.desktop` overrides `/var/lib/flatpak/exports/share/applications/org.gimp.GIMP.desktop`.

**Home Manager's `xdg.desktopEntries` generates:**
- File: `~/.local/share/applications/org.gimp.GIMP.desktop`
- Also runs: `update-desktop-database ~/.local/share/applications` during `writeBoundary`

**The desktop entry override mechanism is correct** and should work per XDG spec. GLib's `GDesktopAppInfo`, used by GNOME, respects this precedence. 

**Potential secondary issue:** If the nix-flatpak systemd service (which runs as a post-activation systemd unit) triggers a GIO application list refresh after Home Manager has finished, GNOME may reload the app list. But since the user-directory file still exists at `~/.local/share/applications/`, GNOME will still prefer it. This is not a root cause.

---

### Root Cause 4: No `index.theme` in user hicolor directory (MINOR)

When `xdg.dataFile` copies the icon hierarchy, it only copies what exists in `.local/share/icons/hicolor/` in the PhotoGIMP repo (which has no `index.theme` file). The `hicolor` theme's `index.theme` lives at `/usr/share/icons/hicolor/index.theme` (system level).

GTK will still search `~/.local/share/icons/hicolor/` because:
1. GTK has built-in knowledge of the `hicolor` fallback theme.
2. The XDG spec does not require a per-user `index.theme` for theme search paths to be valid.

**This is NOT a root cause** but it's worth noting. Some overly-strict icon theme implementations may skip directories without `index.theme`.

---

### Root Cause 5: PhotoGIMP desktop file `Exec` mismatch (INFORMATIONAL)

The PhotoGIMP 3.0 bundled `.desktop` file has this outdated `Exec`:
```
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=gimp-2.10 --file-forwarding org.gimp.GIMP @@u %U @@
```

The current VexOS config correctly overrides this with:
```nix
exec = "flatpak run org.gimp.GIMP %U";
```

This is correct for NixOS (no absolute `/usr/bin/flatpak` assumption, correct GIMP 3.0 invocation). **Not a root cause of the icon issue**, but verifies the existing Exec is fine.

---

## 3. Proposed Solution

### Fix 1 (Required): Add `gtk-update-icon-cache` activation hook

After `writeBoundary` completes (and `xdg.dataFile` has placed the icon symlinks), a new activation entry must run `gtk-update-icon-cache`:

```nix
home.activation.updatePhotogimpIconCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  $VERBOSE_ECHO "PhotoGIMP: updating hicolor icon theme cache"
  if [ -d "$HOME/.local/share/icons/hicolor" ]; then
    $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache \
      --ignore-theme-index \
      --force \
      "$HOME/.local/share/icons/hicolor"
  fi
'';
```

**Notes:**
- `--ignore-theme-index`: Do not require an `index.theme` file in the user hicolor directory.
- `--force`: Always regenerate the cache even if it appears up-to-date (by mtime check).
- `pkgs.gtk3` provides `gtk-update-icon-cache`. This is available because `home-manager.useGlobalPkgs = true` in the flake (so NixOS `pkgs` is used, where `gtk3` is present as a transitive dependency of GNOME).
- The `entryAfter ["writeBoundary"]` ordering guarantees the icons are placed (by HM's `xdg.dataFile` link generation, which runs at `writeBoundary`) before the cache is rebuilt.
- The guard `[ -d "$HOME/.local/share/icons/hicolor" ]` makes it safe even on dry-run or first-install scenarios.

### Fix 2 (Optional but Recommended): Ensure `index.theme` presence for robustness

To be maximally compatible with all GTK/GNOME versions, ensure a minimal `index.theme` is present in the user hicolor directory. Because the system hicolor `index.theme` exists and GTK already knows about hicolor, this is not strictly required. If adding it, it should be placed via a symlink or a small inline file, not via `xdg.dataFile` (to avoid collisions).

This fix is low-priority and **not needed for the core issue**.

### Fix 3 (Documentation): First-activation GNOME Shell restart

After the first `nixos-rebuild switch` with this fix applied, the user must restart GNOME Shell for the icon to appear:

- Wayland (GNOME 45+): **Log out and back in** (GNOME Shell cannot be restarted in-session on Wayland).
- X11: Press `Alt+F2`, type `r`, press Enter.

On subsequent `nixos-rebuild switch` runs, the icon cache mtime will change, and GNOME will pick up the new icon automatically without a restart.

---

## 4. Implementation Steps

1. **Edit `home/photogimp.nix`**: Add the `updatePhotogimpIconCache` activation entry in the `config` block, alongside the existing `installPhotoGIMP` activation.

2. **Add `pkgs.gtk3` to the derivation context**: `pkgs.gtk3` is already available in the module's `pkgs` argument (passed via `home-manager.useGlobalPkgs = true`). No additional imports needed.

3. **Verify ordering**: Ensure the new activation uses `entryAfter ["writeBoundary"]` (same as `installPhotoGIMP`) so it runs after all file writes complete.

4. **Test dry-run safety**: The activation body uses `$DRY_RUN_CMD` so `nixos-rebuild build --dry-run` does not actually mutate the cache.

---

## 5. Exact Nix Code Changes

### `home/photogimp.nix` — add activation hook after the existing `installPhotoGIMP` block

**Add this block inside `config = lib.mkIf config.photogimp.enable { ... };`:**

```nix
# ── GTK hicolor icon cache ───────────────────────────────────────────────
# After xdg.dataFile places PhotoGIMP icon symlinks into ~/.local/share/icons/hicolor/,
# the GTK icon theme cache must be regenerated so GNOME Shell can find 'photogimp'.
# Without this, Icon=photogimp in the .desktop entry resolves to a blank/default icon
# because GNOME Shell's in-memory icon theme has no entry for the newly placed files.
#
# --ignore-theme-index: user hicolor dir has no index.theme (system one at /usr/share/icons/hicolor/ applies)
# --force:              always regenerate, even if mtime appears current
home.activation.updatePhotogimpIconCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  $VERBOSE_ECHO "PhotoGIMP: updating hicolor icon theme cache"
  if [ -d "$HOME/.local/share/icons/hicolor" ]; then
    $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache \
      --ignore-theme-index \
      --force \
      "$HOME/.local/share/icons/hicolor"
  fi
'';
```

**No other changes are required.** The desktop entry override (`xdg.desktopEntries`) and icon placement (`xdg.dataFile`) are correct as-is.

---

## 6. Packages Needed

| Package | nixpkgs attribute | Used for |
|---------|------------------|----------|
| `pkgs.gtk3` | `pkgs.gtk3` (nixos-25.11) | Provides `gtk-update-icon-cache` binary |

**How to reference in module:** Already available via the `pkgs` argument which is the NixOS system pkgs (because `home-manager.useGlobalPkgs = true` is set in `flake.nix`).

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| `pkgs.gtk3` not available in pkgs | Low | `gtk3` is a transitive dependency of GNOME and always present in a GNOME NixOS config; `useGlobalPkgs = true` ensures system pkgs are used |
| `gtk-update-icon-cache` path changes in future nixpkgs | Low | If `gtk3` is superseded by `gtk4`, `gtk-update-icon-cache` is still provided by `gtk3` or a polyfill; pinned to nixos-25.11 |
| GNOME Shell refresh not triggered after first run | Medium | Documented; only affects first activation. Subsequent activations update the mtime of `icon-theme.cache`, which GNOME Shell monitors and uses to trigger a reload |
| `--force` always regenerates cache on every `nixos-rebuild switch` | Low | Rebuilding the cache is a millisecond-level operation; no meaningful performance impact |
| `xdg.dataFile` creates symlinks (not copies); `gtk-update-icon-cache` follows them | None | `gtk-update-icon-cache` resolves symlinks and reads the actual PNG files; this works correctly with Nix store paths |
| nix-flatpak updates GIMP and re-exports desktop file | Low | nix-flatpak exports to `/var/lib/flatpak/exports/`, not `~/.local/share/applications/`; HM's user file always wins at this path |
| Icon cache becomes stale if PhotoGIMP icons change (new version) | Low | The `installPhotoGIMP` activation already uses a version sentinel (`photogimpVersion`); when `photogimpVersion` bumps, `xdg.dataFile` links update automatically (new Nix store path), and the cache rebuild via this fix will regenerate the cache |

---

## 8. Verification

After applying the fix, verify correctness by:

1. Run `nixos-rebuild switch --flake .#vexos`
2. Check that `~/.local/share/icons/hicolor/icon-theme.cache` exists and has a recent mtime
3. Check that `~/.local/share/applications/org.gimp.GIMP.desktop` exists and contains `Icon=photogimp`
4. Log out and back in (Wayland) or restart GNOME Shell (`Alt+F2 → r` on X11)
5. Open GNOME Activities Overview — GIMP should now appear as "PhotoGIMP" with the teal/photoshop-style icon

---

## 9. References

1. [XDG Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/latest/) — defines icon search paths, cache format, and theme directory structure
2. [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) — defines `$XDG_DATA_HOME` > `$XDG_DATA_DIRS` precedence
3. [PhotoGIMP 3.0 `.local/share/icons/hicolor/`](https://github.com/Diolinux/PhotoGIMP/tree/3.0/.local/share/icons/hicolor) — confirmed icon filenames: `photogimp.png` in each size subdirectory
4. [PhotoGIMP 3.0 `.local/share/applications/org.gimp.GIMP.desktop`](https://raw.githubusercontent.com/Diolinux/PhotoGIMP/3.0/.local/share/applications/org.gimp.GIMP.desktop) — confirmed `Icon=photogimp` and `Name=PhotoGIMP`
5. [Arch Wiki — Desktop Entries](https://wiki.archlinux.org/title/Desktop_entries) — user entries in `~/.local/share/applications/` take precedence over system entries; validated update-desktop-database behavior
6. [Flatpak Command Reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html) — system Flatpak exports to `/var/lib/flatpak/exports/share/`, not user home directory
7. [Home Manager xdg.desktopEntries documentation](https://nix-community.github.io/home-manager/options.xhtml#opt-xdg.desktopEntries) — HM writes to `~/.local/share/applications/` and calls `update-desktop-database`
8. [gtk-update-icon-cache man page](https://docs.gtk.org/gtk3/gtk-update-icon-cache.html) — `--force` and `--ignore-theme-index` flags
