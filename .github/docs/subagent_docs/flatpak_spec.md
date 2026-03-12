# Flatpak + Flathub Integration — VexOS Implementation Specification

**Feature:** Declarative Flatpak with Flathub and Application Installation  
**Date:** 2026-03-11  
**Spec Revised:** 2026-03-11 (post-implementation analysis pass)  
**Status:** IMPLEMENTED — All files modified; ready for Review phase  

---

## 1. Current Configuration Analysis

### 1.1 Repository Structure

```
flake.nix                         # Flake entry: defines mkVexosSystem, imports all modules
hosts/default/configuration.nix  # Host-level: imports all modules, sets gpu.type, networking, boot
modules/gnome.nix                 # GNOME/GDM, XKB, GNOME packages, excludes, gnome-keyring
modules/system.nix                # SSH, Tailscale, Samba, printing, bluetooth, Docker, zram
modules/users.nix                 # User "nimda" with groups, shell, initial password
modules/gaming.nix                # Steam, GameMode, PipeWire low latency, nix-gaming cache
modules/gpu.nix                   # Declarative GPU driver selection (none/intel/amd/nvidia)
modules/asus.nix                  # asusd, supergfxd, rog-control-center, fwupd
home/default.nix                  # Home Manager: packages, bash, starship, session vars
```

### 1.2 Nixpkgs Version

The flake pins **nixos-25.11** and **home-manager/release-25.11**.

```nix
# flake.nix (lines 5–12)
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  home-manager = {
    url = "github:nix-community/home-manager/release-25.11";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  nix-gaming = { ... };
};
```

### 1.3 Existing Flake Inputs

Currently active inputs:
- `nixpkgs` (nixos-25.11)
- `home-manager` (release-25.11, follows nixpkgs)
- `nix-gaming` (with pipewireLowLatency + platformOptimizations modules)

### 1.4 Existing GNOME Configuration (gnome.nix)

```nix
services.xserver.enable = true;
services.displayManager.gdm.enable = true;
services.displayManager.gdm.wayland = true;
services.desktopManager.gnome.enable = true;
services.gnome.gnome-keyring.enable = true;
```

**Important:** `services.desktopManager.gnome.enable = true` in nixpkgs **automatically**:
- Enables `xdg.portal.enable = true`
- Installs and activates `xdg-desktop-portal-gnome` as the portal backend

This means no additional XDG portal configuration is strictly required for Flatpak on GNOME.

### 1.5 Existing Module Import Pattern (configuration.nix)

```nix
imports = [
  ../../modules/system.nix
  ../../modules/gnome.nix
  ../../modules/users.nix
  ../../modules/gpu.nix
  ../../modules/gaming.nix
  ../../modules/asus.nix
  ../../modules/flatpak.nix   # ← ADDED (implementation applied)
];
```

### 1.6 Flatpak — Current State (Post-Implementation)

**Implementation has been fully applied.** All three required changes are present in the repository:

**flake.nix** — nix-flatpak input and module import are present:
```nix
# Input declared:
nix-flatpak.url = "github:gmodena/nix-flatpak";

# Module imported in mkVexosSystem:
nix-flatpak.nixosModules.nix-flatpak

# Present in outputs function args:
outputs = { self, nixpkgs, home-manager, nix-flatpak, ... }@inputs:
```

**modules/flatpak.nix** — Complete declarative configuration:
```nix
{ ... }:
{
  services.flatpak.enable = true;
  xdg.portal.enable = true;
  services.flatpak.packages = [ /* 12 apps */ ];
  services.flatpak.update.onActivation = false;
}
```

**hosts/default/configuration.nix** — Module is imported:
```nix
../../modules/flatpak.nix
```

---

## 2. Problem Definition

### What Was Missing (Pre-Implementation)

1. **Flatpak was not enabled** — `services.flatpak.enable` was not set anywhere.
2. **No Flathub remote** was configured declaratively.
3. **No Flatpak applications** were installed.
4. **No declarative package lifecycle management** — nixpkgs 25.11's native `services.flatpak` module provides **only two options** (`enable` and `package`); it does NOT provide declarative remote or package management.

### Implementation Status

| Requirement | Pre-Implementation | Post-Implementation |
|---|---|---|
| `services.flatpak.enable` | Not set | ✅ `true` (flatpak.nix) |
| Flathub remote | Not configured | ✅ Default remote in nix-flatpak |
| 12 Flatpak applications | Not installed | ✅ Declaratively managed (flatpak.nix) |
| XDG portal for Flatpak | Auto-handled by GNOME | ✅ Explicit `xdg.portal.enable = true` for clarity |
| Dedicated module file | Not present | ✅ `modules/flatpak.nix` created |
| nix-flatpak flake input | Not present | ✅ `github:gmodena/nix-flatpak` in flake.nix |
| nix-flatpak NixOS module | Not imported | ✅ `nix-flatpak.nixosModules.nix-flatpak` in mkVexosSystem |
| configuration.nix import | Missing | ✅ `../../modules/flatpak.nix` added to imports |

---

## 3. Research Findings

### 3.1 Source 1: NixOS Official Manual (nixos.org/manual/nixos/unstable)

**Confirmed:** `services.flatpak.enable = true` is the only declarative option in nixpkgs for enabling Flatpak. The manual only documents imperative `flatpak remote-add` shell commands for adding Flathub — no native declarative remote/package options exist.

**XDG Portal for GNOME:** Official docs note that for non-GNOME desktops, `xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ]` is needed. For GNOME, the GNOME module handles this automatically.

### 3.2 Source 2: NixOS Wiki — Flatpak (wiki.nixos.org/wiki/Flatpak)

**Confirmed:** nixpkgs provides only `services.flatpak.enable`. The wiki shows a workaround pattern for adding Flathub declaratively via a `systemd.services.flatpak-repo` oneshot service:

```nix
systemd.services.flatpak-repo = {
  wantedBy = [ "multi-user.target" ];
  path = [ pkgs.flatpak ];
  script = ''
    flatpak remote-add --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
  '';
};
```

**Assessment:** This systemd oneshot pattern is workable but has significant downsides — it is imperative (runs only if the remote is missing), provides no idempotent state management, no package lifecycle (install/uninstall on activation), and no generation-aware rollback support.

### 3.3 Source 3: NixOS Options Search (search.nixos.org/options, channel=25.11)

**Confirmed via search.nixos.org:** NixOS 25.11 nixpkgs has exactly **2** `services.flatpak.*` options:
- `services.flatpak.enable` (boolean)
- `services.flatpak.package` (package override)

There is **no** `services.flatpak.packages`, `services.flatpak.remotes`, or any declarative package management in official nixpkgs 25.11. The feature requested in the prompt ("services.flatpak option added in NixOS 23.11+") does not exist in the official nixpkgs at this time.

### 3.4 Source 4: nix-flatpak Community Module (github.com/gmodena/nix-flatpak)

**nix-flatpak** is the canonical community solution for declarative Flatpak management in NixOS. Verified via GitHub.

Key properties:
- Used in production (NixCon 2023 talk by Martin Wimpress inspired it; presented at NixCon 2025 by the author)
- Provides both `nixosModules.nix-flatpak` and `homeManagerModules.nix-flatpak`
- Compatible with nixos-25.11 (confirmed by `testing-base/flake.nix` which uses `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"`)
- Uses systemd activation service (`flatpak-managed-install`) for lifecycle management
- **Flathub is the default remote** — automatically added without explicit declaration
- `services.flatpak.packages` accepts simple app IDs or attribute sets
- `services.flatpak.remotes` declares additional/alternative remotes
- `services.flatpak.update.onActivation` controls auto-update behaviour
- `services.flatpak.uninstallUnmanaged` controls whether manually installed apps are removed
- The flake has no inputs of its own (just exports outputs), so no nixpkgs version conflicts are possible

**NixOS module vs Home Manager module:**
- `nixosModules.nix-flatpak` = system-wide installation at `/var/lib/flatpak`
- `homeManagerModules.nix-flatpak` = per-user installation at `~/.local/share/flatpak`

**Decision: Use NixOS module (system-wide)** because:
1. The requested applications (Bitwarden, GIMP, OnlyOffice, RustDesk, etc.) are system-level tools appropriate for system-wide installation
2. Consistent with how Steam, Discord, and other apps are installed via nixpkgs in this configuration
3. Simpler import chain (direct module in flake.nix, no Home Manager delegation required)

### 3.5 Source 5: nix-flatpak README — Package Declaration Syntax

From official README (gmodena/nix-flatpak):

```nix
services.flatpak.packages = [
  # Simple string — origin defaults to "flathub"
  "com.obsproject.Studio"
  # Explicit origin
  { appId = "com.brave.Browser"; origin = "flathub"; }
  # Pin a specific commit
  { appId = "im.riot.Riot"; commit = "bdcc7fff..." }
];
```

The `origin` defaults to `"flathub"`, so all 12 requested apps (which are all on Flathub) can be declared as simple strings.

### 3.6 Source 6: NixOS GNOME Module — XDG Portal Auto-Configuration

From nixpkgs source: when `services.desktopManager.gnome.enable = true`, the GNOME NixOS module automatically activates:
- `xdg.portal.enable = true`
- `xdg-desktop-portal-gnome` (provides all GNOME portal interfaces)

This means **no explicit `xdg.portal` configuration is required** for Flatpak to work under GNOME. However, for documentation clarity and robustness (in case a user ever swaps DE), making it explicit in `flatpak.nix` is considered best practice by the NixOS wiki for Flatpak sections:

```nix
# Explicitly verify XDG portals are enabled (GNOME handles this, but defensive config)
xdg.portal.enable = true;
```

The `xdg-desktop-portal-gnome` package is already provided by GNOME; we do not need `xdg-desktop-portal-gtk` on a pure GNOME system.

---

## 4. Proposed Solution Architecture

### 4.1 Decision: nix-flatpak NixOS Module

**Recommended approach:** Add `github:gmodena/nix-flatpak` as a flake input and use `nixosModules.nix-flatpak` for system-wide declarative Flatpak management.

**Why not the systemd oneshot pattern?**:
- No package lifecycle (won't remove apps you delete from config)
- Not idempotent across generations
- State is managed imperatively, not reproducibly

**Why not Home Manager module?**:
- Home Manager module does per-user installation; system-wide is appropriate here
- Fewer import chain complications (nix-flatpak NixOS module is imported in flake.nix just like nix-gaming modules)

### 4.2 Files to Create

| File | Action | Purpose |
|---|---|---|
| `modules/flatpak.nix` | **CREATE** | Flatpak enable + all package declarations |

### 4.2 Files Created

| File | Status | Purpose |
|---|---|---|
| `modules/flatpak.nix` | ✅ CREATED | Flatpak enable + all package declarations |

### 4.3 Files Modified

| File | Status | Change |
|---|---|---|
| `flake.nix` | ✅ MODIFIED | Added `nix-flatpak` input; imported `nix-flatpak.nixosModules.nix-flatpak` in `mkVexosSystem` |
| `hosts/default/configuration.nix` | ✅ MODIFIED | Added `../../modules/flatpak.nix` to imports |

---

## 5. Implementation Steps (Applied)

> **Status:** All steps have been applied. The following documents what was implemented and the exact patterns used, as verified against the nix-flatpak v0.7.0 API (GitHub README, 2026-03-11).

### Step 1: Add nix-flatpak Input to flake.nix

Add after the `nix-gaming` input block:

```nix
nix-flatpak = {
  url = "github:gmodena/nix-flatpak";
  # nix-flatpak has no inputs; no follows needed
};
```

Add to the `outputs` function parameters:

```nix
outputs = { self, nixpkgs, home-manager, nix-flatpak, ... }@inputs:
```

### Step 2: Import nix-flatpak Module in mkVexosSystem

In `flake.nix`, inside the `modules = [...]` list of `mkVexosSystem`, add the NixOS module:

```nix
# nix-flatpak declarative Flatpak management
nix-flatpak.nixosModules.nix-flatpak
```

This mirrors the pattern already used for `nix-gaming` modules.

### Step 3: Add modules/flatpak.nix to configuration.nix imports

```nix
# hosts/default/configuration.nix imports block
imports = [
  ../../modules/system.nix
  ../../modules/gnome.nix
  ../../modules/users.nix
  ../../modules/gpu.nix
  ../../modules/gaming.nix
  ../../modules/asus.nix
  ../../modules/flatpak.nix   # <-- add this line
];
```

### Step 4: Create modules/flatpak.nix

```nix
# modules/flatpak.nix
#
# Declarative Flatpak management via nix-flatpak community module.
# Requires: nix-flatpak.nixosModules.nix-flatpak imported in flake.nix
#
# nix-flatpak uses a systemd activation service (flatpak-managed-install)
# to install/uninstall/update Flatpak apps on nixos-rebuild switch.
# Flatpaks are stored at /var/lib/flatpak (system-wide installation).
# Installation is NOT generational — rollbacks do not uninstall apps.
#
# XDG portals: services.desktopManager.gnome.enable (set in gnome.nix)
# automatically enables xdg.portal and xdg-desktop-portal-gnome.
# No additional portal configuration is required for GNOME + Flatpak.

{ ... }:

{
  # ── Enable Flatpak ────────────────────────────────────────────────────
  services.flatpak.enable = true;

  # ── XDG Portal (explicit for clarity; GNOME already enables this) ─────
  # GNOME's NixOS module sets xdg.portal.enable = true and activates
  # xdg-desktop-portal-gnome. This line is defensive documentation only.
  xdg.portal.enable = true;

  # ── Declarative Flatpak applications (all from Flathub) ───────────────
  # nix-flatpak default remote is Flathub; no explicit remote declaration needed.
  # Apps are installed/managed on each nixos-rebuild switch.
  # Remove an entry to have it uninstalled on the next activation.
  services.flatpak.packages = [
    # Password manager
    "com.bitwarden.desktop"

    # GitHub Desktop alternative (Plus fork)
    "io.github.pol_rivero.github-desktop-plus"

    # Flatpak permissions manager
    "com.github.tchx84.Flatseal"

    # Flatpak app updater / install manager
    "it.mijorus.gearlever"

    # Image editor
    "org.gimp.GIMP"

    # System resource monitor
    "io.missioncenter.MissionCenter"

    # Office suite
    "org.onlyoffice.desktopeditors"

    # Minecraft launcher
    "org.prismlauncher.PrismLauncher"

    # Remote desktop / support
    "com.rustdesk.RustDesk"

    # Note-taking app
    "com.simplenote.Simplenote"

    # Flatpak management GUI
    "io.github.flattool.Warehouse"

    # Privacy-focused web browser
    "app.zen_browser.zen"
  ];

  # ── Update policy ─────────────────────────────────────────────────────
  # onActivation = false means nixos-rebuild switch will install missing apps
  # but will NOT update already-installed apps (idempotent rebuilds).
  # Set to true to always pull latest on every rebuild.
  services.flatpak.update.onActivation = false;
}
```

---

## 6. Complete Diff Summary

### flake.nix — Full Modified Structure

```nix
{
  description = "VexOS - Personal NixOS Configuration with GNOME";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Flatpak management
    # Provides: nixosModules.nix-flatpak, homeManagerModules.nix-flatpak
    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs = { self, nixpkgs, home-manager, nix-flatpak, ... }@inputs:
  let
    mkVexosSystem = { hardwareModule, system ? "x86_64-linux" }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          hardwareModule
          ./hosts/default/configuration.nix

          # nix-gaming NixOS modules
          inputs.nix-gaming.nixosModules.pipewireLowLatency
          inputs.nix-gaming.nixosModules.platformOptimizations

          # nix-flatpak declarative Flatpak management
          nix-flatpak.nixosModules.nix-flatpak

          # Home Manager integration
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.nimda = import ./home/default.nix;
          }
        ];
      };
  in
  {
    lib.mkVexosSystem = mkVexosSystem;

    nixosConfigurations = {
      vexos = mkVexosSystem {
        hardwareModule = ./hosts/default/hardware-configuration.nix;
      };
    };
  };
}
```

---

## 7. NixOS Options Confirmed (Context7-Verified)

### Native nixpkgs 25.11 (`services.flatpak`)

| Option | Type | Default | Confirmed |
|---|---|---|---|
| `services.flatpak.enable` | bool | `false` | ✓ (search.nixos.org, nixos-25.11) |
| `services.flatpak.package` | package | `pkgs.flatpak` | ✓ (search.nixos.org, nixos-25.11) |

**Note:** `services.flatpak.packages` and `services.flatpak.remotes` do **NOT** exist in official nixpkgs 25.11. These options are provided exclusively by the `nix-flatpak` community module.

### nix-flatpak Module (`github:gmodena/nix-flatpak`) — Provided Options

| Option | Type | Default | Confirmed |
|---|---|---|---|
| `services.flatpak.enable` | bool | `false` | ✓ (overrides/extends nixpkgs option) |
| `services.flatpak.packages` | list of str or attrset | `[]` | ✓ (nix-flatpak options.nix) |
| `services.flatpak.remotes` | list of attrset | `[{name="flathub"; location="https://dl.flathub.org/repo/flathub.flatpakrepo";}]` | ✓ |
| `services.flatpak.update.onActivation` | bool | `false` | ✓ |
| `services.flatpak.update.auto.enable` | bool | `false` | ✓ |
| `services.flatpak.uninstallUnmanaged` | bool | `false` | ✓ |
| `services.flatpak.overrides` | attrset | `{}` | ✓ |

### XDG Portal (Auto-Enabled by GNOME)

| Option | Set By | Value |
|---|---|---|
| `xdg.portal.enable` | `services.desktopManager.gnome.enable` | `true` (automatic) |
| `xdg-desktop-portal-gnome` | GNOME NixOS module | Installed automatically |

No `xdg.portal.extraPortals` additions are required on GNOME.

---

## 8. Application Compatibility Notes

| App ID | Notes |
|---|---|
| `com.bitwarden.desktop` | Wayland native ✓ |
| `io.github.pol_rivero.github-desktop-plus` | Electron app; Wayland via NIXOS_OZONE_WL (already set in home.nix) |
| `com.github.tchx84.Flatseal` | GTK4, Wayland native ✓ |
| `it.mijorus.gearlever` | GTK4, Wayland native ✓ |
| `org.gimp.GIMP` | GTK3, runs via XWayland (acceptable) |
| `io.missioncenter.MissionCenter` | GTK4, Wayland native ✓ |
| `org.onlyoffice.desktopeditors` | Qt, X11 only — will use XWayland. Known limitation. |
| `org.prismlauncher.PrismLauncher` | Qt, works under XWayland ✓ |
| `com.rustdesk.RustDesk` | Flutter/Sciter, uses XWayland ✓ |
| `com.simplenote.Simplenote` | Electron app; Wayland via ozone ✓ |
| `io.github.flattool.Warehouse` | GTK4, Wayland native ✓ |
| `app.zen_browser.zen` | Firefox-based; Wayland native via MOZ_ENABLE_WAYLAND (set in home.nix) ✓ |

---

## 9. Risks and Mitigations

### Risk 1: nix-flatpak does not support nixos-25.11

**Likelihood:** Very Low  
**Evidence:** `gmodena/nix-flatpak/testing-base/flake.nix` explicitly uses `nixos-25.11` as its test platform. The module itself has no inputs (no nixpkgs dependency), relying solely on the host system's nixpkgs.  
**Mitigation:** If a version incompatibility surfaces, pin to a specific tagged release: `github:gmodena/nix-flatpak/?ref=v0.7.0`

### Risk 2: XDG Portal conflict on GNOME

**Likelihood:** Very Low  
**Evidence:** GNOME automatically installs `xdg-desktop-portal-gnome`. Adding `xdg.portal.enable = true` explicitly is redundant but harmless (it sets a value already set to true).  
**Mitigation:** Do not add `xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ]` — this would conflict with GNOME's portal configuration and cause the "wrong portal" error.

### Risk 3: Apps fail to install due to network availability during activation

**Likelihood:** Low (only in minimal/offline environments)  
**Evidence:** nix-flatpak uses a `restartOnFailure` mechanism (enabled by default as of 0.6.0) with 60s retry delay — transient network failures are handled automatically.  
**Mitigation:** The `restartOnFailure` default is sufficient. No additional config needed.

### Risk 4: `nix flake check` fails due to new input not being locked

**Likelihood:** Medium (expected, not a failure — flake.lock must be updated)  
**Mitigation:** After implementing changes, run `nix flake update nix-flatpak` to add the new input to `flake.lock`. The preflight script requires `nix flake check` to pass, so this must be done before preflight.

### Risk 5: onlyoffice has no Wayland support

**Likelihood:** Certain (known limitation)  
**Evidence:** nix-flatpak README explicitly shows `"org.onlyoffice.desktopeditors".Context.sockets = ["x11"]` as an override example — it only supports X11/XWayland.  
**Mitigation:** XWayland is available on this system (GDM Wayland + `services.xserver.enable = true`). No override needed; app will transparently use XWayland. Document as known limitation.

### Risk 6: flake.nix outputs parameter change breaks `lib.mkVexosSystem`

**Likelihood:** Low  
**Evidence:** Adding `nix-flatpak` to `inputs` and importing the module inside `mkVexosSystem` is additive.  
**Mitigation:** The `nix-flatpak` module only uses `services.flatpak.*` options declared by nix-flatpak itself. There are no conflicts with existing modules.

---

## 10. Implementation Checklist

- [x] Add `nix-flatpak.url = "github:gmodena/nix-flatpak"` to `flake.nix` inputs
- [x] Add `nix-flatpak` to `outputs` function arguments in `flake.nix`
- [x] Add `nix-flatpak.nixosModules.nix-flatpak` to `mkVexosSystem` modules list in `flake.nix`
- [x] Create `modules/flatpak.nix` with enable, xdg.portal, and packages
- [x] Add `../../modules/flatpak.nix` to imports in `hosts/default/configuration.nix`
- [ ] Run `nix flake update nix-flatpak` to lock the new input *(required on NixOS system before preflight)*
- [ ] Run `nix flake check` to validate the configuration *(required on NixOS system before preflight)*

---

## 11. API Verification Summary (nix-flatpak v0.7.0, 2026-03-11)

Verified against `gmodena/nix-flatpak` GitHub repository (latest stable: `v0.7.0`, commit `123fe29`, bumped to nixos-25.11 support 2 months ago).

### Confirmed API Patterns Used in Implementation

```nix
# ✅ Correct: simple string form — origin defaults to "flathub"
services.flatpak.packages = [
  "com.bitwarden.desktop"
  "app.zen_browser.zen"
  # ... etc
];

# ✅ Correct: update policy (false = idempotent rebuilds)
services.flatpak.update.onActivation = false;

# ✅ Correct: Flathub is default remote — no explicit declaration needed
# (nix-flatpak adds flathub by default unless services.flatpak.remotes is set)

# ✅ Correct: NixOS module import path
nix-flatpak.nixosModules.nix-flatpak
```

### Optional Patterns NOT Used (Available If Needed)

```nix
# Pin to a specific release (use if main-branch instability is encountered)
nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.7.0";

# Auto-update on weekly schedule
services.flatpak.update.auto = {
  enable = true;
  onCalendar = "weekly";
};

# Remove apps not in this list (unmanaged = installed via CLI/store)
services.flatpak.uninstallUnmanaged = true;

# Per-app Wayland/permission overrides
services.flatpak.overrides = {
  global.Context.sockets = ["wayland" "!x11" "!fallback-x11"];
  "org.onlyoffice.desktopeditors".Context.sockets = ["x11"]; # No Wayland support
};

# Explicit Flathub remote (only needed if adding additional remotes)
services.flatpak.remotes = lib.mkOptionDefault [{
  name = "flathub-beta";
  location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
}];
```

### Version Pin Recommendation

The current `flake.nix` uses `github:gmodena/nix-flatpak` (unpinned main branch). The nix-flatpak README advises using `?ref=latest` or `?ref=v0.7.0` for stability:

```nix
# Current (unstable main):
nix-flatpak.url = "github:gmodena/nix-flatpak";

# Recommended for stability:
nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

# Pin to exact release:
nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.7.0";
```

**Assessment:** For a production system, pinning to `?ref=latest` is recommended. For CI/development, the current unpinned `main` is acceptable. Pinning is the only outstanding improvement not yet applied.
- [ ] Run `scripts/preflight.sh` for full validation

---

## 11. Files to Create/Modify (Summary)

| File | Action | Lines Changed (Estimated) |
|---|---|---|
| `flake.nix` | Modify — add input + module import | ~8 lines added |
| `hosts/default/configuration.nix` | Modify — add import line | 1 line added |
| `modules/flatpak.nix` | Create — new module | ~50 lines |

**Total:** ~59 lines of Nix code across 3 files (2 modified, 1 created).

---

*Spec generated by VexOS Research Subagent — Phase 1*
