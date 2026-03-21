# BUILD_FIX Bootloader — Final Re-Review

**Date:** 2026-03-21  
**Reviewer:** Re-Review Subagent  
**Verdict:** NEEDS_FURTHER_REFINEMENT

---

## Summary

Three of the four specified changes were implemented correctly and the build
passes. However, one critical item from the specification was **not completed**:
`modules/bootloader.nix` still exists on disk as an orphaned file. Because the
spec explicitly required deletion, and because the orphaned file contains live
custom option declarations (`options.vexos.bootLoader.*`) that could cause
confusion or accidental re-use, this review cannot approve the work as-is.

---

## Findings by Change

### 1. `modules/bootloader.nix` — Expected: DELETED — Actual: **STILL EXISTS** ❌

The file is present at `/home/nimda/Projects/vex-nix/modules/bootloader.nix`
(74 lines, full implementation). It is not imported by any active configuration,
but it still exists on disk.

A grep for `vexos\.bootLoader|bootloader\.nix` across all `.nix` files returned
**7 matches — all inside `modules/bootloader.nix` itself**:

| Line | Content |
|------|---------|
| 1 | `# modules/bootloader.nix` (header comment) |
| 7 | `#   vexos.bootLoader.type = "grub";` |
| 8 | `#   vexos.bootLoader.grub.device = "/dev/sda";` |
| 13 | `cfg = config.vexos.bootLoader;` |
| 17 | `options.vexos.bootLoader = {` |
| 50 | `message = "vexos.bootLoader.grub.device must be set..."` |
| 51 | (continuation of L50) |

No other `.nix` file references `vexos.bootLoader` or imports `bootloader.nix`.
The file is fully orphaned. **Required action: delete `modules/bootloader.nix`.**

---

### 2. `hosts/default/configuration.nix` — Expected: import removed — Actual: ✅ CORRECT

`bootloader.nix` is absent from the `imports` list. Current imports:

```nix
imports = [
  ../../modules/system.nix
  ../../modules/gnome.nix
  ../../modules/users.nix
  ../../modules/gpu.nix
  ../../modules/gaming.nix
  ../../modules/asus.nix
  ../../modules/flatpak.nix
  ../../modules/plymouth.nix
  ../../modules/kernel.nix
];
```

No `bootloader.nix`. No `vexos.bootLoader` references anywhere in the file.

---

### 3. `hosts/default/hardware-configuration.nix` — Expected: comments only — Actual: ✅ CORRECT

The bootloader section contains **only comments**. No active assignments:

```nix
# ── Bootloader ────────────────────────────────────────────────────────────
# Set your bootloader here. Examples:
#
# UEFI (systemd-boot):
#   boot.loader.systemd-boot.enable = true;
#   boot.loader.efi.canTouchEfiVariables = true;
#
# Legacy BIOS/MBR (GRUB):
#   boot.loader.grub.enable = true;
#   boot.loader.grub.device = "/dev/sda";  # verify with `lsblk`
```

No active `boot.loader.*` assignments. No `vexos.bootLoader.*` references.
Pattern is correct: hardware configs override the system.nix default via plain
assignment when needed (no `lib.mkForce` required).

---

### 4. `modules/system.nix` — Expected: `lib.mkDefault` bootloader fallback — Actual: ✅ CORRECT

```nix
# ── Bootloader defaults ──────────────────────────────────────────────────────
# Fallback bootloader for UEFI systems. Uses lib.mkDefault so any
# hardware-configuration.nix can override with a plain assignment
# (e.g. boot.loader.grub.enable = true) without needing lib.mkForce.
boot.loader.systemd-boot.enable      = lib.mkDefault true;
boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
```

- `lib.mkDefault` — ✅ confirmed (not `lib.mkForce`, not plain assignment)
- Both options are covered: `systemd-boot.enable` and `efi.canTouchEfiVariables`
- Comment accurately describes override behaviour

---

## Build Validation

### `nix flake check 2>&1`

```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
warning: Using 'builtins.derivation' to create a derivation named 'options.json'
  that references the store path '...arylzmnn080w2i8hi0x45pgkd3mmp53r-source'
  without a proper context. The resulting derivation will not have a correct
  store reference, so this is unreliable and may stop working in the future.
EXIT:0
```

**Result: PASSED** — exit code 0, no errors. Warnings are pre-existing and
unrelated to the bootloader changes.

### `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf 2>&1`

```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
warning: Using 'builtins.derivation' to create a derivation named 'options.json'
  that references the store path '...arylzmnn080w2i8hi0x45pgkd3mmp53r-source'
  without a proper context. The resulting derivation will not have a correct
  store reference, so this is unreliable and may stop working in the future.
"set"
EXIT:0
```

**Result: PASSED** — evaluates to `"set"`, exit code 0.

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 75% | C |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 90% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 85% | B |
| Build Success | 100% | A |

**Overall Grade: B+ (92.5%)**

Spec compliance is degraded solely by the undeleted `modules/bootloader.nix`.
All other metrics are high. The overall code quality and build health are
excellent — this is one targeted file deletion away from APPROVED.

---

## Required Action

| Priority | Action |
|----------|--------|
| CRITICAL | Delete `modules/bootloader.nix` |

No other changes are required. Once this file is removed:
- The workspace will be free of all `vexos.bootLoader.*` references
- All orphaned option declarations will be gone
- The spec will be fully implemented
- Re-review may be skipped; the build already passes without this file

---

## Conclusion

**NEEDS_FURTHER_REFINEMENT**

The implementation is functionally correct and the build passes. The sole
remaining gap is that `modules/bootloader.nix` was not deleted. Delete the file
and the work is complete.
