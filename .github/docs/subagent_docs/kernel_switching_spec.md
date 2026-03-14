# VexOS Kernel Switching — Specification

**Feature:** Multi-kernel switching with interactive selection
**Date:** 2026-03-13
**Status:** Research Complete / Ready for Implementation

---

## 1. Current Configuration Analysis

### Project Structure
VexOS is a modular, flake-based NixOS configuration following a clean separation pattern:

- **`flake.nix`** — Entry point. Defines `mkVexosSystem` library function, consumes `nixpkgs` (25.11), `nixpkgs-unstable`, `home-manager`, `nix-gaming`, `nix-flatpak`, and `nix-cachyos-kernel`.
- **`hosts/default/configuration.nix`** — Host config. Imports all modules, sets `gpu.type` and `kernel.type`.
- **`modules/`** — Reusable NixOS modules following a consistent pattern:
  - Option-first design: `lib.mkOption` declares typed options with enums
  - `lib.mkMerge` + `lib.mkIf` for conditional configuration per option value
  - Comprehensive documentation comments per module
  - Examples: `gpu.nix` (enum of `none/intel/amd/nvidia`), `kernel.nix` (enum of `stock/cachyos-gaming/cachyos-server`)
- **`home/default.nix`** — Home Manager config for user `nimda`
- **`justfile`** — Already contains `kernel`, `kernel-info`, `list-kernels`, `rebuild`, `rebuild-boot`, `preflight` recipes
- **`scripts/preflight.sh`** — CI validation: `nix flake check`, eval test, formatting, linting

### Current Kernel Module (`modules/kernel.nix`)
Already implements a three-option kernel selector:
- `"stock"` → `pkgs.linuxPackages_zen`
- `"cachyos-gaming"` → `pkgs.cachyosKernels.linuxPackages-cachyos-bore`
- `"cachyos-server"` → `pkgs.cachyosKernels.linuxPackages-cachyos-server`

CachyOS kernels are sourced via `nix-cachyos-kernel` flake overlay (`pkgs.cachyosKernels.*`), with binary caches for Attic (lantian) and Garnix already configured.

### Current Justfile
Already has a `just kernel` recipe using `fzf` for interactive selection, `sed` to update `configuration.nix`, and `nixos-rebuild boot` to apply changes. This pattern will be extended.

### Module Pattern Convention
All VexOS modules follow this structure:
1. Header comment with description and usage example
2. `let cfg = config.<module>;` binding
3. `options.<module>` with `lib.mkOption` using `lib.types.enum`
4. `config = lib.mkMerge [ ... ]` with `lib.mkIf` per variant

---

## 2. Problem Definition

The user wants to expand kernel selection beyond the current three options to include:

1. **Bazzite kernel** — Gaming-focused kernel from Universal Blue/Bazzite project, based on Fedora's kernel-ark with handheld/gaming patches
2. **CachyOS Gaming kernel** — Already implemented (BORE scheduler)
3. **CachyOS Server kernel** — Already implemented (EEVDF scheduler)
4. **Stock NixOS kernel** — Already implemented (Zen kernel fallback)

Additional requirements:
- Use Nix overlays to make kernels available
- `just kernel` command for interactive selection (already exists, needs expansion)
- Selection must persist across reboots (already works via `sed` on config file)
- x86_64 only
- User concerned about chaotic-nyx deprecation status

---

## 3. Kernel Source Research

### 3.1 chaotic-nyx — Status: CONFIRMED DEPRECATED

**Finding:** chaotic-cx/nyx was **archived on December 8, 2025**. The repository is now read-only.

- GitHub banner: "This repository was archived by the owner on Dec 8, 2025. It is now read-only."
- README states: "Originally launched at 2023-03-28 and killed at 2025-12-08"
- The user's belief is correct — chaotic-nyx is deprecated and should NOT be used.

**Impact:** VexOS does not use chaotic-nyx. The project correctly uses `xddxdd/nix-cachyos-kernel` instead.

### 3.2 xddxdd/nix-cachyos-kernel — Status: ACTIVE (Already in use)

**Finding:** Actively maintained, auto-updated, with binary caches. This is the **official recommended NixOS path** for CachyOS kernels (referenced directly by CachyOS upstream README under "Other Distributions > NixOS").

Key facts:
- **Repository:** `github:xddxdd/nix-cachyos-kernel/release`
- **Overlay:** `nix-cachyos-kernel.overlays.default` exposes `pkgs.cachyosKernels.*`
- **As of 2026-03-01:** Switched to pre-patched kernel sources from CachyOS releases. The `default` overlay is now safe (no version mismatch risk).
- **Available kernels:** `linuxPackages-cachyos-bore`, `linuxPackages-cachyos-server`, `linuxPackages-cachyos-latest`, `linuxPackages-cachyos-lts`, `linuxPackages-cachyos-eevdf`, `linuxPackages-cachyos-hardened`, `linuxPackages-cachyos-deckify`, `linuxPackages-cachyos-bmq`, `linuxPackages-cachyos-rt-bore`, plus LTO and architecture-optimized variants
- **Binary caches:** Hydra CI → `attic.xuyh0120.win/lantian`, Garnix → `cache.garnix.io`
- **Customizable:** `mkCachyKernel` supports overriding cpusched, lto, hzTicks, processorOpt, etc.
- **Stars:** 333, Contributors: 7, actively auto-updated (last commit: 4 hours ago as of research date)

**Impact:** VexOS already uses this correctly. More CachyOS variants can be exposed with zero additional flake inputs.

### 3.3 Bazzite Kernel — Status: COMPLEX TO PACKAGE FOR NIXOS

**Finding:** The Bazzite kernel (`bazzite-org/kernel-bazzite`) is a Fedora kernel-ark derivative with handheld/gaming patches. It is NOT designed for NixOS consumption.

Key facts:
- **Repository:** `github:bazzite-org/kernel-bazzite` (branch `bazzite-6.17`)
- **Build system:** RPM spec-based (`kernel.spec`), Docker containerized builds, Fedora-centric tooling
- **Patches:** `patch-1-redhat.patch` (Fedora base), `patch-2-handheld.patch` (handheld/gaming), `patch-3-akmods.patch`, `patch-4-amdgpu-vrr-whitelist.patch`
- **Source:** Based on Fedora's kernel-ark (Always Ready Kernel), not vanilla Linux
- **Current version:** 6.17.7-ba28
- **Architecture:** x86_64 + aarch64

**Feasibility for NixOS:**
- **Direct packaging: NOT FEASIBLE** — The Bazzite kernel uses Fedora's kernel-ark as its base (not vanilla Linux), with Fedora-specific config infrastructure. Replicating this in Nix's `buildLinux` would require:
  - Extracting all patches from the Fedora patchset
  - Maintaining a separate kernel config for NixOS
  - Tracking two upstream sources (kernel-ark + Bazzite patches)
  - No existing Nix infrastructure for this
- **Many Bazzite patches are ALREADY in CachyOS kernels** — CachyOS includes: BORE scheduler, handheld patches (Steam Deck, ROG Ally), HDR support, ASUS hardware patches, gaming optimizations. The overlap is substantial.
- **Unique Bazzite patches:** Primarily Fedora-specific fixes, some handheld quirks, and amdgpu VRR whitelist patches. Most of the "gaming magic" users perceive in Bazzite comes from CachyOS + fsync/NTsync (now mainline in recent kernels).

### 3.4 CachyOS Deckify Kernel — Status: AVAILABLE (Best Bazzite alternative)

**Finding:** `nix-cachyos-kernel` already provides `linuxPackages-cachyos-deckify` which includes `acpiCall = true` and `handheld = true` patches — covering the same Steam Deck/handheld use cases that Bazzite targets.

This is the closest NixOS-compatible equivalent to the Bazzite kernel, without the complexity of packaging a Fedora-derived kernel.

### 3.5 Additional CachyOS Variants Available

The `nix-cachyos-kernel` flake provides many more variants than VexOS currently exposes:

| Variant | Scheduler | Use Case | Package Name |
|---------|-----------|----------|--------------|
| Latest (EEVDF) | EEVDF | General desktop | `linuxPackages-cachyos-latest` |
| BORE | BORE | Gaming/interactive | `linuxPackages-cachyos-bore` |
| Server | EEVDF (300Hz, no preempt) | Server workloads | `linuxPackages-cachyos-server` |
| Deckify | EEVDF + handheld patches | Steam Deck/handhelds | `linuxPackages-cachyos-deckify` |
| LTS | EEVDF | Long-term stability | `linuxPackages-cachyos-lts` |
| Hardened | EEVDF + hardening | Security-focused | `linuxPackages-cachyos-hardened` |
| BMQ | BMQ | Alternative scheduler | `linuxPackages-cachyos-bmq` |
| RT-BORE | BORE + RT patches | Real-time audio/video | `linuxPackages-cachyos-rt-bore` |

All variants also available with Clang ThinLTO (append `-lto`).

---

## 4. Recommended Architecture

### Decision: Expand CachyOS variants, drop Bazzite, no separate repo needed

**Rationale:**
1. **CachyOS Deckify** covers 90%+ of Bazzite's unique value proposition (handheld patches, ACPI call support)
2. **nix-cachyos-kernel** already provides binary caches — no build infrastructure needed
3. A separate kernel repo would be massive maintenance overhead for marginal benefit
4. The `nix-cachyos-kernel` flake is actively maintained with automated updates

**Architecture:**
- **No new flake inputs** — `nix-cachyos-kernel` already provides everything
- **Expand `modules/kernel.nix`** — Add more CachyOS variants + keep stock Zen
- **Update `justfile`** — Expand the interactive menu with all available kernels
- **No separate GitHub repo needed** — Direct consumption from `nix-cachyos-kernel`

### Kernel Options to Expose

| `kernel.type` Value | Kernel | Description |
|---------------------|--------|-------------|
| `"stock"` | `pkgs.linuxPackages_zen` | NixOS Zen kernel — reliable desktop fallback |
| `"cachyos-gaming"` | `pkgs.cachyosKernels.linuxPackages-cachyos-bore` | CachyOS BORE — gaming/interactive, low-latency |
| `"cachyos-server"` | `pkgs.cachyosKernels.linuxPackages-cachyos-server` | CachyOS Server — throughput-optimized |
| `"cachyos-desktop"` | `pkgs.cachyosKernels.linuxPackages-cachyos-latest` | CachyOS Latest (EEVDF) — general desktop |
| `"cachyos-handheld"` | `pkgs.cachyosKernels.linuxPackages-cachyos-deckify` | CachyOS Deckify — handheld/Steam Deck (Bazzite alternative) |
| `"cachyos-lts"` | `pkgs.cachyosKernels.linuxPackages-cachyos-lts` | CachyOS LTS — long-term stability |
| `"cachyos-hardened"` | `pkgs.cachyosKernels.linuxPackages-cachyos-hardened` | CachyOS Hardened — security-focused |

**Why not Bazzite?** The Bazzite kernel is a Fedora kernel-ark derivative that cannot be cleanly packaged for NixOS without significant custom infrastructure. CachyOS Deckify provides equivalent handheld/gaming functionality through a well-maintained NixOS-native path.

---

## 5. Implementation Plan

### 5.1 File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `modules/kernel.nix` | **Modify** | Expand enum to include new kernel types |
| `justfile` | **Modify** | Expand kernel menu and list-kernels with new options |
| `hosts/default/configuration.nix` | **No change** | Already has `kernel.type = "stock"` (still valid) |
| `flake.nix` | **No change** | `nix-cachyos-kernel` overlay already applied |

### 5.2 Module: `modules/kernel.nix` — Updated Specification

The module must be updated to:
1. Expand the `lib.types.enum` to include 4 new kernel types
2. Add `lib.mkIf` blocks for each new kernel type
3. Simplify CachyOS detection for binary cache config using a prefix check
4. Maintain all existing comments and documentation conventions

**New enum values:**
```
"stock" | "cachyos-gaming" | "cachyos-server" | "cachyos-desktop" | "cachyos-handheld" | "cachyos-lts" | "cachyos-hardened"
```

**Kernel package mappings:**
```nix
"stock"             → pkgs.linuxPackages_zen
"cachyos-gaming"    → pkgs.cachyosKernels.linuxPackages-cachyos-bore
"cachyos-server"    → pkgs.cachyosKernels.linuxPackages-cachyos-server
"cachyos-desktop"   → pkgs.cachyosKernels.linuxPackages-cachyos-latest
"cachyos-handheld"  → pkgs.cachyosKernels.linuxPackages-cachyos-deckify
"cachyos-lts"       → pkgs.cachyosKernels.linuxPackages-cachyos-lts
"cachyos-hardened"  → pkgs.cachyosKernels.linuxPackages-cachyos-hardened
```

**Binary cache detection:**
Replace the current `builtins.elem cfg.type [ "cachyos-gaming" "cachyos-server" ]` with:
```nix
isCachyos = builtins.substring 0 7 cfg.type == "cachyos";
```
This automatically covers all current and future `cachyos-*` variants.

### 5.3 Justfile — Updated Specification

#### `kernel` recipe changes:
Expand the `KERNELS` array to include all 7 options:
```bash
KERNELS=(
    "stock|NixOS Zen Kernel — Standard desktop kernel (default)"
    "cachyos-gaming|CachyOS Gaming (BORE) — Gaming-optimized, low-latency"
    "cachyos-desktop|CachyOS Desktop (EEVDF) — General-purpose desktop"
    "cachyos-handheld|CachyOS Handheld (Deckify) — Steam Deck & handhelds"
    "cachyos-server|CachyOS Server (EEVDF 300Hz) — Server-optimized, high-throughput"
    "cachyos-lts|CachyOS LTS — Long-term support, stability-focused"
    "cachyos-hardened|CachyOS Hardened — Security-focused with hardening patches"
)
```

Increase `fzf --height` from `10` to `12` to accommodate the expanded list.

#### `list-kernels` recipe changes:
Add entries for the 4 new kernel options with consistent formatting.

### 5.4 No Changes to `flake.nix`

The existing flake already:
- Imports `nix-cachyos-kernel` as an input (on `release` branch)
- Applies the `overlays.default` overlay in `mkVexosSystem`
- Does NOT override `nixpkgs` (correctly preserving kernel patch compatibility)

All new kernel variants are already available through `pkgs.cachyosKernels.*` — no flake modifications needed.

---

## 6. Kernel Options Detail

### Stock (NixOS Zen)
- **Package:** `pkgs.linuxPackages_zen`
- **Source:** nixpkgs (`linuxKernel.kernels.linux_zen`)
- **Scheduler:** CFS/EEVDF (vanilla + Zen patches)
- **Use case:** Reliable fallback, well-tested in nixpkgs
- **Binary cache:** Standard nixpkgs cache
- **Timer:** Default (250Hz)

### CachyOS Gaming (BORE)
- **Package:** `pkgs.cachyosKernels.linuxPackages-cachyos-bore`
- **Source:** nix-cachyos-kernel → CachyOS/linux-cachyos `bore` variant
- **Scheduler:** BORE (Burst-Oriented Response Enhancer)
- **Use case:** Gaming, interactive desktop, low-latency workloads
- **Key settings:** 1000Hz timer, full preemption, BORE scheduler, O3 optimizations
- **Binary cache:** lantian Attic + Garnix

### CachyOS Desktop (Latest EEVDF)
- **Package:** `pkgs.cachyosKernels.linuxPackages-cachyos-latest`
- **Source:** nix-cachyos-kernel → CachyOS/linux-cachyos default variant
- **Scheduler:** EEVDF (Earliest Eligible Virtual Deadline First)
- **Use case:** General desktop computing, balanced performance
- **Key settings:** 1000Hz timer, full preemption, EEVDF, O3 optimizations
- **Binary cache:** lantian Attic + Garnix

### CachyOS Server
- **Package:** `pkgs.cachyosKernels.linuxPackages-cachyos-server`
- **Source:** nix-cachyos-kernel → CachyOS/linux-cachyos `server` variant
- **Scheduler:** EEVDF
- **Use case:** Server workloads, throughput-focused
- **Key settings:** 300Hz timer, no preemption, EEVDF, O3 optimizations
- **Binary cache:** lantian Attic + Garnix

### CachyOS Handheld (Deckify)
- **Package:** `pkgs.cachyosKernels.linuxPackages-cachyos-deckify`
- **Source:** nix-cachyos-kernel → CachyOS/linux-cachyos `deckify` variant
- **Scheduler:** EEVDF (with handheld patches)
- **Use case:** Steam Deck, ROG Ally, Legion Go, other handhelds
- **Key settings:** ACPI call patch, handheld hardware patches, 1000Hz timer
- **Acts as:** NixOS-native Bazzite kernel alternative
- **Binary cache:** lantian Attic + Garnix

### CachyOS LTS
- **Package:** `pkgs.cachyosKernels.linuxPackages-cachyos-lts`
- **Source:** nix-cachyos-kernel → CachyOS/linux-cachyos `lts` variant
- **Scheduler:** EEVDF
- **Use case:** Systems requiring maximum stability, production workloads
- **Key settings:** LTS kernel version, EEVDF, O3 optimizations
- **Binary cache:** lantian Attic + Garnix

### CachyOS Hardened
- **Package:** `pkgs.cachyosKernels.linuxPackages-cachyos-hardened`
- **Source:** nix-cachyos-kernel → CachyOS/linux-cachyos `hardened` variant
- **Scheduler:** EEVDF
- **Use case:** Security-sensitive environments
- **Key settings:** Hardening patches, attack surface reduction
- **Binary cache:** lantian Attic + Garnix

---

## 7. Justfile Design

### Interactive Flow (`just kernel`)

```
$ just kernel

VexOS Kernel Selector
=====================

  NixOS Zen Kernel — Standard desktop kernel (default)
  CachyOS Gaming (BORE) — Gaming-optimized, low-latency
  CachyOS Desktop (EEVDF) — General-purpose desktop
  CachyOS Handheld (Deckify) — Steam Deck & handhelds
  CachyOS Server (EEVDF 300Hz) — Server-optimized, high-throughput
  CachyOS LTS — Long-term support, stability-focused
  CachyOS Hardened — Security-focused with hardening patches

Select kernel: _

Selected: cachyos-gaming

Updated hosts/default/configuration.nix with kernel.type = "cachyos-gaming"

Rebuilding NixOS (boot)...
[nixos-rebuild output]

Done! Reboot to use the new kernel.
```

### Mechanism
1. **Display:** `fzf` presents a fuzzy-searchable menu of kernel descriptions
2. **Selection:** Maps the chosen description back to the `kernel.type` enum value
3. **Persistence:** `sed` replaces the `kernel.type = "..."` line in `hosts/default/configuration.nix`
4. **Rebuild:** `sudo nixos-rebuild boot --flake .#vexos` stages the new kernel for next boot
5. **Safety:** Uses `boot` not `switch` — kernel changes require reboot, no live-switching risk

### Related Recipes
- `just kernel-info` — Shows running kernel (`uname -r`) and configured `kernel.type`
- `just list-kernels` — Lists all kernel options with descriptions
- `just rebuild` — Immediate rebuild (`switch`)
- `just rebuild-boot` — Rebuild for next boot

---

## 8. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CachyOS kernel binary cache unavailable (Garnix free tier exceeded) | Medium | Build from source (slow, ~30-60 min) | Two caches configured (lantian + Garnix); `release` branch guarantees binary availability via Hydra CI |
| CachyOS kernel patch version mismatch | Low | Build failure | `release` branch only contains tested/built kernels; `default` overlay is safe since 2026-03-01 switch to pre-patched sources |
| NVIDIA driver incompatibility with CachyOS kernel | Low | GPU driver fail | `nix-cachyos-kernel` tests NVIDIA module builds in CI; `gpu.nix` uses `config.boot.kernelPackages.nvidiaPackages.stable` which auto-adjusts |
| ASUS module compatibility | Low | Missing ASUS features | CachyOS deckify includes ASUS hardware patches; asusd operates at userspace/ACPI level, not kernel-dependent |
| User picks wrong kernel for their hardware | Medium | Poor performance or instability | `just kernel-info` shows running kernel; `just kernel` allows easy switching back; GRUB allows booting previous generation |
| `sed` regex misses target in configuration.nix | Very Low | Config not updated | Regex `kernel\.type = \"[^\"]*\"` is specific; already tested in current justfile |

### Rollback Strategy
NixOS generations provide built-in rollback:
1. GRUB menu shows previous generations
2. `sudo nixos-rebuild switch --rollback` reverts to previous generation
3. `just kernel` can be re-run to select a different kernel

---

## 9. Separate Repo Specification (NOT RECOMMENDED)

### Why Not Recommended
Based on research, a separate kernel-building repo is **not recommended** because:

1. **CachyOS covers all identified use cases** via `nix-cachyos-kernel`
2. **Bazzite kernel is Fedora-derived** — packaging for NixOS requires Fedora-kernel-ark infrastructure
3. **Maintenance burden** — Kernel building CI requires significant compute, ongoing patch rebasing, and security monitoring
4. **Binary cache hosting** — Would need Cachix or similar infrastructure (~$10-50/month)
5. **CachyOS already provides binary caches** — No infrastructure needed

### If User Still Wants This (Future Reference)

A separate repo would look like:

```
vex-kernels/
├── flake.nix            # Exposes kernel packages
├── flake.lock
├── kernels/
│   ├── bazzite/
│   │   ├── default.nix  # buildLinux with Bazzite patches
│   │   ├── config       # x86_64 kernel config extracted from Bazzite
│   │   └── patches/     # Extracted patches from kernel-bazzite
│   └── custom/
│       └── default.nix  # Any other custom kernel
├── .github/
│   └── workflows/
│       └── build.yml    # GitHub Actions: nix build, push to Cachix
└── README.md
```

**GitHub Actions workflow would:**
1. Run on schedule (weekly) and PR
2. `nix build .#linux-bazzite`
3. Push to Cachix binary cache
4. Tag release with kernel version

**VexOS consumption:**
```nix
inputs.vex-kernels.url = "github:VictoryTek/vex-kernels";
# Then in modules/kernel.nix:
# boot.kernelPackages = inputs.vex-kernels.packages.x86_64-linux.linuxPackages-bazzite;
```

**Estimated maintenance:** 2-4 hours/month for patch rebasing, config updates, build fixes.

This approach is documented here for reference but is **deferred** in favor of the CachyOS-based solution which requires zero custom infrastructure.

---

## 10. Implementation Checklist

- [ ] Update `modules/kernel.nix` — Expand enum and add kernel mappings for 4 new types
- [ ] Update `justfile` — Expand `kernel` recipe `KERNELS` array and `list-kernels` recipe
- [ ] Verify `flake.nix` — Confirm no changes needed (overlay already covers all variants)
- [ ] Verify `hosts/default/configuration.nix` — Confirm `kernel.type = "stock"` still valid as default
- [ ] Test: `nix flake check` passes (on NixOS host, not this dev machine)
- [ ] Test: `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf` succeeds (on NixOS host)

---

## 11. Sources

1. **chaotic-cx/nyx** — https://github.com/chaotic-cx/nyx — Archived Dec 8, 2025 (CONFIRMED DEPRECATED)
2. **xddxdd/nix-cachyos-kernel** — https://github.com/xddxdd/nix-cachyos-kernel — Active, 333 stars, binary caches available
3. **CachyOS/linux-cachyos** — https://github.com/CachyOS/linux-cachyos — Upstream kernel definitions, 3k stars
4. **bazzite-org/kernel-bazzite** — https://github.com/bazzite-org/kernel-bazzite — Fedora kernel-ark derivative, 98 stars
5. **ublue-os/bazzite** — https://github.com/ublue-os/bazzite — Uses fsync/Bazzite kernel, 8k stars
6. **NixOS/nixpkgs** — Linux kernel documentation: `boot.kernelPackages`, `buildLinux`, `linuxPackagesFor`
7. **CachyOS kernel-patches** — https://github.com/CachyOS/kernel-patches — Patches consumed by nix-cachyos-kernel
8. **nix-cachyos-kernel README** — Detailed overlay usage, binary cache config, customization via `mkCachyKernel`
