# Up Integration Specification

**Feature:** Integrate `github:VictoryTek/Up` into VexOS NixOS flake  
**Date:** 2026-03-14  
**Status:** Draft — awaiting implementation  

---

## 1. Current Flake Structure Analysis

### 1.1 Inputs (flake.nix)

| Input | URL | Notes |
|-------|-----|-------|
| `nixpkgs` | `github:nixos/nixpkgs/nixos-25.11` | Stable — primary nixpkgs |
| `nixpkgs-unstable` | `github:nixos/nixpkgs/nixos-unstable` | Unstable — instantiated as `pkgs-unstable` in specialArgs |
| `home-manager` | `github:nix-community/home-manager/release-25.11` | Follows `nixpkgs` |
| `nix-gaming` | `github:fufexan/nix-gaming` | Follows `nixpkgs`; provides `nixosModules` |
| `nix-flatpak` | `github:gmodena/nix-flatpak` | Provides `nixosModules.nix-flatpak` |
| `nix-cachyos-kernel` | `github:xddxdd/nix-cachyos-kernel/release` | Provides `overlays.default` (does NOT follow nixpkgs) |

### 1.2 `mkVexosSystem` Builder

```nix
specialArgs = { inherit inputs pkgs-unstable; };
```

- All NixOS modules receive `inputs` and `pkgs-unstable` as extra arguments.
- Home Manager is wired as a NixOS module with:

```nix
home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable; };
home-manager.users.nimda = import ./home/default.nix;
```

- `home/default.nix` currently takes `{ config, pkgs, pkgs-unstable, ... }` — does NOT yet destructure `inputs`.

### 1.3 Notable Detail in `home/default.nix`

The GNOME favorites list already contains:

```nix
"system-update.desktop"
```

This entry does not correspond to any currently installed application. It is almost certainly a placeholder intended for the Up application's desktop file once integrated.

---

## 2. Up Flake Analysis

### 2.1 Repository Overview

- **Repo:** `https://github.com/VictoryTek/Up`
- **Description:** A modern Linux system update & upgrade GUI application
- **Language:** Rust (92.7%), Nix (2.9%), Meson (2.6%), Shell (1.8%)
- **License:** GPL-3.0-or-later
- **UI Stack:** GTK4 + libadwaita (GNOME HIG-compliant)
- **Target:** GNOME desktop — matches VexOS's desktop environment

### 2.2 Up Flake Inputs

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  flake-utils.url = "github:numtide/flake-utils";
};
```

Up targets **nixpkgs unstable**, not a stable channel.

### 2.3 Up Flake Outputs

Up uses `flake-utils.lib.eachDefaultSystem` which generates per-system outputs.

| Output | Path | Description |
|--------|------|-------------|
| `packages.${system}.default` | `packages.x86_64-linux.default` | The `up` binary — a GTK4/Rust app |
| `devShells.${system}.default` | `devShells.x86_64-linux.default` | Dev shell with Rust toolchain + GTK4 deps |

### 2.4 What Up Does NOT Expose

- **No `nixosModules`** — no NixOS system service or daemon
- **No `homeManagerModules`** — no declarative Home Manager integration module
- **No `overlays`** — no nixpkgs overlay

**Conclusion:** Up is a **pure package** — it must be consumed by referencing `inputs.up.packages.${system}.default` directly.

### 2.5 Package Build Details

```nix
packages.default = pkgs.rustPlatform.buildRustPackage {
  pname = "up";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    pkg-config
    meson          # For desktop file / GResources installation
    ninja
    wrapGAppsHook4 # GTK4 wrapper — populates GLib schema and icon paths
  ];

  buildInputs = with pkgs; [
    gtk4
    libadwaita
    glib
    dbus
  ];

  meta = {
    mainProgram = "up";
    platforms = platforms.linux;
    license = licenses.gpl3Plus;
  };
};
```

- `wrapGAppsHook4` ensures GLib schemas and GDK pixbuf loaders are available at runtime
- `meson`/`ninja` in `nativeBuildInputs` handle installation of desktop files, icons, and GResource bundles
- The Flatpak manifest is named `io.github.up.json`, strongly suggesting the application ID (and therefore the `.desktop` file) is `io.github.up.desktop`

### 2.6 App Functionality (Relevant to NixOS)

Up auto-detects the host OS and available package managers. On NixOS, the relevant backend is:

- **Nix backend** (`src/backends/nix.rs`) — updates Nix profile packages (both flake and legacy)
- Flatpak backend — updates installed Flatpak apps (VexOS uses Flatpak)
- Other backends (APT, DNF, Pacman, Zypper) — not applicable on NixOS

---

## 3. Proposed Integration Design

### 3.1 Architecture Decision

Since Up only provides `packages.default`, integration requires:

1. Adding `up` as a flake input
2. Referencing `inputs.up.packages.${system}.default` in `home.packages`
3. Making `inputs` accessible inside `home/default.nix`

No new modules, services, or overlays are needed.

### 3.2 nixpkgs Follows Strategy

Up declares `nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"`. VexOS already has `nixpkgs-unstable` pointing to `github:nixos/nixpkgs/nixos-unstable`.

**Best practice (Context7 / NixOS Flakes guide):** Use `inputs.nixpkgs.follows` to share a single nixpkgs instance and avoid evaluating two separate nixpkgs copies. Since Up targets unstable, follow `nixpkgs-unstable`:

```nix
up = {
  url = "github:VictoryTek/Up";
  inputs.nixpkgs.follows = "nixpkgs-unstable";
};
```

> Note: `flake-utils` (Up's second dependency) does not need a `follows` override — it is a pure Nix utility library with no nixpkgs dependency and has negligible eval cost.

### 3.3 Package Access Pattern

The package is accessed from any module that receives `inputs`:

```nix
inputs.up.packages.x86_64-linux.default
# or dynamically:
inputs.up.packages.${pkgs.stdenv.hostPlatform.system}.default
```

---

## 4. Exact Implementation Changes

### 4.1 Change 1 — `flake.nix`: Add `up` Input

**Location:** In the `inputs` block, after `nix-cachyos-kernel`:

```nix
# Up — modern Linux system update & upgrade GUI (GTK4 + libadwaita)
# Provides: packages.${system}.default
up = {
  url = "github:VictoryTek/Up";
  inputs.nixpkgs.follows = "nixpkgs-unstable";
};
```

**Full updated inputs block:**

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

  home-manager = {
    url = "github:nix-community/home-manager/release-25.11";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  nix-gaming = {
    url = "github:fufexan/nix-gaming";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  nix-flatpak.url = "github:gmodena/nix-flatpak";

  nix-cachyos-kernel = {
    url = "github:xddxdd/nix-cachyos-kernel/release";
  };

  # Up — modern Linux system update & upgrade GUI (GTK4 + libadwaita)
  # Provides: packages.${system}.default
  up = {
    url = "github:VictoryTek/Up";
    inputs.nixpkgs.follows = "nixpkgs-unstable";
  };
};
```

### 4.2 Change 2 — `flake.nix`: No Changes to `outputs`

`inputs` is already threaded through `specialArgs` and `home-manager.extraSpecialArgs`:

```nix
specialArgs = { inherit inputs pkgs-unstable; };
# ...
home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable; };
```

No changes to `mkVexosSystem` are required.

### 4.3 Change 3 — `home/default.nix`: Accept `inputs` Argument

**Current function signature:**

```nix
{ config, pkgs, pkgs-unstable, ... }:
```

**Updated function signature:**

```nix
{ config, pkgs, pkgs-unstable, inputs, ... }:
```

### 4.4 Change 4 — `home/default.nix`: Add Up to `home.packages`

**Location:** In the `home.packages` list, under a new "System Utilities" comment group.

**Addition:**

```nix
# System utilities
inputs.up.packages.${pkgs.stdenv.hostPlatform.system}.default
```

**Context in file** (after existing packages):

```nix
home.packages = with pkgs; [
  # Development tools
  vscode
  rustup
  pkgs-unstable.nodejs_25

  # ... (existing packages) ...

  # System utilities
  inputs.up.packages.${pkgs.stdenv.hostPlatform.system}.default
];
```

### 4.5 Change 5 — `home/default.nix`: Update GNOME Favorites

The existing favorites list contains `"system-update.desktop"`, which is a non-existent placeholder. This should be updated to match Up's actual desktop file ID.

**Based on the Flatpak manifest name `io.github.up.json`**, the application ID is `io.github.up`, making the desktop file `io.github.up.desktop`.

**Current:**

```nix
"system-update.desktop"
```

**Updated:**

```nix
"io.github.up.desktop"
```

> **Verification Note:** After the first successful build, confirm the desktop file ID by inspecting:
> `$(nix build github:VictoryTek/Up#default --print-out-paths)/share/applications/`

---

## 5. Step-by-Step Implementation Plan

### Step 1 — Edit `flake.nix`

Add the `up` input block (4.1 above) in the `inputs` section after `nix-cachyos-kernel`.

**File:** `flake.nix`  
**Change:** Insert 5-line `up` input block

### Step 2 — Edit `home/default.nix`: function signature

Update the top-level function signature to destructure `inputs`.

**File:** `home/default.nix`  
**Change:** Line 1 — add `inputs` to arg set

### Step 3 — Edit `home/default.nix`: add package

Add Up to the `home.packages` list with the dynamic system lookup.

**File:** `home/default.nix`  
**Change:** Append `inputs.up.packages.${pkgs.stdenv.hostPlatform.system}.default` to the packages list

### Step 4 — Edit `home/default.nix`: fix GNOME favorite

Replace the broken `"system-update.desktop"` with `"io.github.up.desktop"` in `dconf.settings`.

**File:** `home/default.nix`  
**Change:** Single string replacement in `favorite-apps`

### Step 5 — Run `nix flake update`

```bash
nix flake update up   # or: nix flake update (updates all)
```

This generates the `flake.lock` entry for `github:VictoryTek/Up` and its `flake-utils` transitive dependency.

### Step 6 — Validate

```bash
# Check flake evaluates cleanly
nix flake check

# Verify toplevel type
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf
```

---

## 6. Files Modified

| File | Change Summary |
|------|---------------|
| `flake.nix` | Add `up` input with `nixpkgs.follows = "nixpkgs-unstable"` |
| `home/default.nix` | Accept `inputs` argument; add Up to `home.packages`; fix GNOME favorite desktop id |
| `flake.lock` | Auto-updated by `nix flake update` |

---

## 7. Risks and Mitigations

### Risk 1: Desktop file ID mismatch

**Description:** The actual desktop file installed by Up's meson build may not be `io.github.up.desktop`. If the application ID in `meson.build` differs, the GNOME dock entry will silently not appear.  
**Severity:** Low — cosmetic only; the app still works  
**Mitigation:** After building, inspect `result/share/applications/` and correct the ID if needed. Alternatively, leave `favorite-apps` uncorrected until verified.

### Risk 2: `rustPlatform.buildRustPackage` + meson integration completeness

**Description:** The Up flake uses `rustPlatform.buildRustPackage` as the builder but lists `meson`/`ninja` only in `nativeBuildInputs`. The `buildRustPackage` derivation does not automatically run meson. If Up's desktop file, GResources, or icon is not installed, the app may launch but lack proper GNOME shell registration.  
**Severity:** Medium — app may work but not appear correctly in GNOME  
**Mitigation:** If desktop/icon data is missing post-build, the implementation subagent should inspect the full package derivation output. A `postInstall` hook may be needed in a local overlay. However, since this is the upstream-authored flake.nix, it is expected to function correctly.

### Risk 3: `nixpkgs.follows` version mismatch

**Description:** Up was written for `nixos-unstable`. If `nixpkgs-unstable` in VexOS is pinned to a much older or newer commit than expected by Up's Cargo dependencies, build failures could occur.  
**Severity:** Low — `flake.lock` pins exact revisions; build is reproducible  
**Mitigation:** If build fails, try removing `inputs.nixpkgs.follows` to let Up use its own pinned nixpkgs. Document the tradeoff (slightly more nixpkgs instantiations).

### Risk 4: `nix flake check` CI target impact

**Description:** `nix flake check` builds the `vexos` NixOS configuration. Adding Up as a `home.packages` entry means the package must be fetched and built during CI.  
**Severity:** Low — Up is a small Rust crate with few deps  
**Mitigation:** The `nix flake check` in VexOS builds only the `vexos` configuration. Up will be evaluated as part of `home.packages`. Network access is required for `cargo` dependencies unless a binary cache is available.

### Risk 5: NixOS-irrelevant update backends shown in UI

**Description:** Up's UI will display backends for APT, DNF, Pacman, etc. even on NixOS. These will simply report "not found" or be hidden. Only the Nix and Flatpak backends are relevant.  
**Severity:** Informational — no functional impact  
**Mitigation:** No action required. This is expected behavior of the application.

---

## 8. Context7 Research Notes

- **Library ID used:** `/websites/nixos-and-flakes_thiscute_world` (NixOS & Flakes guide, High reputation)
- **Pattern confirmed:** `inputs.nixpkgs.follows` is the canonical way to share nixpkgs instances across flake inputs; avoids evaluating duplicate nixpkgs copies
- **`specialArgs` / `extraSpecialArgs` pattern:** Confirmed as correct approach for passing flake-level values (like `inputs`) into NixOS modules and Home Manager configurations without using `_module.args`
- **Package access pattern:** For externally-built packages with no module, `inputs.flakeName.packages.${system}.default` is idiomatic

---

## 9. Summary

Up exposes only a **single Nix package** (`packages.${system}.default`). There are no NixOS modules, Home Manager modules, or overlays. The integration is minimal:

- One new input block in `flake.nix`
- One new function argument in `home/default.nix`
- One new package entry in `home.packages`
- One desktop file ID correction in `dconf.settings`

No new module files are needed. No changes to `hosts/`, `modules/`, or the `mkVexosSystem` builder are required.
