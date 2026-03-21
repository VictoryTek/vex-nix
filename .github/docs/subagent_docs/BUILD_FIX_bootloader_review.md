# BUILD_FIX: Bootloader Module Deletion — Review

**Date:** 2026-03-21  
**Reviewer:** NixOS Review Agent  
**Verdict:** ❌ NEEDS_REFINEMENT

---

## Changes Under Review

| # | Change | File |
|---|--------|------|
| 1 | DELETED `modules/bootloader.nix` | (file removed) |
| 2 | Removed `../../modules/bootloader.nix` import | `hosts/default/configuration.nix` |
| 3 | Replaced `vexos.bootLoader.*` options with commented-out native `boot.loader.*` examples | `hosts/default/hardware-configuration.nix` |

---

## File Review

### `hosts/default/configuration.nix`

**Status: ✅ PASS**

- No import of `bootloader.nix` — confirmed absent
- No `vexos.bootLoader.*` references
- Valid Nix syntax and module structure
- All other module imports (`system.nix`, `gnome.nix`, `users.nix`, `gpu.nix`, etc.) are intact
- `gpu.type`, `kernel.type`, locale, networking, audio, packages, and `stateVersion` are all correctly configured

### `hosts/default/hardware-configuration.nix`

**Status: ✅ Valid Nix / ⚠️ Structurally incomplete for evaluation**

- Valid Nix syntax; no parse errors
- `vexos.bootLoader.*` options completely removed — confirmed
- Boot kernel module configuration, filesystem definitions, CPU configuration are present
- Bootloader section is correctly replaced with instructional comments:
  ```nix
  # UEFI (systemd-boot):
  #   boot.loader.systemd-boot.enable = true;
  #   boot.loader.efi.canTouchEfiVariables = true;
  #
  # Legacy BIOS/MBR (GRUB):
  #   boot.loader.grub.enable = true;
  #   boot.loader.grub.device = "/dev/sda";
  ```
- No active `boot.loader.*` options set anywhere in the module chain — **this causes build failure** (see below)

### `flake.nix`

**Status: ✅ PASS**

- No references to `bootloader.nix`
- `mkVexosSystem` helper is intact and correct
- All inputs and outputs are structurally sound

### `modules/system.nix`

**Status: ✅ PASS**

- No `boot.loader.*` or `vexos.bootLoader.*` options present
- No bootloader configuration of any kind — system relies entirely on hardware-configuration.nix to provide it

---

## Grep Verification

Searched all live `.nix` files on disk for `vexos\.bootLoader` and `bootloader\.nix`:

```
grep -r "vexos\.bootLoader\|bootloader\.nix" --include="*.nix" .
(no output — exit code 1 = no matches)
```

**Result: ✅ Zero remaining references in any live `.nix` file.**

> Note: The grep tool (VS Code indexed search) returned 7 apparent matches — these were from the
> git-indexed version of the already-deleted `modules/bootloader.nix`. The file is confirmed
> absent from the filesystem (`ls -la modules/` does not list it).

---

## Build Validation

### Command 1: `nix flake check 2>&1`

```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
error:
       … while checking flake output 'nixosConfigurations'
         at /var/home/nimda/Projects/vex-nix/flake.nix:111:5:

       … while checking the NixOS configuration 'nixosConfigurations.vexos'

       … while evaluating the option `system.build.toplevel':

       error:
       Failed assertions:
       - You must set the option 'boot.loader.grub.devices' or
         'boot.loader.grub.mirroredBoots' to make the system bootable.

Command exited with code 1
```

**❌ FAILED**

### Command 2: `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf 2>&1`

```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
error:
       … while calling the 'head' builtin

       … while evaluating the option `system.build.toplevel':

       error:
       Failed assertions:
       - You must set the option 'boot.loader.grub.devices' or
         'boot.loader.grub.mirroredBoots' to make the system bootable.

Command exited with code 1
```

**❌ FAILED**

---

## Root Cause Analysis

**Both commands fail with the same NixOS assertion:**

> `You must set the option 'boot.loader.grub.devices' or 'boot.loader.grub.mirroredBoots' to make the system bootable.`

**Cause:**

Prior to this change, `modules/bootloader.nix` provided the `boot.loader.*` configuration for the NixOS system (via its `vexos.bootLoader.*` custom option). When that module was deleted and its consumer options in `hardware-configuration.nix` were replaced with comments, the NixOS module system no longer has any active `boot.loader.*` settings.

NixOS defaults `boot.loader.grub.enable = true` (legacy default), which triggers an assertion requiring `boot.loader.grub.devices` or `boot.loader.grub.mirroredBoots` to be set. Since neither is set, evaluation fails.

**This is a CRITICAL regression**: the build was previously failing due to `bootloader.nix` issues, but the current state still fails — with a different error.

---

## Issues Found

| Severity | Issue | Location |
|----------|-------|----------|
| **CRITICAL** | `nix flake check` fails — no active `boot.loader.*` config in module chain | `hosts/default/hardware-configuration.nix` / `modules/system.nix` |
| INFO | Template `hardware-configuration.nix` correctly has commented bootloader options — by design | Expected |

---

## Required Fix

A default bootloader must be configured somewhere in the module chain so that:
1. `nix flake check` passes on the reference configuration
2. Users who clone the repo and override with their real hardware config get correct behavior
3. The configuration remains declarative and reproducible

**Recommended fix:** Add a default `systemd-boot` configuration (the modern NixOS standard for UEFI systems) to `modules/system.nix` using `lib.mkDefault`, which users can override in their hardware config:

```nix
# Default bootloader (systemd-boot for UEFI).
# Override in your hardware-configuration.nix for BIOS/MBR systems:
#   boot.loader.grub.enable = lib.mkForce true;
#   boot.loader.grub.device = "/dev/sda";
boot.loader.systemd-boot.enable = lib.mkDefault true;
boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
```

This is safe because:
- `lib.mkDefault` has low priority — any hardware-configuration.nix override wins
- `systemd-boot` is the correct default for modern x86_64 UEFI systems
- Users on BIOS/MBR can override with `lib.mkForce` or just set `boot.loader.grub.*` directly

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 80% | B |
| Best Practices | 85% | B+ |
| Functionality | 0% | F |
| Code Quality | 90% | A- |
| Security | 95% | A |
| Performance | 90% | A- |
| Consistency | 85% | B+ |
| Build Success | 0% | F |

**Overall Grade: F (53%)** — Build failure overrides all other scores.

---

## Summary

The deletionof `modules/bootloader.nix` and its import removal from `configuration.nix` are **correct and necessary**. The `hardware-configuration.nix` template is well-written with clear instructional comments.

However, removing the module left a gap: **no active bootloader is now configured anywhere in the NixOS module chain**, causing `nix flake check` and `nix eval` to fail with a NixOS assertion error.

**Verdict: NEEDS_REFINEMENT**

The fix is straightforward: add a `lib.mkDefault` systemd-boot configuration to `modules/system.nix`. This unblocks the build while remaining overridable by user hardware configs.
