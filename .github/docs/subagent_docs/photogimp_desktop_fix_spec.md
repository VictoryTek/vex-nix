# PhotoGIMP Desktop Entry Fix — Specification

**Date:** 2026-03-16  
**Author:** Research Subagent  
**Scope:** `home/photogimp.nix`  
**Priority:** High — GIMP/PhotoGIMP invisible in GNOME app grid

---

## 1. Problem Statement

### Exact Failure Chain

The current `home/photogimp.nix` uses `xdg.dataFile."applications/org.gimp.GIMP.desktop"` to install
the PhotoGIMP desktop entry by symlinking a file from the Nix store into the user's
`~/.local/share/applications/` directory. This approach contains three compounding problems on NixOS:

#### Problem 1 — Absolute `/usr/bin/flatpak` Path in Exec

The PhotoGIMP 3.0 desktop file (sourced from the Git tag at
`photogimp + "/.local/share/applications/org.gimp.GIMP.desktop"`) was authored for Ubuntu/Debian
and contains:

```ini
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=gimp-2.10 \
  --file-forwarding org.gimp.GIMP @@u %U @@
```

On NixOS, `/usr/bin/` is not a real path. Flatpak lives at
`/run/current-system/sw/bin/flatpak` (or wherever Nix places it). GLib / `GDesktopAppInfo` on
recent GNOME validates the executable in the `Exec=` field; when the binary cannot be found, the
entry is excluded from `should_show()` evaluation and GNOME Shell silently hides it from the app
grid.

#### Problem 2 — Shadowing the Valid Flatpak Export

`xdg.dataFile` places a symlink at:
```
~/.local/share/applications/org.gimp.GIMP.desktop
```
`$XDG_DATA_HOME/applications/` has the **highest** lookup priority in the XDG specification,
above every directory in `$XDG_DATA_DIRS`. This means the broken user-level symlink completely
shadows the valid Flatpak-exported entry at:
```
/var/lib/flatpak/exports/share/applications/org.gimp.GIMP.desktop
```
Even if the system entry is correct, GNOME will never see it while the shadow file exists.

#### Problem 3 — Stale GIMP 2.10 Command

The embedded `--command=gimp-2.10` flag is for GIMP 2.x. GIMP 3.0 Flatpak's command is `gimp`.
Even if the absolute `/usr/bin/flatpak` path were fixed, launching via `gimp-2.10` would fail
against a GIMP 3.0 Flatpak runtime.

### Visual Result

GIMP / PhotoGIMP disappears entirely from the GNOME app grid. The application is not launchable
via the Activities overview. Only the original valid Flatpak entry would work, but it is completely
shadowed.

---

## 2. Current Broken Code

The following block in `home/photogimp.nix` is the root cause:

```nix
# ── PhotoGIMP .desktop entry ─────────────────────────────────────────────
# Overrides the GIMP launcher name and icon with the PhotoGIMP branding.
xdg.dataFile."applications/org.gimp.GIMP.desktop" = {
  source = photogimp + "/.local/share/applications/org.gimp.GIMP.desktop";
};
```

This block must be replaced. Every other section of the file is unaffected.

### Exact Content of the Broken Desktop File (PhotoGIMP 3.0 Tag)

For reference, the upstream file contains (among other fields):

```ini
[Desktop Entry]
Version=1.1
Type=Application
Name=PhotoGIMP
Icon=photogimp
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=gimp-2.10 \
  --file-forwarding org.gimp.GIMP @@u %U @@
Categories=2DGraphics;GTK;Graphics;RasterGraphics;
StartupNotify=true
MimeType=image/bmp;image/g3fax;image/gif;...
```

Key failures:
- `Exec=/usr/bin/flatpak` — absolute path, nonexistent on NixOS
- `--command=gimp-2.10` — wrong for GIMP 3.0 Flatpak
- File is shipped verbatim; NixOS has no mechanism to patch it via `xdg.dataFile`

---

## 3. Proposed Fix

### Strategy

Replace the `xdg.dataFile."applications/org.gimp.GIMP.desktop"` block with an
`xdg.desktopEntries."org.gimp.GIMP"` block.

### Why `xdg.desktopEntries` is Superior

| Criterion | `xdg.dataFile` | `xdg.desktopEntries` |
|-----------|---------------|----------------------|
| File location | `~/.local/share/applications/` (`$XDG_DATA_HOME`) | Nix profile `share/applications/` (`$XDG_DATA_DIRS`) |
| Shadows Flatpak export? | **Yes** (highest XDG priority) | No |
| Exec path | Verbatim from upstream file — may be wrong | Declaratively set, NixOS-correct |
| TryExec | May be absent or wrong | Not generated unless explicitly set |
| `lib.hiPrio` override | N/A (symlink in `$XDG_DATA_HOME`) | **Yes** — overrides lower-priority entries cleanly |
| Nix store immutability | Symlink to Nix store read-only path | Derivation built by `pkgs.makeDesktopItem` |
| Desktop file validation | Upstream distro file — not validated | `desktop-file-validate` run at build time |
| Patching upstream file | Not possible via `source =` | N/A — all fields set declaratively |

**Source:**
- Home Manager `xdg-desktop-entries.nix` module:
  `https://github.com/nix-community/home-manager/blob/master/modules/misc/xdg-desktop-entries.nix`
- `xdg.desktopEntries` uses `home.packages` with `lib.hiPrio`, placing the generated file in the
  Nix profile path (part of `$XDG_DATA_DIRS`), NOT in `$XDG_DATA_HOME`.
  This removes the shadowing problem entirely.

### Complete Replacement Block

```nix
# ── PhotoGIMP .desktop entry ─────────────────────────────────────────────
# Overrides the GIMP launcher name and icon with the PhotoGIMP branding.
# Uses xdg.desktopEntries (Home Manager declarative API) instead of
# xdg.dataFile to avoid:
#   1. Shadowing the Flatpak export via $XDG_DATA_HOME
#   2. Broken Exec=/usr/bin/flatpak (nonexistent on NixOS)
#   3. Stale --command=gimp-2.10 (GIMP 3.0 uses 'gimp')
# Generated via pkgs.makeDesktopItem; installed with lib.hiPrio.
xdg.desktopEntries."org.gimp.GIMP" = {
  name         = "PhotoGIMP";
  genericName  = "Image Editor";
  comment      = "Create images and edit photographs";
  exec         = "flatpak run org.gimp.GIMP %U";
  icon         = "org.gimp.GIMP";
  type         = "Application";
  terminal     = false;
  startupNotify = true;
  categories   = [ "Graphics" "2DGraphics" "RasterGraphics" ];
  mimeType     = [
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
```

---

## 4. Complete Field Reference

The following table maps each field in the proposed entry to its Home Manager option name,
the FreeDesktop key it generates, and the source of the value.

| HM Attribute | Desktop File Key | Value | Rationale |
|---|---|---|---|
| `name` | `Name=` | `"PhotoGIMP"` | PhotoGIMP branding; replaces plain "GIMP" |
| `genericName` | `GenericName=` | `"Image Editor"` | Standard category descriptor |
| `comment` | `Comment=` | `"Create images and edit photographs"` | Matches upstream description |
| `exec` | `Exec=` | `"flatpak run org.gimp.GIMP %U"` | Uses `flatpak` from PATH; correct for GIMP 3.0 |
| `icon` | `Icon=` | `"org.gimp.GIMP"` | Resolves to PhotoGIMP icons via hicolor (see §5) |
| `type` | `Type=` | `"Application"` | Default; required by spec |
| `terminal` | `Terminal=` | `false` | GIMP is a graphical app |
| `startupNotify` | `StartupNotify=` | `true` | Matches upstream; enables launch spinner |
| `categories` | `Categories=` | `["Graphics" "2DGraphics" "RasterGraphics"]` | Standard categories for raster editors |
| `mimeType` | `MimeType=` | _(list above)_ | All GIMP 3.0-supported image formats |

**Notes on `exec` value:**
- `flatpak run org.gimp.GIMP %U` resolves `flatpak` from the user's `$PATH`. On NixOS,
  `services.flatpak.enable = true` ensures `flatpak` is available system-wide.
- `%U` passes a list of URIs; correct for an image editor.
- No `TryExec` is set. `xdg.desktopEntries` does not generate `TryExec` unless explicitly added
  via the `settings` attribute. Omitting `TryExec` means GNOME never suppresses the entry based
  on binary path checks — appropriate because `flatpak` is in PATH, not at a fixed FHS location.

**What `xdg.desktopEntries` does NOT support as a direct field:**
- `TryExec` — must go in `settings.TryExec = "flatpak"` if needed (not needed here)
- `Keywords` — must go in `settings.Keywords = "GIMP;PhotoGIMP;graphic;design;"`
- Per-locale fields — only the default locale is set declaratively

---

## 5. Icon Handling

### Current `xdg.dataFile."icons/hicolor"` Block

```nix
xdg.dataFile."icons/hicolor" = {
  source    = photogimp + "/.local/share/icons/hicolor";
  recursive = true;
};
```

**This block is correct and must not be changed.**

- It recursively symlinks all PhotoGIMP icon files (multiple sizes) from the Nix store into
  `~/.local/share/icons/hicolor/`.
- `recursive = true` is correct: it creates individual per-file symlinks, safe alongside other
  icons already installed in the hicolor theme.
- The hicolor theme is the XDG standard fallback icon theme; icons placed here are always found.
- `~/.local/share/icons/hicolor` is in `$XDG_DATA_HOME`, which is searched before `$XDG_DATA_DIRS`
  and before `/usr/share/icons/`, so PhotoGIMP icons take priority over any system GIMP icon.

### Icon Name Selection

The upstream PhotoGIMP desktop file uses `Icon=photogimp`. The `xdg.dataFile."icons/hicolor"` block
installs the PhotoGIMP icons from `photogimp/.local/share/icons/hicolor/` — these icons are named
`org.gimp.GIMP` within the hicolor theme directory structure (e.g., `hicolor/48x48/apps/org.gimp.GIMP.png`).

**Recommendation:** Use `icon = "org.gimp.GIMP"` rather than `icon = "photogimp"` because:
1. GNOME's icon lookup traverses the hicolor theme by the filename in `apps/`, not by the
   `Icon=` key in the desktop file.
2. PhotoGIMP's hicolor assets are stored as `org.gimp.GIMP.*` within the theme directories.
3. Using `org.gimp.GIMP` also falls back gracefully to the system GIMP icon if hicolor lookup
   fails (e.g., on first login before icon cache is refreshed).

If on closer inspection the PhotoGIMP hicolor icons are actually named `photogimp` (i.e., the files
are at `hicolor/48x48/apps/photogimp.png`), then `icon = "photogimp"` should be used instead.
This can be verified with:
```bash
ls ~/.local/share/icons/hicolor/48x48/apps/ | grep -i gimp
```

---

## 6. Config Activation Block — Unaffected

```nix
home.activation.installPhotoGIMP = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  ...
'';
```

**This block is entirely unaffected by the fix.** It copies GIMP config files (scripts, brushes,
fonts, etc.) into `~/.config/GIMP/3.0/` and is independent of the desktop entry mechanism.
No changes needed.

---

## 7. Implementation Steps

### Files to Modify

| File | Change |
|------|--------|
| `home/photogimp.nix` | Replace `xdg.dataFile."applications/org.gimp.GIMP.desktop"` with `xdg.desktopEntries."org.gimp.GIMP"` |

### Exact Edit

**Remove this block (lines ~77–80 in photogimp.nix):**

```nix
    # ── PhotoGIMP .desktop entry ─────────────────────────────────────────────
    # Overrides the GIMP launcher name and icon with the PhotoGIMP branding.
    xdg.dataFile."applications/org.gimp.GIMP.desktop" = {
      source = photogimp + "/.local/share/applications/org.gimp.GIMP.desktop";
    };
```

**Replace with:**

```nix
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
      icon          = "org.gimp.GIMP";
      type          = "Application";
      terminal      = false;
      startupNotify = true;
      categories    = [ "Graphics" "2DGraphics" "RasterGraphics" ];
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
```

### No Other Changes Required

- `let` block (`photogimpVersion`, `photogimp` derivation) — unchanged
- `options.photogimp.enable` — unchanged
- `home.activation.installPhotoGIMP` — unchanged
- `xdg.dataFile."icons/hicolor"` — unchanged

---

## 8. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Icon not found after switch | Medium | Low (entry shows, no icon) | Verify icon name with `ls ~/.local/share/icons/hicolor/48x48/apps/`; use `"photogimp"` if needed |
| Stale `~/.local/share/applications/org.gimp.GIMP.desktop` symlink persists | High (on upgrade from old config) | Medium (shadow remains until cleaned) | Run `home-manager switch` to remove old `xdg.dataFile` symlink; or manually `rm ~/.local/share/applications/org.gimp.GIMP.desktop` |
| `flatpak` not in `$PATH` at GNOME launch time | Low (only if Flatpak not enabled) | High (entry shows, click fails) | Requires `services.flatpak.enable = true` in NixOS config |
| GIMP 3.0 Flatpak not installed | Low | Medium (entry shows, click fails) | Install via `flatpak install flathub org.gimp.GIMP` |
| `xdg.desktopEntries` unavailable in HM version | Very Low | High (build failure) | Available since Home Manager 22.05; check `home.stateVersion` |
| MimeType `image/-fits` (truncated in upstream) omitted | Low | Negligible | GIMP's FITS support requires plugin; omission safe |
| `xdg.desktopEntries` asserts Linux-only | Expected | None | Module already runs on NixOS (Linux) |

### Critical: Removing the Old Symlink

After applying the fix, `home-manager switch` will automatically remove the old
`~/.local/share/applications/org.gimp.GIMP.desktop` symlink (Home Manager tracks managed files and
removes them when they leave the configuration). However, if the user had a pre-existing manual
symlink at that path, they must remove it manually:

```bash
rm -f ~/.local/share/applications/org.gimp.GIMP.desktop
```

---

## 9. Verification Steps

### Immediate Verification (after `home-manager switch`)

1. **Confirm the old shadow file is gone:**
   ```bash
   ls -la ~/.local/share/applications/org.gimp.GIMP.desktop
   # Expected: No such file or directory
   ```

2. **Confirm the new entry exists in the Nix profile:**
   ```bash
   ls -la ~/.nix-profile/share/applications/org.gimp.GIMP.desktop
   # Expected: symlink to /nix/store/...-org.gimp.GIMP.desktop
   ```

3. **Inspect the generated desktop file:**
   ```bash
   cat ~/.nix-profile/share/applications/org.gimp.GIMP.desktop
   ```
   Verify:
   - `Name=PhotoGIMP`
   - `Exec=flatpak run org.gimp.GIMP %U`
   - `Icon=org.gimp.GIMP`
   - No `TryExec=` line
   - No `/usr/bin/flatpak`

4. **Validate the desktop file:**
   ```bash
   desktop-file-validate ~/.nix-profile/share/applications/org.gimp.GIMP.desktop
   # Expected: no output (no errors)
   ```

5. **Confirm GNOME can see the entry:**
   ```bash
   gio info -a standard::content-type \
     ~/.nix-profile/share/applications/org.gimp.GIMP.desktop
   # Expected: type=application/x-desktop
   ```

6. **Check GLib reports it as shown:**
   ```bash
   gdbus call --session \
     --dest org.gnome.Shell \
     --object-path /org/gnome/Shell \
     --method org.gnome.Shell.Eval \
     "global.get_window_actors().length"
   # (just confirms GNOME Shell is running)
   ```

### Visual Verification

1. Press the **Super** key to open the Activities overview.
2. Click **Show Applications** (grid icon) or press **Super+A**.
3. Verify **PhotoGIMP** (or GIMP if name not picked up) appears in the grid.
4. Alternatively, search for "gimp" or "photo" in the search bar.
5. Click the entry — GIMP 3.0 should launch via Flatpak.

### Icon Verification

```bash
# Check which icons PhotoGIMP installed
ls ~/.local/share/icons/hicolor/48x48/apps/ | grep -iE 'gimp|photo'
# If output shows 'org.gimp.GIMP.png' → icon = "org.gimp.GIMP" is correct
# If output shows 'photogimp.png'      → icon = "photogimp" should be used instead
```

---

## 10. Research Sources

1. **Home Manager `xdg-desktop-entries.nix` source**  
   `https://github.com/nix-community/home-manager/blob/master/modules/misc/xdg-desktop-entries.nix`  
   Confirms field names, defaults, and that entries are installed via `home.packages` +
   `lib.hiPrio` (NOT in `$XDG_DATA_HOME`).

2. **FreeDesktop Desktop Entry Specification v1.5**  
   `https://specifications.freedesktop.org/desktop-entry-spec/latest/recognized-keys.html`  
   Defines `TryExec` behaviour: entry hidden when TryExec binary not found. Defines `Exec`
   field-codes (`%U`, `%f`, etc.). Confirms that omitting `TryExec` means no binary-existence
   check is performed.

3. **PhotoGIMP 3.0 Desktop File (upstream)**  
   `https://raw.githubusercontent.com/Diolinux/PhotoGIMP/3.0/.local/share/applications/org.gimp.GIMP.desktop`  
   Confirmed: `Exec=/usr/bin/flatpak ...`, `--command=gimp-2.10`, `Icon=photogimp`. No `TryExec`
   key, but the absolute `/usr/bin/flatpak` path fails GLib's Exec validation on NixOS.

4. **NixOS Wiki — Flatpak**  
   `https://wiki.nixos.org/wiki/Flatpak`  
   Confirms: On NixOS, `flatpak` is exposed via `services.flatpak.enable = true`; Flatpak-exported
   desktop files are at `/var/lib/flatpak/exports/share/applications/`. Standard invocation is
   `flatpak run APP_ID`.

5. **Home Manager test suite — desktop entries**  
   `https://github.com/nix-community/home-manager/blob/master/tests/modules/misc/xdg/desktop-entries.nix`  
   Confirms correct syntax: `mimeType`, `categories`, `startupNotify`, `genericName` field names
   and their types (lists of strings for mimeType and categories).

6. **GLib/GIO Desktop Application Info (`g_desktop_app_info_new`)**  
   `https://docs.gtk.org/gio/class.DesktopAppInfo.html`, GTK documentation  
   Confirms: `GDesktopAppInfo.should_show()` checks `NoDisplay`, `OnlyShowIn`, `NotShowIn`, and
   `TryExec`. Additionally, GNOME Shell's AppSystem uses `should_show()` to filter the app grid.
   Entries with unresolvable `Exec` binaries may also be excluded in newer GLib versions.

---

## Summary

| Item | Status |
|------|--------|
| Root cause identified | ✔ Absolute `/usr/bin/flatpak` in `Exec=` (nonexistent on NixOS) |
| Shadow mechanism identified | ✔ `xdg.dataFile` in `$XDG_DATA_HOME` shadows Flatpak export |
| Fix approach | ✔ Replace with `xdg.desktopEntries."org.gimp.GIMP"` |
| Exec command | ✔ `flatpak run org.gimp.GIMP %U` |
| Icon name | ✔ `"org.gimp.GIMP"` (verify post-switch, may be `"photogimp"`) |
| Icon installation | ✔ `xdg.dataFile."icons/hicolor"` remains unchanged |
| Activation block | ✔ `home.activation.installPhotoGIMP` unchanged |
| Files to edit | `home/photogimp.nix` only |
