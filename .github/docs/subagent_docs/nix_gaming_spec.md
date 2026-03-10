# nix-gaming Integration Specification for VexOS

**Feature:** nix-gaming flake integration  
**Date:** 2026-03-10  
**Status:** DRAFT — Research & Specification Phase  

---

## 1. Current Configuration Analysis

### Existing Gaming Setup (modules/gaming.nix)

- **Steam** enabled via `programs.steam` with remotePlay and localNetworkGameTransfers firewall rules open.
- **GameMode** (Feral Interactive) enabled with renice=10 and GPU optimisations accepted.
- **Manual sysctl tweaks** already present:
  - `vm.max_map_count = 2147483642` — required by games with many memory mappings.
  - `kernel.split_lock_mitigate = 0` — prevents split-lock performance penalties.

### PipeWire Setup (hosts/default/configuration.nix)

```nix
services.pulseaudio.enable = false;
security.rtkit.enable = true;
services.pipewire = {
  enable = true;
  alsa.enable = true;
  alsa.support32Bit = true;
  pulse.enable = true;
};
```

Standard latency PipeWire with no gaming optimisations.

### GPU (modules/gpu.nix)

Declarative GPU module; currently `gpu.type = "none"` in configuration.nix (template default).  
Supports nvidia / amd / intel with `hardware.graphics.enable32Bit = true` for Wine/Steam.

### Home Manager (home/default.nix)

Function signature: `{ config, pkgs, ... }:` — does **not** currently receive `inputs`.  
No gaming packages in home.packages.

### flake.nix

Inputs: `nixpkgs` (nixos-25.11), `home-manager` (release-25.11) only.  
`specialArgs = { inherit inputs; }` is already passed to nixosSystem.  
`home-manager.users.nimda = import ./home/default.nix` — no `extraSpecialArgs` yet.

---

## 2. nix-gaming Components Evaluated

Source: <https://github.com/fufexan/nix-gaming>  
README: <https://raw.githubusercontent.com/fufexan/nix-gaming/master/README.md>  
Flake outputs: verified via `pkgs/default.nix` and `modules/default.nix`.

### ✅ INCLUDE: `pipewireLowLatency` NixOS Module

**Module name:** `inputs.nix-gaming.nixosModules.pipewireLowLatency`  
**Enabled via:** `services.pipewire.lowLatency.enable = true`  
**Defaults:** `quantum = 64`, `rate = 48000` (theoretical latency: 64/48000 ≈ 1.33ms)  

What it does:
- Sets `default.clock.min-quantum` to the configured quantum.
- Configures `libpipewire-module-rt` for real-time scheduling (nice=-15, rt.prio=88).
- Configures PulseAudio-compatible streams with `pulse.min.req`, `pulse.min.quantum`, `pulse.min.frag`.
- Sets `resample.quality = 1` for low-CPU resampling.
- Optionally applies ALSA hardware-level overrides via WirePlumber (`alsa.enable`).

VexOS relevance: **HIGH** — ASUS TUF gaming laptop benefits greatly from low-latency audio, especially for games with audio cues and voice chat.

### ✅ INCLUDE: `platformOptimizations` NixOS Module

**Module name:** `inputs.nix-gaming.nixosModules.platformOptimizations`  
**Enabled via:** `programs.steam.platformOptimizations.enable = true`  
**Extends:** `programs.steam` module from nixpkgs (can also work without Steam enabled).

What it does (sets the same sysctl values as SteamOS on Steam Deck):
- `kernel.sched_cfs_bandwidth_slice_us = 3000` — tighter CFS scheduling for smoother frame delivery.
- `net.ipv4.tcp_fin_timeout = 5` — faster TCP cleanup for games killed/restarted quickly.
- `kernel.split_lock_mitigate = 0` — same as current gaming.nix (will CONFLICT — must remove).
- `vm.max_map_count = 2147483642` — same as current gaming.nix (will CONFLICT — must remove).

VexOS relevance: **HIGH** — Provides official SteamOS-equivalent kernel tuning from a maintained upstream source; replaces the two manual sysctl entries already in gaming.nix.

### ✅ INCLUDE: `proton-ge-bin` from nixpkgs (NOT nix-gaming)

> ⚠️ **IMPORTANT:** `proton-ge` in nix-gaming is **DEPRECATED** as of 2024-03-17.  
> The package now emits a warning and returns `pkgs.emptyFile`.  
> The official replacement is `pkgs.proton-ge-bin` from Nixpkgs, configured via  
> `programs.steam.extraCompatPackages`.  
> See: <https://github.com/NixOS/nixpkgs/pull/296009>

**Package:** `pkgs.proton-ge-bin` (from nixpkgs, available in nixos-24.11+)  
**Configured via:** `programs.steam.extraCompatPackages = [ pkgs.proton-ge-bin ]`

What it does:
- Makes GE-Proton (Glorious Eggroll's Proton fork) available as a Steam compatibility tool.
- GE-Proton includes extra patches for better compatibility: media codecs, EAC/BE anti-cheat workarounds, FSR integration, Wayland improvements, DLSS patches, etc.
- Appears in Steam → Settings → Compatibility → "GE-Proton (version)" per-game override.

VexOS relevance: **HIGH** — Essential for gaming on Linux; many games require GE-Proton for audio, cutscenes, or better performance.

### ✅ INCLUDE: `wine-ge` from nix-gaming

**Package:** `inputs.nix-gaming.packages.${pkgs.stdenv.hostPlatform.system}.wine-ge`  
**Added to:** `home.packages` in home/default.nix  

What it does:
- wine-ge is Glorious Eggroll's Wine fork with gaming patches: FSR support, media codec patches, Esync/Fsync, better game compatibility.
- Useful for running non-Steam Windows games (e.g., GOG games via Heroic, Lutris games, standalone Windows executables).

VexOS relevance: **MEDIUM-HIGH** — Valuable for any non-Steam Windows game without Steam's Proton.

### ✅ INCLUDE: Cachix Binary Cache

**Cache URL:** `https://nix-gaming.cachix.org`  
**Public key:** `nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=`

Essential to add — wine-ge is a large package and takes significant time to compile from source. The Cachix cache provides pre-built binaries.

### ❌ SKIP: `osu-lazer-bin`, `osu-stable`, `rocket-league`

Not applicable to a general gaming laptop setup.

### ❌ SKIP: `steamCompat` module

Deprecated. Functionality now built into nixpkgs Steam module via `extraCompatPackages`.

### ❌ SKIP: `wine` module (ntsync)

The `ntsync` / `wine` module is for specific kernel-level Wine synchronisation primitives. Not needed for standard gaming setup.

### ❌ SKIP: `star-citizen`, `faf-client`, `northstar-proton`, etc.

Game-specific packages not applicable for a general-purpose gaming configuration.

---

## 3. flake.nix Changes

### 3.1 Add nix-gaming Input

Add to the `inputs` attrset:

```nix
nix-gaming = {
  url = "github:fufexan/nix-gaming";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Why `inputs.nixpkgs.follows = "nixpkgs"`:**  
nix-gaming's own flake.nix uses `github:NixOS/nixpkgs/nixpkgs-unstable`. Without the `follows`, Nix would evaluate nix-gaming's packages against a different nixpkgs version, causing two separate nixpkgs instances in the build closure — wasted build time and larger closure size. Making it follow our `nixos-25.11` nixpkgs keeps everything consistent.

### 3.2 Update outputs Argument Binding

The current `outputs` destructures: `{ self, nixpkgs, home-manager, ... }@inputs`.  
The `...` already captures nix-gaming via `inputs`. No change needed here since modules receive `inputs` via `specialArgs`.

### 3.3 Add extraSpecialArgs for Home Manager

Inside the home-manager configuration block:

```nix
home-manager.extraSpecialArgs = { inherit inputs; };
```

This allows `home/default.nix` to access `inputs.nix-gaming.packages.…` for wine-ge.

### 3.4 Full flake.nix After Changes

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
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    nixosConfigurations = {
      vexos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/default/configuration.nix
          ./hosts/default/hardware-configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.nimda = import ./home/default.nix;
          }
        ];
      };
    };
  };
}
```

---

## 4. modules/gaming.nix Changes

### 4.1 Add inputs Parameter

Change function signature from:
```nix
{ config, pkgs, ... }:
```
To:
```nix
{ config, lib, pkgs, inputs, ... }:
```

(`lib` is needed for some module patterns; `inputs` needed for nix-gaming module imports)

### 4.2 Import nix-gaming NixOS Modules

Add an `imports` block:

```nix
imports = [
  inputs.nix-gaming.nixosModules.pipewireLowLatency
  inputs.nix-gaming.nixosModules.platformOptimizations
];
```

### 4.3 Enable platformOptimizations

```nix
programs.steam.platformOptimizations.enable = true;
```

### 4.4 Enable pipewireLowLatency

```nix
services.pipewire.lowLatency = {
  enable = true;
  quantum = 64;   # 64/48000 ≈ 1.33ms latency
  rate = 48000;
};
```

Note: `services.pipewire.enable = true`, `alsa.enable`, etc. are already set in `configuration.nix`.  
The lowLatency module extends the existing config — no duplication.

### 4.5 Add proton-ge-bin as Steam Compat Tool

```nix
programs.steam.extraCompatPackages = [ pkgs.proton-ge-bin ];
```

### 4.6 Add Cachix Binary Cache

```nix
nix.settings = {
  substituters = [ "https://nix-gaming.cachix.org" ];
  trusted-public-keys = [
    "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
  ];
};
```

### 4.7 Remove Duplicate sysctl Entries

**CRITICAL:** The following entries in the current `boot.kernel.sysctl` block are now covered by `platformOptimizations` and MUST be removed to avoid Nix evaluation conflict:

```nix
# REMOVE these — platformOptimizations sets them:
"vm.max_map_count" = 2147483642;
"kernel.split_lock_mitigate" = 0;
```

The entire `boot.kernel.sysctl` block can be removed since these were its only two entries.

### 4.8 Full modules/gaming.nix After Changes

```nix
# modules/gaming.nix
#
# Gaming support module: Steam, GameMode, nix-gaming enhancements.
# Provides: platformOptimizations (SteamOS sysctl tweaks),
#           pipewireLowLatency (low-latency audio),
#           proton-ge-bin (GE-Proton as Steam compat tool),
#           nix-gaming Cachix binary cache.
#
# Note: Requires gpu.type to be set (nvidia/amd/intel) in configuration.nix
# for Steam and games to function properly.

{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    inputs.nix-gaming.nixosModules.pipewireLowLatency
    inputs.nix-gaming.nixosModules.platformOptimizations
  ];

  # ── Cachix binary cache (avoids building wine-ge from source) ─────────
  nix.settings = {
    substituters = [ "https://nix-gaming.cachix.org" ];
    trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  };

  # ── Steam ────────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = true;

    # GE-Proton: custom Proton fork with extra patches for better
    # game compatibility (codecs, anti-cheat, FSR, DLSS, Wayland, etc.)
    # Replaces the deprecated proton-ge package from nix-gaming.
    extraCompatPackages = [ pkgs.proton-ge-bin ];

    # SteamOS-equivalent sysctl tweaks from nix-gaming platformOptimizations
    platformOptimizations.enable = true;
  };

  # ── GameMode (Feral Interactive) ──────────────────────────────────────
  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = 0;
      };
    };
  };

  # ── PipeWire Low Latency ─────────────────────────────────────────────
  # Extends the PipeWire configuration in configuration.nix.
  # Theoretical latency: quantum/rate = 64/48000 ≈ 1.33ms
  # If audio cuts out, increase quantum to 128 or 256.
  services.pipewire.lowLatency = {
    enable = true;
    quantum = 64;
    rate = 48000;
  };
}
```

---

## 5. home/default.nix Changes

### 5.1 Add inputs to Function Signature

Change:
```nix
{ config, pkgs, ... }:
```
To:
```nix
{ config, pkgs, inputs, ... }:
```

### 5.2 Add wine-ge to home.packages

Add to the `home.packages` list:

```nix
# Wine (GE build) — for running non-Steam Windows games
# wine-ge includes Esync/Fsync, FSR, media codecs, and gaming patches
inputs.nix-gaming.packages.${pkgs.stdenv.hostPlatform.system}.wine-ge
```

This makes wine-ge available in the user's PATH as `wine`, `wine64`, `winecfg`, etc.

---

## 6. Exact Syntax Reference

### flake.nix Input Declaration

```nix
nix-gaming = {
  url = "github:fufexan/nix-gaming";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Passing inputs to Home Manager

```nix
home-manager.extraSpecialArgs = { inherit inputs; };
```

### NixOS Module Import (inside a NixOS module file)

```nix
imports = [
  inputs.nix-gaming.nixosModules.pipewireLowLatency
  inputs.nix-gaming.nixosModules.platformOptimizations
];
```

### platformOptimizations Enable

```nix
programs.steam.platformOptimizations.enable = true;
```

### pipewireLowLatency Enable

```nix
services.pipewire.lowLatency = {
  enable = true;
  quantum = 64;
  rate = 48000;
};
```

### proton-ge-bin (nixpkgs, NOT nix-gaming)

```nix
programs.steam.extraCompatPackages = [ pkgs.proton-ge-bin ];
```

### wine-ge Package Reference

```nix
inputs.nix-gaming.packages.${pkgs.stdenv.hostPlatform.system}.wine-ge
```

### Cachix Cache (nix.settings)

```nix
nix.settings = {
  substituters = [ "https://nix-gaming.cachix.org" ];
  trusted-public-keys = [
    "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
  ];
};
```

---

## 7. Risks and Mitigations

### Risk 1: sysctl Conflict (CRITICAL)

**Problem:** `modules/gaming.nix` currently sets `vm.max_map_count` and `kernel.split_lock_mitigate` manually. The `platformOptimizations` module sets the same keys. Nix will throw an evaluation error if the same `boot.kernel.sysctl` key is set in multiple places without `mkDefault`/`mkForce`.

**Mitigation:** Remove the `boot.kernel.sysctl` block entirely from gaming.nix. platformOptimizations covers these values and adds `kernel.sched_cfs_bandwidth_slice_us` and `net.ipv4.tcp_fin_timeout` as additional improvements.

### Risk 2: nixpkgs Version Compatibility

**Problem:** nix-gaming's own flake uses `nixpkgs-unstable`. Some nix-gaming packages (like wine-ge) may depend on unstable-specific package attributes.

**Mitigation:** Use `inputs.nixpkgs.follows = "nixpkgs"` to pin nix-gaming to our `nixos-25.11` nixpkgs. Since nixos-25.11 is a fixed release (stable), package attributes should be compatible. If a wine-ge build fails due to a missing dependency in 25.11, the fallback is to remove `inputs.nixpkgs.follows` and accept the dual-nixpkgs overhead.

### Risk 3: wine-ge Build Time Without Cache

**Problem:** wine-ge is a large package (multi-GB build). Without the Cachix cache, it may take 1-2 hours to build.

**Mitigation:** The Cachix cache (`https://nix-gaming.cachix.org`) is included in `nix.settings` in gaming.nix. Ensure it is configured before the first `nixos-rebuild switch`. Note: `nix.settings.trusted-public-keys` may require a trusted user or root to apply — using `nix.settings.substituters` with the `extra-substituters` format in user nix.conf may also work.

### Risk 4: pipewireLowLatency Audio Dropouts

**Problem:** `quantum = 64` may be too aggressive for some USB or HDMI audio devices, causing audio dropouts or crackling.

**Mitigation:** The spec defaults to `quantum = 64` (1.33ms), which works for most systems. If dropouts occur, increase to `quantum = 128` (2.67ms) or `quantum = 256` (5.33ms). Gaming audio quality difference below 10ms is imperceptible; the primary benefit is reduced round-trip latency for audio feedback in games.

### Risk 5: proton-ge-bin Not in nixos-25.11

**Problem:** `pkgs.proton-ge-bin` was merged into nixpkgs in the 24.11 cycle. If it's not available in nixos-25.11, the build will fail.

**Mitigation:** `proton-ge-bin` was added to nixpkgs in late 2024 (PR #296009) and is present in nixos-24.11 and later, so nixos-25.11 will have it. If absent, use `pkgs.proton-ge-bin` from nixpkgs-unstable as an overlay, or add it as a nix-gaming package (noting the deprecated warning).

### Risk 6: nix-gaming modules require `programs.steam` to be enabled

**Problem:** `platformOptimizations` extends the Steam module. If `programs.steam.enable = false`, the option `programs.steam.platformOptimizations.enable` still exists but has no effect.

**Mitigation:** `programs.steam.enable = true` is already set in gaming.nix. No conflict.

### Risk 7: nix-gaming nixpkgs.follows and flake-parts compatibility

**Problem:** nix-gaming uses `flake-parts`. When using `inputs.nixpkgs.follows`, there may be edge cases with how flake-parts resolves the nixpkgs. 

**Mitigation:** This is a standard and well-tested pattern in the nix-gaming user community. The `follows` attribute is applied before evaluation, so flake-parts sees our nixpkgs. If issues arise, remove `inputs.nixpkgs.follows` as a first debugging step.

---

## 8. Implementation Steps Summary

For the Implementation Subagent (Phase 2):

1. **Edit `flake.nix`:**
   - Add `nix-gaming` input with `inputs.nixpkgs.follows = "nixpkgs"`.
   - Add `home-manager.extraSpecialArgs = { inherit inputs; }` in the HM config block.

2. **Edit `modules/gaming.nix`:**
   - Add `lib` and `inputs` to function args.
   - Add `imports` block with the two nix-gaming NixOS modules.
   - Add `nix.settings` Cachix cache block.
   - Add `programs.steam.extraCompatPackages = [ pkgs.proton-ge-bin ]`.
   - Add `programs.steam.platformOptimizations.enable = true`.
   - Add `services.pipewire.lowLatency` block.
   - **Remove** the `boot.kernel.sysctl` block (both entries replaced by platformOptimizations).

3. **Edit `home/default.nix`:**
   - Add `inputs` to function signature.
   - Add `wine-ge` to `home.packages` list.

**Files modified:**
- `flake.nix`
- `modules/gaming.nix`
- `home/default.nix`

**Files NOT modified:**
- `hosts/default/configuration.nix` — PipeWire base config stays as-is; lowLatency extends it.
- `modules/system.nix` — No changes needed.
- `modules/asus.nix` — No changes needed.
- `modules/gpu.nix` — No changes needed.
- `modules/gnome.nix` — No changes needed.
- `modules/users.nix` — No changes needed.

---

## 9. Component Integration Summary Table

| Component | Source | Integration Point | Priority |
|-----------|--------|-------------------|----------|
| `pipewireLowLatency` | nix-gaming NixOS module | `modules/gaming.nix` imports | HIGH |
| `platformOptimizations` | nix-gaming NixOS module | `modules/gaming.nix` imports | HIGH |
| `proton-ge-bin` | nixpkgs (stable) | `programs.steam.extraCompatPackages` | HIGH |
| `wine-ge` | nix-gaming package | `home/default.nix` home.packages | MEDIUM |
| Cachix binary cache | nix-gaming cachix | `nix.settings` in gaming.nix | HIGH |
| Remove duplicate sysctl | N/A (cleanup) | `modules/gaming.nix` | CRITICAL |
| `extraSpecialArgs` | flake HM config | `flake.nix` | REQUIRED |

---

*Spec file: `.github/docs/subagent_docs/nix_gaming_spec.md`*  
*Researched sources: nix-gaming README, flake.nix, pkgs/default.nix, modules/default.nix, modules/platformOptimizations.nix, modules/pipewireLowLatency.nix, nixpkgs PR #296009*
