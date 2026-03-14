# VexOS Kernel Switching — Review & Quality Assurance

**Feature:** Multi-kernel switching with interactive selection
**Date:** 2026-03-13
**Reviewer:** QA Subagent (Phase 3)
**Status:** PASS

---

## 1. Summary of Findings

The kernel switching implementation is well-executed and closely follows the specification. All seven kernel variants are correctly mapped, the Nix module follows established project conventions, and the justfile provides a functional interactive menu with proper error handling. No critical issues were found. Two recommended improvements and two minor suggestions are noted below.

### Files Reviewed
- `modules/kernel.nix` — Expanded kernel selection module (primary deliverable)
- `justfile` — Interactive kernel selector menu and helper recipes
- `hosts/default/configuration.nix` — Host config with kernel.type declaration
- `flake.nix` — Flake inputs and overlay application (context)
- `modules/gpu.nix` — Reference module for pattern consistency
- `modules/system.nix`, `modules/gaming.nix`, `modules/asus.nix`, `modules/gnome.nix`, `modules/plymouth.nix`, `modules/users.nix`, `modules/flatpak.nix` — Style consistency references
- `home/default.nix`, `scripts/deploy.sh`, `scripts/preflight.sh`, `scripts/install.sh` — Context files

---

## 2. Detailed Review

### 2.1 modules/kernel.nix

**Specification Compliance** — All requirements met:
- ✅ Enum expanded to 7 values: `stock`, `cachyos-gaming`, `cachyos-server`, `cachyos-desktop`, `cachyos-handheld`, `cachyos-lts`, `cachyos-hardened`
- ✅ All kernel package mappings match spec exactly
- ✅ `isCachyos = builtins.substring 0 7 cfg.type == "cachyos"` prefix check implemented (replacing hardcoded list)
- ✅ Binary caches for CachyOS kernels configured with `extra-substituters`/`extra-trusted-public-keys`
- ✅ Header comment updated to list all supported values

**Best Practices:**
- ✅ Uses `lib.mkOption` with `lib.types.enum` — type-safe, prevents invalid values at evaluation time
- ✅ Uses `lib.mkMerge` + `lib.mkIf` pattern — standard NixOS module idiom
- ✅ `extra-substituters` (not `substituters`) — correctly adds caches without overriding defaults
- ✅ `extra-trusted-public-keys` — same correct additive approach
- ✅ Default value `"stock"` ensures safe fallback
- ✅ Comprehensive description for each enum variant (scheduler, use case, key features)
- ✅ No import-from-derivation (IFD) — pure evaluation

**Consistency with Other Modules:**
- ✅ Follows `{ config, lib, pkgs, ... }:` argument pattern (matches `gpu.nix`)
- ✅ Uses `let cfg = config.kernel;` binding (matches `gpu.nix`'s `let cfg = config.gpu;`)
- ✅ `options.kernel` with `lib.mkOption` (matches `options.gpu`)
- ✅ `config = lib.mkMerge [ ... ]` with individual `lib.mkIf` blocks (matches `gpu.nix`)
- ✅ Header comment with module description and usage example (matches all modules)
- ✅ Section separator comments using `# ── Section ───...` style (matches project convention)

**Correctness:**
- ✅ `pkgs.linuxPackages_zen` — correct nixpkgs attribute for Zen kernel
- ✅ `pkgs.cachyosKernels.linuxPackages-cachyos-bore` — correct (Nix identifiers support hyphens; after `.` the parser expects an identifier, not an expression, so hyphens are part of the attr name)
- ✅ All CachyOS package paths match what `nix-cachyos-kernel`'s `overlays.default` exposes via `cachyosKernels` attribute set
- ✅ `builtins.substring 0 7 cfg.type == "cachyos"` — correctly detects all `cachyos-*` variants (first 7 chars of "cachyos-gaming" = "cachyos")
- ✅ Overlay applied in `flake.nix` line 62: `{ nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.default ]; }` — makes `pkgs.cachyosKernels.*` available
- ✅ `nix-cachyos-kernel` input uses `/release` branch (line 25 of flake.nix) — correct for pre-patched stable kernels
- ✅ flake.nix does NOT override nixpkgs for nix-cachyos-kernel (preserves kernel patch compatibility)

**Security:**
- ✅ Binary cache keys are pinned with specific public keys
- ✅ No network access or dynamic evaluation
- ✅ No privilege escalation in the module itself

### 2.2 justfile

**Specification Compliance:**
- ✅ `KERNELS` array expanded to 7 options matching kernel.nix enum
- ✅ `fzf --height=12` accommodates expanded list
- ✅ `list-kernels` recipe updated with all 7 options
- ✅ `kernel-info` recipe present and functional
- ✅ Additional `rebuild`, `rebuild-boot`, `preflight` recipes preserved

**Edge Case Handling:**
- ✅ `set -euo pipefail` — strict bash mode catches errors
- ✅ fzf cancellation (Esc/Ctrl-C) handled: `|| { echo "No kernel selected. Aborting."; exit 1; }`
- ✅ Empty `KERNEL_TYPE` guard: `if [[ -z "$KERNEL_TYPE" ]]; then ... exit 1; fi`
- ✅ Uses `nixos-rebuild boot` (not `switch`) — safer, requires reboot to apply

**Security (Shell Injection Analysis):**
- ✅ `$KERNEL_TYPE` is derived exclusively from hardcoded `KERNELS` array keys (line: `key="${k%%|*}"`), NOT from user input. The fzf selection only determines which predefined key is selected. No injection vector exists.
- ✅ `$CONFIG` is a hardcoded relative path, not user-supplied
- ✅ `sed` operates on a known file with a constrained pattern
- ✅ `sudo` is only used for `nixos-rebuild boot` — appropriate and necessary

**sed Command Analysis:**
```bash
sed -i "s/kernel\.type = \"[^\"]*\"/kernel.type = \"$KERNEL_TYPE\"/" "$CONFIG"
```
- ✅ Pattern `kernel\.type = \"[^\"]*\"` correctly matches `kernel.type = "stock"` (or any quoted value)
- ✅ The trailing semicolon in `kernel.type = "stock";` is preserved because it's outside the match
- ✅ The pattern does NOT match comment lines in configuration.nix (comments contain `"stock"` etc. but not `kernel.type = "stock"`)
- ⚠️ RECOMMENDED: sed silently succeeds even if the pattern doesn't match (e.g., if someone reformats the line). The script prints "Updated" regardless. See issue R1.

**Justfile Structure:**
- ✅ Shebang `#!/usr/bin/env bash` for the multi-line `kernel` recipe
- ✅ Simple `@echo` for `list-kernels` and `kernel-info` recipes
- ✅ Clean separation of concerns between recipes

### 2.3 hosts/default/configuration.nix

- ✅ `kernel.type = "stock"` present with correct default
- ✅ Comment above references `just list-kernels` and lists all valid values
- ✅ Lists all 7 valid enum values in the comment
- ✅ `../../modules/kernel.nix` imported in the modules list
- ✅ Follows same pattern as `gpu.type = "none"` declaration above it

### 2.4 flake.nix (No Changes Required — Verified)

- ✅ `nix-cachyos-kernel` input on `release` branch (line 24-28)
- ✅ Overlay applied in `mkVexosSystem` via `{ nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.default ]; }` (line 61-62)
- ✅ nixpkgs NOT overridden for nix-cachyos-kernel — preserves patch compatibility
- ✅ No changes needed — all new kernel variants are already available through the existing overlay

---

## 3. Issues

### CRITICAL — None

No build-breaking, security, or correctness issues found.

### RECOMMENDED

**R1. Justfile: sed replacement not verified** (`justfile`, line 56)

The `sed -i` command does not verify that a substitution actually occurred. If `configuration.nix` has been manually reformatted (e.g., extra spaces, tabs, or the line was removed), `sed` silently succeeds with zero replacements, but the script prints "Updated $CONFIG with kernel.type = ..." — misleading the user.

Suggested fix — add a `grep` check after sed:
```bash
sed -i "s/kernel\.type = \"[^\"]*\"/kernel.type = \"$KERNEL_TYPE\"/" "$CONFIG"
if ! grep -q "kernel\.type = \"$KERNEL_TYPE\"" "$CONFIG"; then
    echo "ERROR: Failed to update $CONFIG. Is kernel.type line present?"
    exit 1
fi
```

**R2. Justfile: No file existence check before sed** (`justfile`, line 55-56)

If `just kernel` is run from a directory other than the repo root, `hosts/default/configuration.nix` won't exist. While `set -e` catches the error, the sed error message is cryptic. A friendlier check would improve UX:
```bash
CONFIG="hosts/default/configuration.nix"
if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: $CONFIG not found. Run this from the repository root."
    exit 1
fi
```

### MINOR

**M1. Justfile: Could show diff of change** (`justfile`, line 57)

After updating the kernel type, showing the relevant line from configuration.nix would provide visual confirmation:
```bash
grep 'kernel.type' "$CONFIG"
```

**M2. list-kernels could indicate current selection more prominently** (`justfile`, line 70-80)

The `list-kernels` recipe shows the current setting via `grep`, but could prefix the active kernel with a marker (e.g., `→`) for quick visual identification. This is purely cosmetic.

---

## 4. Build Validation

**Result: N/A** — This is not a NixOS host. Build commands (`nix flake check`, `nix eval`) cannot be executed on this machine.

**Static analysis confirms:**
- All kernel package attribute paths match `nix-cachyos-kernel`'s documented overlay structure
- `lib.types.enum` prevents invalid values at evaluation time
- `lib.mkMerge` + `lib.mkIf` pattern guarantees exactly one kernel is selected
- `builtins.substring` is a pure builtin — no evaluation side effects
- Binary cache configuration uses additive settings (`extra-*`) — no override conflicts
- Module imports in `configuration.nix` are complete and correctly pathed
- No circular dependencies introduced

---

## 5. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 98% | A |
| Performance | 100% | A |
| Consistency | 98% | A |
| Build Success | N/A | N/A |

**Overall Grade: A (97%)**

---

## 6. Verdict

### **PASS**

The implementation correctly follows the specification, uses proper NixOS module conventions, maintains consistency with the existing codebase, and contains no critical issues. The two RECOMMENDED improvements (sed verification and file existence check in the justfile) are defensive hardening — the current code functions correctly under normal usage conditions.
