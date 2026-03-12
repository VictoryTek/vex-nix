# PhotoGIMP Activation Path Fix — Specification

**Phase:** 1 — Research & Specification  
**Date:** 2026-03-12  
**Status:** Ready for Implementation

---

## Problem Statement

Home Manager activation fails with:

```
Activating installPhotoGIMP
cp: cannot stat '/nix/store/adm0qcpwnaddshdy1q5n1fxr5pd7hpj1-source/.config/GIMP/3.0/.': No such file or directory
```

The activation script in `home/photogimp.nix` references a source path
`.config/GIMP/3.0/` that does not exist inside the PhotoGIMP `3.0` tag archive.

---

## Research Findings

### PhotoGIMP Repository Structure — Tag `3.0` vs `master`

The `rev = "3.0"` in `pkgs.fetchFromGitHub` fetches the **`3.0` release tag**
(commit `078d83a`, released 2025-03-17). The `master` branch was significantly
restructured *after* that tag was cut.

**Tag `3.0` root-level directories** (verified via GitHub Git Trees API):

```
.local/
  share/
    applications/
      org.gimp.GIMP.desktop
    icons/
      hicolor/
        16x16/apps/photogimp.png
        32x32/apps/photogimp.png
        48x48/apps/photogimp.png
        64x64/apps/photogimp.png
        128x128/apps/photogimp.png
        256x256/apps/photogimp.png
        512x512/apps/photogimp.png
        photogimp.png
.var/
  app/
    org.gimp.GIMP/
      config/
        GIMP/
          3.0/           ← GIMP config files live here in tag 3.0
            shortcutsrc
            toolrc
            sessionrc
            dockrc
            gimprc
            contextrc
            colorrc
            controllerrc
            devicerc
            extensionrc
            modifiersrc
            parasiterc
            pluginrc
            profilerc
            tags.xml
            templaterc
            theme.css
            toolrc
            unitrc
            internal-data/
            plug-in-settings/
            splashes/
              splash-screen-2025-v2.png
            tool-options/
docs/
screenshots/
.editorconfig
.gitignore
LICENSE
README.md
```

**Master branch root-level directories** (restructured after `3.0` tag):

```
.config/
  GIMP/
    3.0/           ← NEW layout on master (does NOT exist in tag 3.0)
.local/
  share/
    ...
docs/
screenshots/
```

### Root Cause

The `photogimp.nix` activation script was written against the `master` branch's
**new directory layout** (`.config/GIMP/3.0/`), but the pinned `rev = "3.0"`
fetches the **old tag layout** where GIMP config files are under
`.var/app/org.gimp.GIMP/config/GIMP/3.0/`.

The official `3.0` tag README confirms this explicitly:

> "Since it's just files, the only thing you need to do is to copy all the files
> that reside on a particular folder from this package
> `/.var/app/org.gimp.GIMP/config/GIMP/3.0` to your GIMP's configuration folder."

### Icon Path Verification

The `xdg.dataFile."icons/hicolor"` reference to
`photogimp + "/.local/share/icons/hicolor"` is **correct** — this path exists
in both the `3.0` tag and `master`. No change required there.

---

## Current Broken Code

In `home/photogimp.nix`, the `installPhotoGIMP` activation block (line ~52):

```nix
$DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rf \
  ${photogimp}/.config/GIMP/3.0/. \
  "$GIMP_CONFIG/"
```

The path `.config/GIMP/3.0/` does **not exist** in the `3.0` tag archive.

---

## Required Fix

### Option A — Fix the source path (use correct path for tag `3.0`)

Change the `cp` source path in the activation script from:

```
${photogimp}/.config/GIMP/3.0/.
```

to:

```
${photogimp}/.var/app/org.gimp.GIMP/config/GIMP/3.0/.
```

This is the minimal, correct fix that aligns the script with the actual
directory structure of the pinned `3.0` tag.

### Option B — Upgrade `rev` to `master` (not recommended)

Alternatively, `rev` could be changed from `"3.0"` to the latest master commit
hash. The `master` branch does have `.config/GIMP/3.0/`. However, this would:
- Break reproducibility (no stable tag)
- Require a new hash
- Risk introducing unreleased, unstable configuration files

**Recommendation: Use Option A.**

---

## Exact Change Required

**File:** `home/photogimp.nix`

**Old string:**
```nix
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rf \
          ${photogimp}/.config/GIMP/3.0/. \
          "$GIMP_CONFIG/"
```

**New string:**
```nix
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rf \
          ${photogimp}/.var/app/org.gimp.GIMP/config/GIMP/3.0/. \
          "$GIMP_CONFIG/"
```

No other changes are required. The module comment block, version sentinel
logic, `fetchFromGitHub` stanza, and `xdg.dataFile` icon reference are all
correct for the `3.0` tag.

---

## Implementation Checklist

- [ ] Replace `.config/GIMP/3.0/.` with `.var/app/org.gimp.GIMP/config/GIMP/3.0/.` in the `cp` command
- [ ] Update the inline comment on line ~7 (`# Config target:`) — currently reads `# Copies all files from PhotoGIMP's .config/GIMP/3.0/` — to reflect the actual source path (optional but improves clarity)
- [ ] Verify activation succeeds: `home-manager switch`
- [ ] Confirm GIMP opens with PhotoGIMP layout

---

## Sources

1. GitHub Git Trees API — PhotoGIMP tag `3.0`:  
   `https://api.github.com/repos/Diolinux/PhotoGIMP/git/trees/3.0?recursive=1`
2. GitHub — PhotoGIMP tree at tag `3.0`:  
   `https://github.com/Diolinux/PhotoGIMP/tree/3.0`
3. GitHub — PhotoGIMP tree at `master`:  
   `https://github.com/Diolinux/PhotoGIMP/tree/master`
4. PhotoGIMP `3.0` tag README (install instructions for non-Flatpak Linux):  
   confirms config files live at `/.var/app/org.gimp.GIMP/config/GIMP/3.0`
5. PhotoGIMP `master` README (install instructions for Linux):  
   confirms new layout copies to `~/.config/GIMP/3.0` — this is the *destination*, not a repo source path in tag `3.0`
6. NixOS Home Manager `home.activation` docs:  
   `https://nix-community.github.io/home-manager/options.xhtml#opt-home.activation`
