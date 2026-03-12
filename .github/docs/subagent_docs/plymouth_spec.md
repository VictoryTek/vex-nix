# Plymouth Boot Splash — Implementation Specification

**Feature**: Silent graphical boot splash screen using Plymouth  
**Project**: VexOS NixOS Flake Configuration  
**Nixpkgs Channel**: `nixos-25.11`  
**Date**: 2026-03-11  
**Status**: DRAFT — Awaiting Implementation

---

## 1. Current Configuration Analysis

### 1.1 Bootloader

- **Type**: GRUB (legacy BIOS/MBR)
- **Configuration** (`hosts/default/configuration.nix`):
  ```nix
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  ```
- **No EFI**: The hardware template uses a `vfat /boot` partition but GRUB is configured for MBR (`device = "/dev/sda"`), confirming legacy BIOS boot.
- **GRUB timeout**: Not explicitly set → NixOS default (typically 5 seconds showing the menu).
- **No `boot.loader.timeout`** currently set.

### 1.2 GPU Configuration

- **Current host default**: `gpu.type = "none"` (VM-safe default in `hosts/default/configuration.nix`)
- **Supported types** (from `modules/gpu.nix`): `"none"`, `"intel"`, `"amd"`, `"nvidia"`
- **NVIDIA modesetting**: Already configured when `gpu.type = "nvidia"` → `hardware.nvidia.modesetting.enable = true`
- **No KMS initrd modules** currently added for any GPU type.

### 1.3 Kernel Parameters

- **Currently set**: None beyond NixOS defaults. No `quiet`, `splash`, or logging suppression parameters.
- **`boot.initrd.verbose`**: Not set (defaults to `true` — shows lots of boot messages).
- **`boot.consoleLogLevel`**: Not set (defaults to 4 = `WARNING`).

### 1.4 Display Manager

- **GDM with Wayland**: `services.displayManager.gdm.enable = true; services.displayManager.gdm.wayland = true;` (in `modules/gnome.nix`)
- GDM automatically signals Plymouth to quit when it starts — no special configuration needed for the handoff.

### 1.5 Existing Plymouth Configuration

- **None**. Plymouth is not currently enabled anywhere in the configuration.

### 1.6 Theme/Package Infrastructure

- No existing Plymouth theme packages.
- `pkgs.breeze-plymouth` and `pkgs.adi1090x-plymouth-themes` are available in nixpkgs 25.11.

---

## 2. Problem Definition

The system currently shows a verbose boot sequence with:

- Raw kernel log messages scrolling across the screen
- GRUB menu appearing for 5 seconds on every boot
- No graphical boot animation
- Abrupt transition from black screen to GDM login

The goal is to implement a **clean, silent, graphical boot experience** using Plymouth that:

1. Shows a polished animated boot splash from GRUB handoff to GDM
2. Suppresses all kernel/udev log messages during normal boot
3. Hides the GRUB menu by default (still accessible via `Shift` key)
4. Loads the GPU's KMS driver early in initrd for hardware-accelerated Plymouth rendering
5. Transitions cleanly into GDM

---

## 3. Research Findings

### 3.1 Sources Consulted

1. **NixOS Wiki — Plymouth** (`https://wiki.nixos.org/wiki/Plymouth`) — Primary reference for options and kernel params
2. **NixOS Wiki — Plymouth (EN)** (`https://wiki.nixos.org/wiki/Plymouth/en`) — English canonical source; confirms `boot.plymouth.*` options
3. **NixOS Wiki — Graphics / Early KMS** (`https://wiki.nixos.org/wiki/Graphics`) — `boot.initrd.kernelModules` for GPU-specific early KMS
4. **NixOS Wiki — NVIDIA** (`https://wiki.nixos.org/wiki/NVIDIA`) — NVIDIA-specific initrd KMS modules
5. **NixOS Manual (unstable)** — `boot.plymouth.tpm2-totp`, `boot.initrd.kernelModules` documentation
6. **NixOS Wiki — Linux Kernel** (`https://wiki.nixos.org/wiki/Linux_kernel`) — `boot.kernelParams` reference
7. **NixOS Wiki — GRUB** (`https://wiki.nixos.org/wiki/Grub`) — GRUB timeout and text mode configuration

### 3.2 Required NixOS Options

| Option | Value | Purpose |
|--------|-------|---------|
| `boot.plymouth.enable` | `true` | Enables Plymouth in initrd |
| `boot.plymouth.theme` | `"breeze"` | Selects the Breeze splash theme |
| `boot.plymouth.themePackages` | `[ pkgs.breeze-plymouth ]` | Provides the theme files |
| `boot.consoleLogLevel` | `3` | Suppresses kernel log to errors only |
| `boot.initrd.verbose` | `false` | Suppresses initrd script verbose output |
| `boot.kernelParams` | see §3.3 | Silent boot parameters |
| `boot.loader.timeout` | `0` | Hides GRUB menu, boots default immediately |
| `boot.initrd.kernelModules` | GPU-dependent | Early KMS for Plymouth hardware rendering |

### 3.3 Kernel Parameters for Silent Boot

Based on NixOS Wiki (Plymouth page), the following kernel parameters are needed:

```
quiet                        — Suppresses non-critical kernel messages
splash                       — Signals kernel/systemd to activate Plymouth
boot.shell_on_fail           — On boot failure: drop to shell instead of hanging
udev.log_priority=3          — Suppresses udev log to error level
rd.systemd.show_status=auto  — Only show systemd status on failure
```

### 3.4 GRUB Interaction

- Plymouth works with legacy GRUB. No GRUB plugin for Plymouth is needed.
- GRUB hands off to the kernel, which starts Plymouth in the initrd stage.
- `boot.loader.timeout = 0` in NixOS maps to `timeout 0` in grub.cfg → boots default entry immediately.
- User can still hold **`Shift`** during BIOS POST to force GRUB menu display (standard GRUB behavior).
- The GRUB splash image (NixOS default background) is visible for essentially zero time when timeout=0.

### 3.5 Available Themes in nixpkgs 25.11

| Theme Name | Package | Notes |
|------------|---------|-------|
| `spinner` | Built-in (no package) | Minimal animated spinner; no extra pkg needed |
| `fade-throbber` | Built-in | Fading animation |
| `bgrt` | Built-in | Uses UEFI BGRT OEM logo — **NOT suitable**: this system uses legacy BIOS (no BGRT table) |
| `breeze` | `pkgs.breeze-plymouth` | KDE Breeze-style; very polished; works on any DE |
| `rings` | `pkgs.adi1090x-plymouth-themes` (override needed) | Popular community theme; complex override |
| `loader` | `pkgs.adi1090x-plymouth-themes` (override needed) | Modern; complex override |

**Chosen theme: `breeze` from `pkgs.breeze-plymouth`**

Rationale:
- Clean, minimal, modern animated splash
- No complex `override` syntax required (unlike `adi1090x-plymouth-themes`)
- Available as a first-class nixpkgs package in 25.11
- Works identically on GNOME and KDE
- Compatible with both framebuffer and KMS (hardware) rendering
- Well-tested in the NixOS community

### 3.6 GPU / KMS Considerations

Plymouth needs the GPU's **Kernel Mode Setting (KMS)** driver to load **in the initrd** (before Plymouth starts) for hardware-accelerated rendering. Without early KMS, Plymouth falls back to the generic framebuffer/VESA mode, which may cause a brief flash or degraded animation.

| `gpu.type` | Initrd KMS Module(s) to Add |
|------------|----------------------------|
| `"none"` | None (Plymouth uses VESA/framebuffer — functional but basic) |
| `"intel"` | `"i915"` |
| `"amd"` | `"amdgpu"` |
| `"nvidia"` | `"nvidia"`, `"nvidia_modeset"`, `"nvidia_uvm"`, `"nvidia_drm"` |

**Note on NVIDIA**: `hardware.nvidia.modesetting.enable = true` (already set in `modules/gpu.nix`) adds `nvidia-drm.modeset=1` to kernel params automatically. The initrd modules are still required for Plymouth to activate KMS early enough.

### 3.7 Plymouth + GDM Handoff

GDM is Plymouth-aware and automatically sends a `quit` signal to Plymouth when GDM is ready to display. The `services.displayManager.gdm.enable = true` setting (already in `modules/gnome.nix`) handles this without any additional configuration.

The Plymouth → GDM transition is:
1. Plymouth renders splash during initrd + systemd init stages
2. GDM service starts
3. GDM sends `plymouth quit --retain-splash` (waits for GDM to show first frame)
4. Plymouth fades out / GDM login screen fades in

---

## 4. Proposed Solution Architecture

### 4.1 New File: `modules/plymouth.nix`

Create a dedicated, self-contained Plymouth module following the existing modular pattern of this project. It will:

- Enable Plymouth with the `breeze` theme
- Configure all silent-boot kernel parameters
- Set GRUB timeout to 0
- Conditionally add GPU-specific KMS initrd modules by reading `config.gpu.type`

This module has a **read-only dependency** on `config.gpu.type` (defined in `modules/gpu.nix`). There is no circular dependency because `plymouth.nix` only **reads** the option that `gpu.nix` **defines and sets**.

### 4.2 Modified File: `hosts/default/configuration.nix`

Add `../../modules/plymouth.nix` to the imports list.

No other files need modification.

---

## 5. Exact NixOS Configuration

### 5.1 `modules/plymouth.nix` (create new)

```nix
# modules/plymouth.nix
#
# Plymouth graphical boot splash module.
#
# Enables a clean, silent boot experience with an animated Plymouth splash.
# Automatically loads the appropriate GPU KMS kernel module in the initrd
# based on the gpu.type option set in the host configuration.
#
# Requires: modules/gpu.nix must be imported before this module so that
#           config.gpu.type is available.

{ config, lib, pkgs, ... }:

{
  boot.plymouth = {
    enable = true;
    theme = "breeze";
    themePackages = [ pkgs.breeze-plymouth ];
  };

  # Silent boot: suppress kernel and udev messages during normal boot.
  # boot.shell_on_fail ensures a recovery shell is available on errors.
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "udev.log_priority=3"
    "rd.systemd.show_status=auto"
  ];

  # GRUB: boot the default entry immediately.
  # Hold Shift at BIOS POST to access the GRUB menu when needed.
  boot.loader.timeout = 0;

  # Early KMS: load the GPU driver module in the initrd so Plymouth can use
  # hardware-accelerated rendering instead of the generic VESA framebuffer.
  # Uses lib.optional / lib.optionals to evaluate to an empty list when the
  # condition is false — safe for gpu.type = "none".
  boot.initrd.kernelModules =
    (lib.optional  (config.gpu.type == "intel")  "i915")
    ++ (lib.optional  (config.gpu.type == "amd")    "amdgpu")
    ++ (lib.optionals (config.gpu.type == "nvidia") [
         "nvidia"
         "nvidia_modeset"
         "nvidia_uvm"
         "nvidia_drm"
       ]);
}
```

### 5.2 `hosts/default/configuration.nix` (modify imports)

Add `../../modules/plymouth.nix` to the imports list:

```nix
imports = [
  ../../modules/system.nix
  ../../modules/gnome.nix
  ../../modules/users.nix
  ../../modules/gpu.nix
  ../../modules/gaming.nix
  ../../modules/asus.nix
  ../../modules/flatpak.nix
  ../../modules/plymouth.nix   # ← ADD THIS LINE
];
```

---

## 6. All Kernel Parameters — Before and After

### Before (current)

None explicitly set. NixOS defaults apply (verbose boot, all messages visible).

### After (new `modules/plymouth.nix`)

| Parameter | Source |
|-----------|--------|
| `quiet` | Plymouth silent boot |
| `splash` | Activates Plymouth splash |
| `boot.shell_on_fail` | Error recovery (drop to shell on failure) |
| `udev.log_priority=3` | Suppress udev messages below error level |
| `rd.systemd.show_status=auto` | Show systemd status only on failure |

Plus NixOS options (not kernel params):

| Option | Value |
|--------|-------|
| `boot.consoleLogLevel` | `3` (errors only) |
| `boot.initrd.verbose` | `false` |
| `boot.loader.timeout` | `0` |

---

## 7. Theme Choice and Rationale

**Selected theme**: `breeze` (package: `pkgs.breeze-plymouth`)

**Rejected options**:

- `bgrt` — Requires UEFI BGRT firmware table. This system uses **legacy BIOS**, meaning no BGRT is available. Using it would cause Plymouth to fall back to text mode silently.
- `spinner` — Works but visually minimal; no extra package. Suitable as a fallback but `breeze` is more polished.
- `adi1090x-plymouth-themes` (`rings`, `loader`, etc.) — Visually excellent but requires an `override` expression with `selected_themes = [ "name" ]`, adding complexity. Better reserved for user customization.
- `fade-throbber` — Built-in but less polished than `breeze`.

**Why `breeze`**:
- Single, clean package reference (`pkgs.breeze-plymouth`)
- Renders a smooth animated boot logo
- Theme name exactly matches the directory name (`"breeze"`) — no mismatch risk
- Actively maintained in nixpkgs as part of the KDE ecosystem
- Hardware-renderer when KMS is active, graceful fallback to framebuffer

---

## 8. GPU / KMS Analysis and Steps

### 8.1 `gpu.type = "none"` (current CI default)

- No KMS modules added to initrd
- Plymouth operates in VESA/framebuffer mode
- The `breeze` theme renders in software mode — animation is visible but may not be pixel-perfect
- **No risk**: This is the safe default for VMs and headless systems

### 8.2 `gpu.type = "intel"`

- Add `"i915"` to `boot.initrd.kernelModules`
- Intel KMS activates before Plymouth — full hardware rendering
- `intel-media-driver` (already in gpu.nix extraPackages) handles post-boot VA-API; no interaction with Plymouth

### 8.3 `gpu.type = "amd"`

- Add `"amdgpu"` to `boot.initrd.kernelModules`
- AMD KMS activates before Plymouth — full hardware rendering
- `services.xserver.videoDrivers = [ "amdgpu" ]` (already in gpu.nix) handles Xorg; no interaction with Plymouth

### 8.4 `gpu.type = "nvidia"`

- Add `"nvidia"`, `"nvidia_modeset"`, `"nvidia_uvm"`, `"nvidia_drm"` to `boot.initrd.kernelModules`
- `hardware.nvidia.modesetting.enable = true` (already in gpu.nix) sets `nvidia-drm.modeset=1` kernel param automatically
- All four modules are required for NVIDIA KMS to be active in the initrd stage
- Known NVIDIA Plymouth risk: see §9.2

---

## 9. Risks and Mitigations

### 9.1 Black Screen Instead of Splash (All GPUs)

**Risk**: Plymouth fails to initialize graphics and produces a black screen.  
**Cause**: Missing KMS driver in initrd, or `quiet splash` not correctly passed by GRUB.  
**Mitigation**:
- `boot.shell_on_fail` in kernelParams — provides rescue shell on failure
- The `breeze` theme gracefully degrades to text mode if GPU rendering fails
- To debug: temporarily remove `quiet` and `splash` from `kernelParams` to see raw boot messages

### 9.2 NVIDIA + Plymouth Black Screen / Flickering

**Risk**: NVIDIA proprietary driver KMS in initrd can cause black screens at Plymouth → GDM transition.  
**Cause**: The `nvidia_drm` module may not initialize cleanly in initrd on all systems.  
**Mitigation**:
- `hardware.nvidia.modesetting.enable = true` (already set in gpu.nix) is required and present
- If black screen occurs with NVIDIA: remove `"nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"` from initrd modules (Plymouth will use framebuffer fallback)
- The NixOS Wiki notes this as a known NVIDIA limitation

### 9.3 GRUB Timeout = 0 Lock-out

**Risk**: User accidentally loses the ability to select a previous NixOS generation.  
**Mitigation**:
- With GRUB and `timeout = 0`, holding **Shift** during BIOS POST still interrupts auto-boot in many BIOS/firmware implementations
- If `Shift` does not work on a specific machine, set `boot.loader.timeout = 1` or `boot.loader.timeout = 3` in the **host's local `configuration.nix`** (which overrides the module default)
- `nixos-rebuild boot` (not switch) can safely test configuration before committing

### 9.4 Plymouth → GDM Transition Flicker

**Risk**: Brief black screen between Plymouth quitting and GDM first frame.  
**Cause**: Normal timing gap on slower systems.  
**Mitigation**: This is expected behavior and not addressable without systemd-stage-2 integration. GDM handles the handoff automatically. On systems with KMS active, the transition is typically instant.

### 9.5 CI / `nix flake check` with `gpu.type = "none"`

**Risk**: The CI configuration uses `gpu.type = "none"` — Plymouth will attempt to add zero KMS modules (empty list concatenation). `lib.optional false x = []` evaluates cleanly; no evaluation error.  
**Mitigation**: This is handled correctly by the `lib.optional` / `lib.optionals` expressions. CI evaluation will pass without GPU modules, which is the correct behavior for the template hardware config.

### 9.6 `udev.log_priority` vs `udev.log_level`

**Risk**: Some documentation references `udev.log_level=3` (older) while current NixOS Wiki uses `udev.log_priority=3`.  
**Decision**: Use `udev.log_priority=3` as documented in the current NixOS Wiki (Plymouth page). This is the systemd ≥247 parameter name. NixOS 25.11 uses a recent systemd version where this is correct.

---

## 10. Implementation Steps (Ordered)

1. **Create `modules/plymouth.nix`** with the exact content in §5.1
2. **Modify `hosts/default/configuration.nix`** to add `../../modules/plymouth.nix` to the imports list (§5.2)
3. **Verify no conflicts**: Confirm no existing `boot.kernelParams`, `boot.initrd.kernelModules`, `boot.loader.timeout`, or `boot.plymouth.*` settings exist in other modules that would conflict
4. **Run preflight** (`scripts/preflight.sh`) to validate `nix flake check` passes

### Conflict Check Required

Before finalizing, the implementation subagent must verify these options are not set elsewhere:
- `boot.kernelParams` — not set in `system.nix`, `gnome.nix`, `gpu.nix`, `gaming.nix`, `asus.nix` (except possibly `gaming.nix` for performance params)
- `boot.loader.timeout` — not set anywhere currently
- `boot.plymouth.*` — not set anywhere currently

If `boot.kernelParams` is set in `gaming.nix` or `asus.nix`, use `lib.mkAfter`/`boot.kernelParams = [ ... ] ++ [ existing ]` or rely on NixOS list merging (multiple modules setting `boot.kernelParams` as lists is fine — NixOS merges them automatically).

---

## 11. Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `modules/plymouth.nix` | **CREATE** | New Plymouth module with full configuration |
| `hosts/default/configuration.nix` | **MODIFY** | Add `../../modules/plymouth.nix` to imports |

---

## 12. Spec Validation Checklist

- [x] Bootloader type confirmed: GRUB legacy BIOS/MBR
- [x] `bgrt` theme excluded (requires UEFI BGRT, incompatible with legacy BIOS)
- [x] `breeze` theme confirmed available in nixpkgs 25.11 via `pkgs.breeze-plymouth`
- [x] KMS modules verified per GPU type (NixOS Wiki: Graphics)
- [x] NVIDIA modesetting already handled in `gpu.nix` — no duplication needed
- [x] GDM Plymouth handoff is automatic — no extra config needed
- [x] `udev.log_priority=3` confirmed (not deprecated `udev.log_level`)
- [x] `lib.optional` / `lib.optionals` pattern safe for `gpu.type = "none"` (CI default)
- [x] `boot.loader.timeout = 0` documented behavior confirmed for GRUB
- [x] No new flake inputs required — `pkgs.breeze-plymouth` is in nixpkgs 25.11
