# PhotoGIMP Integration Specification
## VexOS NixOS Flake Configuration

**Date**: 2026-03-12  
**Status**: Ready for Implementation  
**Feature**: Declarative PhotoGIMP Configuration via Home Manager

---

## 1. Current Configuration Analysis

### Repository Structure
VexOS is a modular NixOS flake configuration with the following key architecture:

| Component | Path | Purpose |
|-----------|------|---------|
| Flake entry point | `flake.nix` | Defines inputs, `lib.mkVexosSystem`, and CI config |
| NixOS host | `hosts/default/configuration.nix` | Imports all system modules |
| Home Manager | `home/default.nix` | User environment for `nimda` |
| System modules | `modules/*.nix` | Reusable NixOS-level modules |

### Relevant Existing Patterns

**Flake inputs** (`flake.nix`):
- `nixpkgs` → `nixos-25.11`
- `nixpkgs-unstable` → `nixos-unstable`
- `home-manager` → `release-25.11`
- `nix-flatpak` → for declarative Flatpak management

**Home Manager integration**:
```nix
home-manager.users.nimda = import ./home/default.nix;
```
Home Manager is loaded as a NixOS module. The `home/default.nix` file is the sole HM entry point.

**Existing `home.file` usage** (`home/default.nix`):
```nix
home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ../wallpapers/vex-bb-light.jxl;
home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ../wallpapers/vex-bb-dark.jxl;
```
This is a direct source-reference pattern (source from repo path). Home Manager symlinks these into the home directory.

**GIMP installation** (`modules/flatpak.nix`):
```nix
services.flatpak.packages = [
  ...
  "org.gimp.GIMP"
  ...
];
```
GIMP is **currently installed via Flatpak** (`org.gimp.GIMP` from Flathub). There is no native Nix GIMP package.

**User**: `nimda`, home: `/home/nimda`  
**State version**: `24.05`

---

## 2. Problem Definition

### Current State
The user has a bash script that:
1. Downloads PhotoGIMP from GitHub **at runtime** (impure, non-reproducible)
2. Creates `/etc/profile.d/photogimp-setup.sh` that **re-downloads** PhotoGIMP on each user's first login

### Problems
- **Not reproducible**: Runtime network access during setup breaks the declarative NixOS model
- **Not pinned**: Downloads latest master, meaning configuration can change between deploys
- **Not idempotent**: Re-download logic is fragile and side-effect heavy
- **Not integrated**: Lives outside the Nix evaluation graph — invisible to `nix flake check`
- **Profile.d anti-pattern**: Using `/etc/profile.d/` for per-user setup is a NixOS anti-pattern

### Goal
Install PhotoGIMP declaratively by:
1. Fetching the PhotoGIMP source at **build time** (hash-pinned via `pkgs.fetchFromGitHub`)
2. Placing config files into `~/.config/GIMP/3.0/` at **activation time** via `home.activation`
3. Integrating cleanly with the existing Home Manager configuration in `home/default.nix`

---

## 3. Recommended Solution Architecture

### Decision Matrix

| Option | Description | Verdict |
|--------|-------------|---------|
| **A: `xdg.configFile` recursive symlink** | Symlink entire `~/.config/GIMP/3.0/` to Nix store path | ❌ REJECTED — GIMP cannot write session files to a read-only Nix store symlink |
| **B: Individual `xdg.configFile` entries** | Symlink each config file individually | ❌ REJECTED — GIMP writes to `sessionrc`, `pluginrc`, etc. at runtime; read-only symlinks cause GIMP errors |
| **C: `home.activation` copy with version guard** | Copy (not symlink) config files on activation; skip if version unchanged | ✅ RECOMMENDED |
| **D: Store-path derivation + overlay** | Build a custom derivation and patch GIMP | ❌ OVER-ENGINEERED — unnecessary complexity |

### Why Option C is Correct

1. **GIMP needs write access to its config directory.** GIMP writes `sessionrc`, `pluginrc`, `recentfiles`, and other runtime data to `~/.config/GIMP/3.0/` during every session. Symlinks to the Nix store would cause GIMP to fail on startup or silently fail to save preferences.

2. **`home.activation` copies files as real mutable files**, not symlinks. Combined with `chmod -R u+w`, the copied files are fully writable by the user.

3. **Version guard prevents re-copying on every switch.** A sentinel file `.photogimp-version` in `~/.config/GIMP/3.0/` tracks the installed version. Files are only copied if the version changes (or on first install), preserving any runtime customizations the user makes between upgrades.

4. **`pkgs.fetchFromGitHub` is fully reproducible.** The PhotoGIMP source is fetched once at build time, stored in the Nix store with a pinned hash. No network access occurs at activation time.

### Recommended Architecture Summary

```
home/photogimp.nix          ← NEW: Home Manager module (PhotoGIMP config)
home/default.nix            ← MODIFIED: add imports = [ ./photogimp.nix ]
modules/flatpak.nix         ← NO CHANGE: GIMP stays as Flatpak
```

**GIMP Installation**: Keep as Flatpak (`org.gimp.GIMP`). Do **not** add a native Nix GIMP package alongside it. The Flatpak GIMP 3.0 on NixOS reads its config from `~/.config/GIMP/3.0/` (confirmed: Flatpak GIMP 3.0 uses `--filesystem=xdg-config/GIMP:create` permission, which maps to the user's XDG config home at `~/.config/GIMP/`).

---

## 4. PhotoGIMP Repository Analysis

### Source
- **Repository**: `https://github.com/Diolinux/PhotoGIMP`
- **Latest release tag**: `3.0` (released March 17, 2025)
- **Requires**: GIMP 3.0 or newer ✅ (Flatpak `org.gimp.GIMP` on Flathub is GIMP 3.0)

### Complete File Layout

```
PhotoGIMP-master/
├── .config/
│   └── GIMP/
│       └── 3.0/                        ← Install to: ~/.config/GIMP/3.0/
│           ├── filters/                (directory — filter scripts)
│           ├── internal-data/          (directory — brushes, gradients etc.)
│           ├── plug-in-settings/       (directory — plugin preferences)
│           ├── splashes/               (directory — custom splash screens)
│           ├── tool-options/           (directory — per-tool options)
│           ├── action-history          (file)
│           ├── colorrc                 (file — color swatches)
│           ├── contextrc               (file — active tool/color context)
│           ├── controllerrc            (file — input controller config)
│           ├── devicerc                (file — input device config)
│           ├── dockrc                  (file — dock/panel layout)
│           ├── extensionrc             (file — extensions state)
│           ├── gimprc                  (file — general GIMP preferences)
│           ├── modifiersrc             (file — keyboard modifier config)
│           ├── parasiterc              (file — persistent data store)
│           ├── pluginrc                (file — plugin registry cache)
│           ├── profilerc               (file — color profiles)
│           ├── sessionrc               (file — window layout/positions)
│           ├── shortcutsrc             (file — Photoshop-mapped shortcuts)
│           ├── tags.xml                (file — tag metadata)
│           ├── templaterc              (file — canvas templates)
│           ├── theme.css               (file — UI theme adjustments)
│           ├── toolrc                  (file — tool order/layout)
│           └── unitrc                  (file — measurement units)
└── .local/
    └── share/
        ├── applications/
        │   └── org.gimp.GIMP.desktop   ← See note below (SKIP for Flatpak)
        └── icons/
            └── hicolor/
                ├── 128x128/apps/       (128px PhotoGIMP icon)
                ├── 16x16/apps/         (16px PhotoGIMP icon)
                ├── 256x256/            (256px PhotoGIMP icon)
                ├── 32x32/apps/         (32px PhotoGIMP icon)
                ├── 48x48/apps/         (48px PhotoGIMP icon)
                ├── 512x512/apps/       (512px PhotoGIMP icon)
                ├── 64x64/apps/         (64px PhotoGIMP icon)
                └── photogimp.png       (root icon file)
```

**Note on `org.gimp.GIMP.desktop`**: PhotoGIMP ships an overriding `.desktop` file that renames the app to "PhotoGIMP" and changes the icon. However, since VexOS installs GIMP via Flatpak (`nix-flatpak`), the Flatpak runtime also manages `~/.local/share/applications/org.gimp.GIMP.desktop`. Flatpak will **overwrite** any manually placed `.desktop` file when `org.gimp.GIMP` is installed or updated. Therefore, **skip the `.desktop` file** to avoid a Flatpak management conflict. The GIMP config changes (layout, shortcuts, theme) will still apply — only the app name/icon in the launcher are cosmetic.

---

## 5. NixOS/Home Manager Options to Use

### Source 1: Context7 — `/nix-community/home-manager` (High reputation, score 80.35)

#### `home.activation` with `lib.hm.dag.entryAfter`
```nix
home.activation.installPhotoGIMP = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  # Shell script runs after all Home Manager symlinks are in place
  run ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/GIMP/3.0"
  $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rf ${source}/. "$HOME/.config/GIMP/3.0/"
  $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$HOME/.config/GIMP/3.0/"
'';
```
- Must run `entryAfter [ "writeBoundary" ]` to execute after all `home.file` symlinks
- Since HM 22.11, activation scripts have a **reset PATH** — all commands must use absolute Nix store paths: `${pkgs.coreutils}/bin/cp`
- `$DRY_RUN_CMD` is empty in normal mode, or `echo` in `--dry-run` mode (from Context7 docs)
- `$VERBOSE_ECHO` prints informational messages

#### `xdg.dataFile` with `recursive = true`
```nix
xdg.dataFile."icons/hicolor" = {
  source = photogimp + "/.local/share/icons/hicolor";
  recursive = true;
};
```
When `recursive = true`, Home Manager walks the source directory tree and creates **individual per-file symlinks** (not a single directory symlink). This is safe to use alongside other icon themes already present in `~/.local/share/icons/hicolor/`.

#### `pkgs.fetchFromGitHub`
```nix
photogimp = pkgs.fetchFromGitHub {
  owner = "Diolinux";
  repo  = "PhotoGIMP";
  rev   = "3.0";
  hash  = "sha256-PLACEHOLDER"; # Must be determined at implementation time
};
```

### Source 2: Home Manager Manual (release-25.11)
- `home.file`: manages files in `$HOME` — creates symlinks by default
- `xdg.configFile`: manages files in `$XDG_CONFIG_HOME` (`~/.config/`) — creates symlinks
- `xdg.dataFile`: manages files in `$XDG_DATA_HOME` (`~/.local/share/`) — creates symlinks  
- `home.activation`: shell scripts run during `home-manager switch`

### Source 3: NixOS/nixpkgs `pkgs.fetchFromGitHub`
Standard fetcher for GitHub repositories. Produces a fixed-output derivation (FOD) pinned by cryptographic hash. Available in all nixpkgs contexts.

---

## 6. Implementation Steps

### Step 1: Obtain the `fetchFromGitHub` Hash

On a NixOS machine, run the following to get the correct hash for PhotoGIMP 3.0:

```bash
nix-prefetch-url --unpack \
  "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
```

Alternatively, use the `lib.fakeHash` trick: set `hash = "";` in fetchFromGitHub (or use `lib.fakeHash`), run `nix build`, and the error output will contain the correct `sha256-` hash. Replace the placeholder with this hash.

**Expected approach for the implementation subagent**: Use `hash = "";` first to trigger the Nix hash mismatch error, then use the reported correct hash.

### Step 2: Create `home/photogimp.nix`

This is a new Home Manager module. Full implementation code:

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
    # Run the following to obtain the correct hash:
    #   nix-prefetch-url --unpack \
    #     "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
    hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
{
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
      if [ -z "${"\${DRY_RUN_CMD}"}" ]; then
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
  # launcher name ("PhotoGIMP") and icon in the app grid are skipped.
  xdg.dataFile."icons/hicolor" = {
    source    = photogimp + "/.local/share/icons/hicolor";
    recursive = true;
  };
}
```

**Important**: The `${"\${DRY_RUN_CMD}"}` syntax in the `if [ -z ... ]` guard is Nix string interpolation escaping. In the actual Nix file this should be written as `${"\${DRY_RUN_CMD}"}` escaped properly, or restructured as shown in the risk mitigation section below. See Section 9 for the correct Nix escape syntax.

### Step 3: Modify `home/default.nix`

Add an `imports` block at the top of the module:

```nix
# home/default.nix  — add imports block
{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./photogimp.nix     # ← ADD THIS
  ];

  # ... rest of existing home.nix unchanged ...
}
```

### Step 4: No Changes to System Modules

- `modules/flatpak.nix`: **No change** — `org.gimp.GIMP` stays as the Flatpak GIMP installation
- `hosts/default/configuration.nix`: **No change** — no new NixOS module to import
- `flake.nix`: **No change** — no new flake inputs required

---

## 7. Files to Create / Modify

| File | Action | Description |
|------|--------|-------------|
| `home/photogimp.nix` | **CREATE** | New Home Manager module — PhotoGIMP activation + icons |
| `home/default.nix` | **MODIFY** | Add `imports = [ ./photogimp.nix ]` |
| `modules/flatpak.nix` | **NO CHANGE** | GIMP remains as Flatpak |
| `hosts/default/configuration.nix` | **NO CHANGE** | No new system module needed |
| `flake.nix` | **NO CHANGE** | No new inputs required |

---

## 8. PhotoGIMP `fetchFromGitHub` Specification

```nix
pkgs.fetchFromGitHub {
  owner = "Diolinux";
  repo  = "PhotoGIMP";
  rev   = "3.0";           # git tag for PhotoGIMP 3.0 (released 2025-03-17)
  hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                           # PLACEHOLDER — implementer must run:
                           #   nix-prefetch-url --unpack \
                           #     "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
                           # OR: use hash = ""; to trigger build error revealing correct hash
}
```

**Reproducibility guarantee**: Using `rev = "3.0"` (a Git tag) plus a cryptographic `hash` ensures the exact same source code is used on every build, forever, regardless of network availability after the first fetch.

---

## 9. GIMP Config Directory Mapping

The `home.activation` script copies the entire `photogimp/.config/GIMP/3.0/` tree. Here is what each significant file does:

| PhotoGIMP source file | Installed to | Purpose |
|----------------------|--------------|---------|
| `shortcutsrc` | `~/.config/GIMP/3.0/shortcutsrc` | Photoshop-compatible keyboard shortcuts |
| `toolrc` | `~/.config/GIMP/3.0/toolrc` | Tool ordering mimicking Photoshop toolbar |
| `sessionrc` | `~/.config/GIMP/3.0/sessionrc` | Window/panel layout positions |
| `dockrc` | `~/.config/GIMP/3.0/dockrc` | Dock/panel configuration |
| `gimprc` | `~/.config/GIMP/3.0/gimprc` | General GIMP preferences (canvas, grid) |
| `contextrc` | `~/.config/GIMP/3.0/contextrc` | Active tool/color context |
| `theme.css` | `~/.config/GIMP/3.0/theme.css` | UI theme (minor Photoshop-like theming) |
| `templaterc` | `~/.config/GIMP/3.0/templaterc` | Pre-defined canvas templates |
| `splashes/` | `~/.config/GIMP/3.0/splashes/` | Custom PhotoGIMP splash screen |
| `filters/` | `~/.config/GIMP/3.0/filters/` | Filter scripts |
| `internal-data/` | `~/.config/GIMP/3.0/internal-data/` | Brushes, gradients, patterns |
| `plug-in-settings/` | `~/.config/GIMP/3.0/plug-in-settings/` | Per-plugin preferences |
| `tool-options/` | `~/.config/GIMP/3.0/tool-options/` | Per-tool option snapshots |

**Icon files** (via `xdg.dataFile`):

| PhotoGIMP source | Installed to | Purpose |
|-----------------|--------------|---------|
| `icons/hicolor/128x128/apps/` | `~/.local/share/icons/hicolor/128x128/apps/` | 128px app icon |
| `icons/hicolor/16x16/apps/` | `~/.local/share/icons/hicolor/16x16/apps/` | 16px app icon |
| `icons/hicolor/256x256/` | `~/.local/share/icons/hicolor/256x256/` | 256px app icon |
| `icons/hicolor/32x32/apps/` | `~/.local/share/icons/hicolor/32x32/apps/` | 32px app icon |
| `icons/hicolor/48x48/apps/` | `~/.local/share/icons/hicolor/48x48/apps/` | 48px app icon |
| `icons/hicolor/512x512/apps/` | `~/.local/share/icons/hicolor/512x512/apps/` | 512px app icon |
| `icons/hicolor/64x64/apps/` | `~/.local/share/icons/hicolor/64x64/apps/` | 64px app icon |
| `icons/hicolor/photogimp.png` | `~/.local/share/icons/hicolor/photogimp.png` | Root icon |

---

## 10. Risks and Mitigations

### Risk 1: Nix String Interpolation in Shell Scripts
**Problem**: The `home.activation` body is a Nix string. `$DRY_RUN_CMD` is a bash variable, but `${}` in a Nix string is Nix interpolation syntax. Writing `${DRY_RUN_CMD}` inside the string would attempt Nix interpolation (which fails because `DRY_RUN_CMD` is not a Nix variable).

**Mitigation**: Use `$DRY_RUN_CMD` (without braces) in the activation script body — bash evaluates this at runtime. Only use `${ }` syntax for Nix-level values like `${photogimp}` and `${pkgs.coreutils}`. For the `if [ -z "$DRY_RUN_CMD" ]` guard that needs braces, use a `''` (two single quotes) escape inside the Nix string: `"${''}DRY_RUN_CMD"` or restructure to use `$DRY_RUN_CMD` form.

**Correct pattern**:
```nix
home.activation.installPhotoGIMP = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  if [ -z "$DRY_RUN_CMD" ]; then   # bash $VAR (no braces) — safe in Nix strings
    ${pkgs.coreutils}/bin/printf '%s' "${photogimpVersion}" > "$VERSION_FILE"
  fi
'';
```

### Risk 2: Hash Mismatch / Incorrect SHA256
**Problem**: The `hash` placeholder in `fetchFromGitHub` will cause a build failure until replaced with the correct value.

**Mitigation**: Implementation subagent must:
1. Set `hash = "";` in the `fetchFromGitHub` call
2. Run `nix build` (or `nix flake check`)
3. Read the error output: `got: sha256-ACTUAL_HASH_HERE`
4. Replace the empty string with the reported hash
5. Rebuild to confirm

### Risk 3: GIMP Flatpak Config Path
**Problem**: Flatpak GIMP may store config in `~/.var/app/org.gimp.GIMP/config/GIMP/3.0/` on some older Flatpak versions, rather than `~/.config/GIMP/3.0/`.

**Mitigation**: GIMP 3.0 on Flathub explicitly declares `--filesystem=xdg-config/GIMP:create` in its sandbox permissions, mapping to `~/.config/GIMP/3.0/`. The PhotoGIMP project's own Linux Flatpak installation instructions confirm the target is `~/.config/GIMP/3.0/`. If a system uses an old GIMP Flatpak (<3.0), the config path may differ — but VexOS targets Flathub's current GIMP 3.0.

### Risk 4: Activation Script Overwrites User GIMP Customisations on Version Upgrade
**Problem**: When PhotoGIMP upgrades to a new version (e.g., 3.1), the version sentinel check will trigger a re-copy, overwriting any GIMP settings the user customised since the last install.

**Mitigation**: This is intentional and documented behaviour — it matches how PhotoGIMP manual upgrades work. Users who have extensively customised GIMP settings should back up `~/.config/GIMP/3.0/` before upgrading PhotoGIMP in the flake. This is prominently called out in PhotoGIMP's own README ("Back up your current GIMP settings before installing!").

### Risk 5: Flatpak `.desktop` Conflict
**Problem**: PhotoGIMP ships `org.gimp.GIMP.desktop` to rename the app to "PhotoGIMP". Flatpak also writes `~/.local/share/applications/org.gimp.GIMP.desktop` when `org.gimp.GIMP` is installed/updated.

**Mitigation**: The `.desktop` file is **omitted from this implementation**. GIMP's Photoshop-like layout, shortcuts, and theme will still work. Only the cosmetic launcher rename ("PhotoGIMP") and icon are skipped. If this is desired in the future, it could be added as a scheduled systemd user service that re-applies the `.desktop` override after Flatpak operations.

### Risk 6: `pkgs.coreutils` Absolute Path Requirement
**Problem**: As of Home Manager 22.11, activation scripts run with a reset PATH. Plain `cp`, `mkdir`, etc. are not addressable without absolute paths.

**Mitigation**: All shell commands in the activation script use `${pkgs.coreutils}/bin/COMMAND` absolute paths. This is already accounted for in the implementation code above.

### Risk 7: First-Time GIMP Run Requirement
**Problem**: PhotoGIMP's documentation states GIMP must be run once before PhotoGIMP is installed (to generate initial config files). If PhotoGIMP activation runs before GIMP is ever opened, some pre-existing config files may be absent.

**Mitigation**: The activation script uses `mkdir -p` to create `~/.config/GIMP/3.0/` if it doesn't exist, and `cp -rf` to copy all PhotoGIMP files in. GIMP 3.0 will accept this pre-seeded directory on first launch. Users do NOT need to open GIMP first before running `nixos-rebuild switch`.

### Risk 8: `xdg.dataFile` Icon Path Conflict
**Problem**: If `~/.local/share/icons/hicolor` already contains files managed by other home-manager options or packages, `xdg.dataFile."icons/hicolor" = { recursive = true; }` creates individual symlinks per file, which should not conflict. However, if Home Manager tries to manage both a symlink AND a real file at the same path, it will error.

**Mitigation**: PhotoGIMP uses unique filenames (`photogimp.png`, icons in size-specific subdirectories). These names do not conflict with standard icon theme files. The `recursive = true` implementation creates per-file symlinks, not a top-level directory symlink, so coexistence with other home-manager-managed icon files is safe.

---

## 11. Build Validation Commands

After implementation, verify with:

```bash
# From the vex-nix repository root:

# 1. Flake syntax and evaluation check
nix --extra-experimental-features 'nix-command flakes' flake check

# 2. Full configuration evaluation
nix --extra-experimental-features 'nix-command flakes' \
  eval .#nixosConfigurations.vexos.config.system.build.toplevel \
  --apply builtins.typeOf

# 3. Verify lib.mkVexosSystem is still exported
nix --extra-experimental-features 'nix-command flakes' \
  eval .#lib.mkVexosSystem --apply builtins.typeOf
# Expected: "lambda"

# 4. Formatting check (if alejandra is available)
alejandra --check .

# 5. Full preflight
bash scripts/preflight.sh
```

---

## 12. Research Sources

1. **Context7 — Home Manager (`/nix-community/home-manager`)**: `home.activation`, `lib.hm.dag.entryAfter`, `xdg.configFile`, `xdg.dataFile`, PATH reset in activation scripts (HM 22.11+), `$DRY_RUN_CMD` / `$VERBOSE_ECHO` variables.

2. **Context7 — Home Manager Manual (`/websites/nix-community_github_io_home-manager`)**: `home.file` attribute set form, `recursive = true` for directory linking, `force = true` for overwrite semantics.

3. **PhotoGIMP GitHub Repository** (`https://github.com/Diolinux/PhotoGIMP`): Directory structure (`.config/GIMP/3.0/`, `.local/share/`), file inventory (shortcutsrc, toolrc, sessionrc, dockrc, gimprc, contextrc, theme.css, templaterc, splashes/, filters/, internal-data/, plug-in-settings/, tool-options/), Flatpak install instructions confirming `~/.config/GIMP/3.0/` target, GIMP 3.0+ requirement, release tag `3.0`.

4. **PhotoGIMP GitHub `.config/GIMP/3.0/` tree**: Complete file listing — 5 subdirectories + 15+ config files.

5. **PhotoGIMP GitHub `.local/share/` tree**: `applications/org.gimp.GIMP.desktop` + `icons/hicolor/` with 7 icon sizes.

6. **VexOS Repository Analysis** (all existing files): Confirmed architecture — flake structure, Home Manager integration pattern, existing `home.file` wallpaper pattern, `modules/flatpak.nix` GIMP as Flatpak, `home/default.nix` as the sole HM entry point, HM `stateVersion = "24.05"`, user `nimda`.

7. **GIMP 3.0 Flatpak sandbox permissions**: Flatpak `org.gimp.GIMP` on Flathub declares `--filesystem=xdg-config/GIMP:create`, meaning it reads/writes `~/.config/GIMP/3.0/` (XDG config home), confirming compatibility with PhotoGIMP's config placement.

8. **Nix `fetchFromGitHub` documentation** (nixpkgs): Fixed-output derivation pattern, `owner/repo/rev/hash` parameters, `sha256-` base64 hash format.

---

## 13. Key Architectural Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Fetch strategy | `pkgs.fetchFromGitHub` (build-time, hash-pinned) | Reproducible; no runtime network access; integrated with Nix store |
| Install strategy | `home.activation` copy with version guard | GIMP needs writable config dir; version guard preserves user changes between upgrades |
| GIMP package | Keep as Flatpak (no change) | Already set up; Flatpak GIMP 3.0 fully compatible with PhotoGIMP 3.0 config placement |
| `.desktop` file | Skip | Flatpak runtime overwrites user-local `.desktop` on installs/updates — conflict avoided |
| Icon installation | `xdg.dataFile` with `recursive = true` | Icons don't need to be writable; individual per-file symlinks are safe |
| Module placement | New `home/photogimp.nix` imported from `home/default.nix` | Consistent with existing `home/` structure; clean separation from NixOS system modules |
| PhotoGIMP version | `3.0` (tag) | Latest stable release; matches GIMP 3.0 API requirements |
