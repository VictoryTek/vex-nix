# VexOS — NixOS 25.11 Upgrade & GPU Auto-Selection Specification

**Date:** 2026-03-10  
**Status:** DRAFT — Ready for Implementation  
**Spec Author:** Research Subagent (Phase 1)

---

## 1. Current State Analysis

### 1.1 Repository Overview

| File | Notes |
|---|---|
| `flake.nix` | Uses `nixos-unstable`; no `nixos-25.11` pin yet |
| `hosts/default/configuration.nix` | `system.stateVersion = "24.05"` |
| `home/default.nix` | `home.stateVersion = "24.05"` |
| `modules/gnome.nix` | No OpenGL/GPU options set |
| `modules/system.nix` | No GPU options set |
| `modules/gpu.nix` | Does not exist — must be created |
| `hardware-configuration.nix` | `kvm-intel` in kernelModules; Intel CPU template |

### 1.2 Current Flake Inputs (verbatim)

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### 1.3 GPU Configuration — Current State

**No GPU configuration exists anywhere in the repository.** No `hardware.graphics`, no `hardware.opengl`, no `services.xserver.videoDrivers`. The system relies entirely on kernel defaults (modesetting / nouveau).

### 1.4 Important Note on stateVersion

`system.stateVersion = "24.05"` and `home.stateVersion = "24.05"` refer to the NixOS release the system was **first installed on**. These values **must NOT be changed** when upgrading the channel. Changing `stateVersion` causes data migration issues. Leave both at `"24.05"` permanently.

---

## 2. Part 1 — NixOS 25.11 Upgrade

### 2.1 Release Branch Verification (Context7 Confirmed)

| Component | Current URL | Target URL |
|---|---|---|
| nixpkgs | `github:nixos/nixpkgs/nixos-unstable` | `github:nixos/nixpkgs/nixos-25.11` |
| home-manager | `github:nix-community/home-manager` (master/unstable) | `github:nix-community/home-manager/release-25.11` |

**Reasoning verified via Context7 Home Manager docs:**
> "Home Manager follows NixOS release cycles … the stable branch for NixOS 25.11 is `release-25.11`."
> "Always use the Home Manager version that matches your NixOS version to avoid compatibility issues."

The `release-25.11` branch of home-manager tracks `nixos-25.11` in its own flake inputs and receives backported fixes but not new modules.

### 2.2 Updated flake.nix Inputs

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

  home-manager = {
    url = "github:nix-community/home-manager/release-25.11";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

No other changes to `flake.nix` structure are required.

### 2.3 hardware.opengl → hardware.graphics Rename (CRITICAL BREAKING CHANGE)

This rename was introduced in **NixOS 24.11** ("Vicuña"). The old `hardware.opengl` namespace is kept as a **compatibility alias** in 24.11 and 25.05, but is **expected to be removed by 25.11**.

| Old option (≤24.05) | New option (≥24.11) |
|---|---|
| `hardware.opengl.enable` | `hardware.graphics.enable` |
| `hardware.opengl.enable32Bit` (was `driSupport32Bit`) | `hardware.graphics.enable32Bit` |
| `hardware.opengl.extraPackages` | `hardware.graphics.extraPackages` |
| `hardware.opengl.extraPackages32` | `hardware.graphics.extraPackages32` |

**Action required:** The new `modules/gpu.nix` must use `hardware.graphics.*` exclusively. Any future use of `hardware.opengl.*` in this repository must be updated.

### 2.4 Known Breaking Changes Between Unstable → 25.11 Relevant to This Config

| Area | Change | Impact |
|---|---|---|
| `hardware.opengl` | Alias may be removed | Use `hardware.graphics` in all new code |
| GNOME | Updated to version 47 (in 24.11), confirmed in 25.05 | `gnome.nix` package names should still be valid |
| `services.xserver` | Still present, `services.displayManager.gdm` still valid | No change needed |
| Kernel default | Linux 6.12+ expected | `kvm-intel` module still valid |
| `nixpkgs.config.allowUnfree` | Unchanged | No action |

### 2.5 nixos-hardware Compatibility

`nixos-hardware` is not currently an input in this flake. It is **not required** for this change. If added later for laptop-specific tuning, it should be pinned to a commit that is compatible with `nixos-25.11`. No action required for this spec.

### 2.6 Post-Upgrade: Run nix flake update

After editing `flake.nix`, the implementer must run:
```bash
nix flake update
```
This regenerates `flake.lock` with new SHA256 hashes for the 25.11 channel pins. The `flake.lock` file will be modified as part of this change.

---

## 3. Part 2 — GPU Auto-Detection Module

### 3.1 Architecture Decision

**Selected Approach: Option C — Declarative `modules/gpu.nix` with `gpu.type` enum option.**

#### Why not Option A (system-level option)?
A single NixOS option without a dedicated module mixes concerns and forces GPU logic into host files that should stay clean.

#### Why not Option B (PCI auto-detection at build time)?
True hardware auto-detection (reading `/sys/bus/pci/...` or `lspci` outputs) at **Nix evaluation time** is fragile:
- Nix evaluation is a pure functional computation — it does not have access to hardware state.
- Workarounds using `builtins.readFile` on `/sys` paths break reproducibility and cross-compilation.
- Derivations that IFD (import-from-derivation) hardware scan tools add complexity and evaluation overhead.
- The resulting configuration cannot be built on a CI machine without the target hardware present.

#### Why Option C is correct for a declarative NixOS config:
- Fully reproducible — the config expresses intent, not discovered state.
- Portable — the same `modules/gpu.nix` works for all hosts; each host sets `gpu.type`.
- Safe fallback — `gpu.type = "none"` disables all GPU-specific config (bare metal, VMs).
- Easy to extend — adding `"hybrid-nvidia-intel"` or `"hybrid-nvidia-amd"` later is trivial.

### 3.2 GPU Type Enum Definition

| Value | Driver Stack | Use Case |
|---|---|---|
| `"none"` | Kernel modesetting (default) | VMs, CI, headless, unknown hardware |
| `"intel"` | `modesetting` + `intel-media-driver` | Intel iGPU Gen 4+ (Broadwell and newer) |
| `"amd"` | `amdgpu` kernel module + RADV | AMD discrete/integrated GPU (GCN 1.1+) |
| `"nvidia"` | Proprietary NVIDIA + `hardware.nvidia` | NVIDIA discrete GPU (Maxwell and newer) |

**Default must be `"none"`** so the config evaluates cleanly on any machine without requiring GPU-specific packages.

### 3.3 Full Annotated Content for `modules/gpu.nix`

```nix
# modules/gpu.nix
#
# Declarative GPU driver selection module.
# Set `gpu.type` in your host configuration to configure the appropriate
# driver stack. Supported values: "none", "intel", "amd", "nvidia".
#
# Usage example in hosts/default/configuration.nix:
#   gpu.type = "nvidia";

{ config, lib, pkgs, ... }:

let
  cfg = config.gpu;
in {

  # ── Option Declaration ──────────────────────────────────────────────────
  options.gpu = {
    type = lib.mkOption {
      type    = lib.types.enum [ "none" "intel" "amd" "nvidia" ];
      default = "none";
      description = ''
        Select the GPU driver stack to configure.
          "none"   — No GPU-specific configuration (VM/headless safe default).
          "intel"  — Intel integrated graphics (modesetting + VA-API media driver).
          "amd"    — AMD discrete/integrated GPU (amdgpu + RADV Vulkan).
          "nvidia" — NVIDIA proprietary driver (requires Turing architecture or newer
                     for the open kernel module; set open = false for older cards).
      '';
    };

    nvidia = {
      open = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = ''
          Use the open-source NVIDIA kernel module (nvidia-open).
          Supported on Turing (RTX 20xx) and newer architectures.
          Set to false for older cards (Pascal GTX 10xx and below).
        '';
      };
    };
  };

  # ── Configuration ───────────────────────────────────────────────────────
  config = lib.mkMerge [

    # ── Shared: enable hardware graphics for all non-none GPU types ────────
    (lib.mkIf (cfg.type != "none") {
      hardware.graphics = {
        enable      = true;
        enable32Bit = true;   # needed for Steam, Wine, 32-bit games
      };
    })

    # ── Intel ──────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "intel") {
      services.xserver.videoDrivers = [ "modesetting" ];

      hardware.graphics.extraPackages = with pkgs; [
        # Modern Intel iGPU VA-API (Broadwell / Gen 8 and newer)
        intel-media-driver
        # Older Intel iGPU VA-API fallback (Gen 4–9)
        intel-vaapi-driver
        # Intel compute runtime for OpenCL
        intel-compute-runtime
      ];
    })

    # ── AMD ────────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "amd") {
      # The amdgpu kernel module loads automatically for supported cards.
      # Setting videoDrivers to "amdgpu" makes the xorg intent explicit.
      services.xserver.videoDrivers = [ "amdgpu" ];

      hardware.graphics.extraPackages = with pkgs; [
        # AMDVLK: AMD's official open-source Vulkan driver (alternative to RADV)
        amdvlk
        # ROCm OpenCL runtime (for compute workloads)
        rocmPackages.clr.icd
      ];

      hardware.graphics.extraPackages32 = with pkgs; [
        driversi686Linux.amdvlk
      ];
    })

    # ── NVIDIA ─────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "nvidia") {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        # Kernel mode-setting: required for Wayland/GDM, prevents tearing
        modesetting.enable = true;

        # Open-source kernel module (nvidia-open, recommended for Turing+)
        # Set cfg.nvidia.open = false in host config for older GPUs
        open = cfg.nvidia.open;

        # NVIDIA power management (suspend/resume stability)
        powerManagement.enable = false;

        # Use the stable driver package (latest tested/stable)
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    })

  ]; # end mkMerge

}
```

### 3.4 Changes to `hosts/default/configuration.nix`

Add the import and set `gpu.type` to match the target machine's hardware.

```nix
imports = [
  ../../modules/system.nix
  ../../modules/gnome.nix
  ../../modules/users.nix
  ../../modules/gpu.nix      # ← ADD THIS LINE
];
```

And add one line to set GPU type (update the value to match the actual hardware):

```nix
# GPU driver selection — set to "intel", "amd", "nvidia", or "none"
gpu.type = "none";   # ← Change to match hardware: "nvidia", "amd", "intel"
```

**Important:** The default value in `gpu.nix` is `"none"`, so if the host does not set `gpu.type`, the config evaluates safely with no GPU-specific packages. The implementer should set this to the appropriate value for the `default` host (per `hardware-configuration.nix`, the CPU template appears to be Intel-based — `kvm-intel` — so a reasonable default for the default host is `"intel"` unless NVIDIA/AMD is present).

### 3.5 Changes to `modules/gnome.nix`

**No changes required.** GDM and GNOME work correctly with all three GPU branches. `hardware.graphics.enable = true` set by `gpu.nix` is sufficient for GDM to start on all drivers.

### 3.6 Changes to `modules/system.nix`

**No changes required.** System-level packages and services are GPU-independent.

### 3.7 Changes to `home/default.nix`

**No changes required.** Home Manager user configuration is GPU-independent.

---

## 4. Implementation Steps (for Phase 2 subagent)

1. **Edit `flake.nix`:**
   - Change `nixpkgs.url` from `…/nixos-unstable` to `…/nixos-25.11`
   - Change `home-manager.url` from `…/home-manager` to `…/home-manager/release-25.11`

2. **Create `modules/gpu.nix`:**
   - Use the exact content from Section 3.3 above

3. **Edit `hosts/default/configuration.nix`:**
   - Add `../../modules/gpu.nix` to the `imports` list
   - Add `gpu.type = "none";` (with comment) after the locale block

4. **Run `nix flake update`** to regenerate `flake.lock`

5. **Do NOT change** `system.stateVersion` or `home.stateVersion`

---

## 5. Files to Create / Modify

| Action | File |
|---|---|
| MODIFY | `flake.nix` |
| CREATE | `modules/gpu.nix` |
| MODIFY | `hosts/default/configuration.nix` |
| AUTO-UPDATED | `flake.lock` (via `nix flake update`) |

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `hardware.opengl` alias removed in 25.11, causing eval error | Medium | `gpu.nix` uses `hardware.graphics` exclusively; no legacy alias used |
| `nix flake update` downloads multi-GB channel closure | Low (CI) | Normal expectation; proceed |
| `gpu.type = "nvidia"` set without actual NVIDIA GPU breaks boot | Medium | Default is `"none"`; host must explicitly opt in |
| `hardware.nvidia.open = true` on a pre-Turing card causes black screen | Medium | `nvidia.open` sub-option lets host override to `false` |
| `nixos-25.11` branch not yet cut/stable at time of implementation | Low (as of March 2026) | Check `github:nixos/nixpkgs` for branch existence before running `nix flake update`; fall back to a pinned commit if needed |
| Package name changes in 25.11 for `amdvlk`, `intel-media-driver`, etc. | Low | These are well-established packages with stable names; confirmed present in nixos-unstable as of spec date |
| `rocmPackages.clr.icd` evaluation fails on non-AMD builds | Low | Wrapped in `lib.mkIf (cfg.type == "amd")` — only evaluated when AMD is selected |
| `home.stateVersion` mismatch warning | None if unchanged | Keep at `"24.05"` |

---

## 7. Research Sources

1. **NixOS Manual (unstable)** — `hardware.graphics.*` options, Intel/NVIDIA/AMD driver configuration examples — https://nixos.org/manual/nixos/unstable/
2. **NixOS Wiki — NVIDIA** — `hardware.nvidia.open`, `modesetting.enable`, open module Turing requirement — https://wiki.nixos.org/wiki/NVIDIA
3. **NixOS Wiki — AMD GPU** — `hardware.graphics` rename from `hardware.opengl`, `amdvlk`, `rocmPackages.clr.icd` — https://wiki.nixos.org/wiki/AMD_GPU
4. **NixOS Wiki — Intel Graphics** — `modesetting` driver recommendation, `intel-media-driver` vs `intel-vaapi-driver` — https://wiki.nixos.org/wiki/Intel_Graphics
5. **Home Manager README / MAINTAINING.md** (Context7 — `/nix-community/home-manager`) — `release-25.11` branch naming, `home.stateVersion` guidance, `nixpkgs.follows` pattern
6. **NixOS Release Notes 24.11 / 25.05** (Context7 — `/websites/nixos_manual_nixos_unstable`) — `hardware.opengl` → `hardware.graphics` rename introduced in 24.11; compatibility alias status in 25.05/25.11

---

## 8. Validation Checklist (for Phase 3 Review subagent)

- [ ] `nix flake check` passes with updated inputs
- [ ] `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf` returns `"string"` (derivation path)
- [ ] `gpu.type` option accepts all four enum values without error
- [ ] `gpu.type = "none"` produces no GPU packages in the closure
- [ ] `hardware.graphics` (not `hardware.opengl`) is used in `gpu.nix`
- [ ] `system.stateVersion` remains `"24.05"`
- [ ] `home.stateVersion` remains `"24.05"`
- [ ] `flake.lock` is updated (new SHA256s for 25.11)
- [ ] No `hardware.opengl` references anywhere in the repository
