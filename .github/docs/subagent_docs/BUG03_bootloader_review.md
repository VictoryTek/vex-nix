# BUG-03 Review — GRUB → systemd-boot Bootloader Fix

**Date:** 2026-03-19  
**Reviewer:** Static Review (Phase 3)  
**Spec:** `.github/docs/subagent_docs/BUG03_bootloader_spec.md`  
**Files Reviewed:**
- `hosts/default/configuration.nix`
- `modules/plymouth.nix`

---

## 1. Criterion-by-Criterion Findings

### ✅ 1. `boot.loader.systemd-boot.enable = true` present in `configuration.nix`

**PASS.** Present at line 50 of `hosts/default/configuration.nix`:

```nix
boot.loader.systemd-boot.enable = true;
```

Exactly as specified in spec Section 5.1.

---

### ✅ 2. `boot.loader.efi.canTouchEfiVariables = true` present in `configuration.nix`

**PASS.** Present at line 51:

```nix
boot.loader.efi.canTouchEfiVariables = true;
```

Exactly as specified in spec Section 5.1.

---

### ✅ 3. Old GRUB lines REMOVED from `configuration.nix`

**PASS.** Neither `boot.loader.grub.enable` nor `boot.loader.grub.device` appear as live configuration in `configuration.nix`. The only appearances are inside the BIOS fallback comment block (lines 47–48), which is the correct and intentional pattern.

---

### ✅ 4. `boot.loader.grub.timeoutStyle` REMOVED from `modules/plymouth.nix`

**PASS.** A full grep of `plymouth.nix` for `boot.loader.grub` returns zero matches. The GRUB-specific `timeoutStyle = "hidden"` line has been correctly removed.

---

### ✅ 5. `boot.loader.timeout = 0` PRESERVED in `modules/plymouth.nix`

**PASS.** The bootloader-agnostic timeout line is present and correct as the final statement in `plymouth.nix`:

```nix
boot.loader.timeout = 0;
```

---

### ✅ 6. No mutual-exclusion conflict — no residual `boot.loader.grub.*` live options

**PASS.** Neither modified file contains any live `boot.loader.grub.*` attribute assignments. The only GRUB references in the entire modified file set are inside `#`-prefixed comments in `configuration.nix`. There is no condition under which NixOS would activate GRUB from these files as-is.

---

### ✅ 7. BIOS fallback comment present in `configuration.nix`

**PASS.** Lines 44–49 of `configuration.nix` contain a well-constructed override guide:

```nix
# Bootloader (UEFI — systemd-boot)
# Requires an EFI System Partition mounted at /boot (vfat).
# For legacy BIOS/MBR hardware, override in hardware-configuration.nix:
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub.enable = true;
#   boot.loader.grub.device = "/dev/sdX";  # replace with your actual disk
```

This comment exceeds the spec's requirement in one respect: it provides concrete override code
(`boot.loader.systemd-boot.enable = false`, `grub.enable = true`, `grub.device = "/dev/sdX"`),
which is more actionable than the spec's suggestion to "override with `lib.mkForce` if needed."
This deviation is an improvement in user-facing documentation clarity.

---

### ✅ 8. No regressions in other settings

**PASS.** All non-bootloader configuration in `configuration.nix` is intact and unchanged:
- `imports` block (10 modules) — unchanged
- `gpu.type`, `kernel.type` — unchanged
- `networking.hostName`, `time.timeZone`, `i18n.*` — unchanged
- `services.pulseaudio`, `security.rtkit`, `services.pipewire` — unchanged
- `nix.settings.experimental-features`, `nixpkgs.config.allowUnfree` — unchanged
- `environment.systemPackages` — unchanged
- `system.stateVersion` — unchanged

All Plymouth-related settings in `plymouth.nix` are intact:
- `boot.plymouth.enable`, `boot.plymouth.theme` — unchanged
- `boot.kernelParams` — unchanged
- `boot.consoleLogLevel`, `boot.initrd.verbose` — unchanged
- `boot.initrd.kernelModules` (full `lib.optionals` chain) — unchanged
- `boot.initrd.systemd.enable` — unchanged
- `boot.loader.timeout` — preserved

---

### ✅ 9. Nix syntax validity

**PASS — both files are syntactically valid.**

**`hosts/default/configuration.nix`:**
- Top-level function signature: `{ config, pkgs, inputs, ... }:` — valid
- Outer attrset: opens `{` at line 3, closes `}` at line 87 — balanced
- `imports = [ ... ];` list properly terminated
- All `option.path = value;` statements properly semicoloned
- `i18n.extraLocaleSettings = { ... };` nested attrset properly closed
- `services.pipewire = { ... };` nested attrset properly closed
- `environment.systemPackages = with pkgs; [ ... ];` list properly terminated
- No syntax issues detected

**`modules/plymouth.nix`:**
- Function signature: `{ config, lib, ... }:` — valid
- Outer attrset: opens `{` at line 3, closes `}` at line 49 — balanced
- `boot.plymouth = { ... };` — properly closed
- `boot.kernelParams = [ ... ];` — properly terminated
- `boot.initrd.kernelModules = lib.optionals (...) [ ... ] ++ lib.optionals (...) [ ... ] ++ [...];` — multi-line `++` chain properly terminated with `;`
- All scalar attribute assignments end with `;`
- No unmatched braces or brackets detected

---

### ⚠️ 10. Spec compliance — comment update NOT fully implemented

**PARTIAL.** This is the single deviation from the specification.

**Spec Section 5.2** explicitly required updating the comment on `boot.loader.timeout`:

```nix
# Spec required:
# Hide the bootloader menu on boot (press Space during POST to interrupt).
# Works for both systemd-boot and GRUB.
boot.loader.timeout = 0;
```

**Actual implementation:**

```nix
# Hide boot menu on boot (press Shift during POST to interrupt).
boot.loader.timeout = 0;
```

Two discrepancies:
1. The interrupt key is still documented as `Shift` — this was correct for GRUB but is **incorrect for systemd-boot**, which uses `Space` (or any key, per systemd-boot documentation). This is a factually inaccurate comment after the bootloader change.
2. The second spec-required comment line (`# Works for both systemd-boot and GRUB.`) was not added.

**Severity: NON-CRITICAL / RECOMMENDED FIX.** This is a documentation accuracy issue only. It has zero effect on runtime behavior or NixOS evaluation. The `timeout = 0` option is correctly present and functional. However, leaving "press Shift" in the comment after switching to systemd-boot is a misleading developer note — Shift has no special meaning to systemd-boot.

---

## 2. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 92% | A- |
| Best Practices | 98% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 98% | A+ |
| Performance | 100% | A+ |
| Consistency | 97% | A |
| Build Success | 98% | A+ |

> **Build Success** is assessed via static analysis only per the review brief (no build run required).  
> The `nix flake check` output in the terminal context confirms the configuration evaluates and passes all checks as of the last run.

**Overall Grade: A (97%)**

---

## 3. Summary of Findings

| # | Criterion | Status | Severity |
|---|-----------|--------|----------|
| 1 | `systemd-boot.enable = true` present | ✅ PASS | — |
| 2 | `efi.canTouchEfiVariables = true` present | ✅ PASS | — |
| 3 | GRUB enable/device lines removed | ✅ PASS | — |
| 4 | `grub.timeoutStyle` removed from plymouth.nix | ✅ PASS | — |
| 5 | `boot.loader.timeout = 0` preserved | ✅ PASS | — |
| 6 | No mutual exclusion conflict | ✅ PASS | — |
| 7 | BIOS fallback comment present | ✅ PASS | — |
| 8 | No regressions in other settings | ✅ PASS | — |
| 9 | Nix syntax validity | ✅ PASS | — |
| 10 | Comment not updated (still says "Shift", missing second line) | ⚠️ PARTIAL | NON-CRITICAL |

---

## 4. Verdict

**PASS**

All functional requirements of BUG-03 are correctly implemented. The bootloader has been migrated from BIOS GRUB to UEFI systemd-boot. The GRUB-specific `timeoutStyle` dead option has been removed from plymouth.nix. The bootloader-agnostic `boot.loader.timeout = 0` is preserved. No regressions were introduced. Both files are syntactically valid Nix.

One non-critical issue exists: the comment on `boot.loader.timeout` in `modules/plymouth.nix` was not updated per spec — it still references "Shift" (a GRUB behavior) instead of "Space" (systemd-boot), and is missing the second line the spec required. This should be corrected in a follow-up commit to maintain documentation accuracy.

---

## 5. Recommended Follow-Up (Non-Blocking)

**File:** `modules/plymouth.nix`  
**Line:** The `boot.loader.timeout = 0;` comment block

Change:
```nix
  # Hide boot menu on boot (press Shift during POST to interrupt).
  boot.loader.timeout = 0;
```

To:
```nix
  # Hide the bootloader menu on boot (press Space during POST to interrupt).
  # Works for both systemd-boot and GRUB.
  boot.loader.timeout = 0;
```

This is a documentation-only fix and does not require a full review cycle.
