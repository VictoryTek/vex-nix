# Deploy Script Review — `scripts/deploy.sh`

**Project:** VexOS NixOS Configuration  
**Review Date:** 2026-03-10  
**Reviewer:** QA Subagent  
**Files Reviewed:**
- `scripts/deploy.sh`
- `scripts/preflight.sh` (style reference)
- `README.md`
- `.github/docs/subagent_docs/deploy_script_spec.md`
- `hosts/default/hardware-configuration.nix`
- `flake.nix`

---

## Syntax Check

```
$ wsl bash -c "bash -n /mnt/c/Projects/vex-nix/scripts/deploy.sh 2>&1"
(no output)
EXIT:0
```

**Result: PASS — zero syntax errors.**

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 93% | A |
| Consistency | 97% | A |
| Syntax Validity | 100% | A |

**Overall Grade: A (97%)**

---

## Validation Checklist

### Spec Compliance

| Item | Status | Notes |
|------|--------|-------|
| `-y`/`--yes` flag present | ✅ PASS | Parsed in `while` loop; skips confirmation in Step 3 |
| `--regen-hardware` flag present | ✅ PASS | Forces `do_regen_hardware()` in Step 8 |
| `--keep-hardware` flag present | ✅ PASS | Forces `do_keep_hardware()` in Step 8 |
| `--dry-run` flag present | ✅ PASS | Activates `run()` guard throughout |
| `-h`/`--help` flag present | ✅ PASS | Calls `usage()` and exits 0 |
| Mutual exclusion check | ✅ PASS | `--regen-hardware` + `--keep-hardware` detected and rejected before any action |
| Root/sudo check before destructive ops | ✅ PASS | Step 2 checks `$EUID -ne 0`; only warns in dry-run mode |
| Backup created before file modification | ✅ PASS | Step 6 runs before Step 7; uses `cp -a` (preserves timestamps/perms) |
| Fresh-install path handled | ✅ PASS | `FRESH_INSTALL=true` set when `/etc/nixos/` does not exist |
| `.git/` and `.github/` excluded from copy | ✅ PASS | rsync `--exclude='.git/' --exclude='.github/'`; cp fallback uses `rm -rf` after copy |
| Hardware sentinel detection | ✅ PASS | `is_template_hardware_config()` greps for exact sentinel matching `hardware-configuration.nix` line 1 |
| `find_hw_config_in_dir()` handles both layouts | ✅ PASS | Checks `hosts/default/` first, then root layout fallback |
| `--keep-hardware` fails clearly on fresh install | ✅ PASS | `do_keep_hardware()` returns 1 with `[FAIL]` if no backup hw config found |
| Permissions set on `/etc/nixos/` | ✅ PASS | Step 9: `chown root:root`, `chmod 755` dirs, `chmod 644` files, `chmod 755` scripts |
| `nixos-rebuild switch --flake /etc/nixos#vexos` | ✅ PASS | Step 10; inline failure handling prints backup path |
| ERR trap installed at top of script | ✅ PASS | `trap 'cleanup_on_error $LINENO' ERR` placed right after `set -euo pipefail` |
| ERR trap prints backup path | ✅ PASS | `cleanup_on_error()` checks `$BACKUP_DIR` and prints restore instructions |
| `REPO_DIR` resolved from `BASH_SOURCE[0]` | ✅ PASS | `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` |

---

### Style Consistency (vs `preflight.sh`)

| Item | Status | Notes |
|------|--------|-------|
| `#!/usr/bin/env bash` shebang | ✅ PASS | Identical |
| `set -euo pipefail` | ✅ PASS | Identical |
| `RED`, `GREEN`, `YELLOW`, `NC` colour vars | ✅ PASS | Matching; deploy.sh adds `BLUE` for banner (additive, not contradictory) |
| `pass()`, `fail()`, `warn()`, `info()` helpers | ✅ PASS | Identical signatures and formatting |
| `ERRORS=0` accumulator with `ERRORS=$((ERRORS + 1))` | ✅ PASS | Identical pattern |
| Step headers use `==>` prefix | ✅ PASS | Wrapped in `step()` helper — produces identical output |
| Coloured `=====` result banner | ✅ PASS | Green on success, red on failure, matching preflight.sh pattern |
| `run()` helper for dry-run guard | ✅ PASS | Prefix applied to every mutating command |

Minor difference: deploy.sh adds a `step()` helper function to avoid code repetition in step headers. preflight.sh uses inline `echo`. The output is functionally identical; the helper is a clean improvement.

---

### Security Review

| Item | Status | Notes |
|------|--------|-------|
| No `eval` of untrusted input | ✅ PASS | No `eval` used anywhere in deploy.sh |
| Variables quoted to prevent word splitting | ✅ PASS | `"$BACKUP_DIR"`, `"${REPO_DIR}/"`, `"$hw_config"`, `"$BACKUP_DIR"` all quoted in all execution contexts |
| rsync/cp excludes `.git/` and `.github/` | ✅ PASS | rsync uses `--exclude`; cp fallback uses `rm -rf` on both dirs |
| Timestamped backup path (no predictable filename) | ✅ PASS | `BACKUP_DIR="/etc/nixos.bak-${TIMESTAMP}"` using `date +%Y%m%d-%H%M%S` |
| No credentials or secrets in script | ✅ PASS | None present |
| `/tmp/hardware-configuration.nix` — predictable path | ⚠️ WARN (LOW) | `do_regen_hardware()` writes to `/tmp/hardware-configuration.nix`. Since the script requires root and the output is root-written, practical risk is low. A `mktemp` approach would be strictly more correct but is not required for this use-case. |

---

### Bash Correctness

| Item | Status | Notes |
|------|--------|-------|
| `set -euo pipefail` | ✅ PASS | Present on line 2 |
| All variable references quoted | ✅ PASS | No unquoted expansion of user-controlled or path variables detected |
| ERR trap fires correctly | ✅ PASS | `return 1` in helper functions propagates to the ERR trap under `set -e`; trap captures `$LINENO` at the call site |
| Bash 4.x compatibility | ✅ PASS | No `mapfile`, `declare -A`, or other bash 4+ exclusives used; `[[ =~ ]]` is bash 3.2+ |
| `--dry-run` prevents ALL mutations | ✅ PASS | Every mutation is wrapped in `run()` or an explicit `if [[ "$OPT_DRYRUN" == "true" ]]` guard |
| `run()` uses `"$@"` for execution | ✅ PASS | Argument integrity preserved during real execution |
| `run()` uses `$*` for display string | ✅ INFO | Cosmetic only — arguments with spaces appear merged in dry-run display. Not a correctness or security issue. Using `printf '%s ' "$@"` would produce more precise output but is not required. |
| `nixos-rebuild` missing → `exit 1` (not just `ERRORS++`) | ✅ PASS | Hard failure with explicit message in Step 4 |

---

### README Review

| Item | Status | Notes |
|------|--------|-------|
| "Automated Deployment" section present | ✅ PASS | Correctly placed after "Installation" section |
| All 5 flags in the table | ✅ PASS | `-y`/`--yes`, `--regen-hardware`, `--keep-hardware`, `--dry-run`, `-h`/`--help` |
| Common examples block | ✅ PASS | Covers interactive, non-interactive keep, regen, and dry-run cases |
| GPU note included | ✅ PASS | Blockquote warning about setting `gpu.type` before deploying |
| Backup behavior explained | ✅ PASS | Final paragraph explains timestamped backup and rollback |
| `--keep-hardware` description slightly imprecise | ℹ️ INFO | README says "from the current `/etc/nixos/`" but the script restores from the timestamped backup, not the live directory. Functionally the pre-copy state is equivalent; this is a documentation nuance only, not misleading for typical users. |

---

## Findings Summary

### Critical Issues
None.

### Warnings (non-blocking)
1. **`/tmp/hardware-configuration.nix` — predictable filename** (Security, LOW):  
   In `do_regen_hardware()`, the generated hardware config is written to `/tmp/hardware-configuration.nix` — a fixed, world-readable path. Since the script runs as root and the file contains only hardware topology (no secrets), real-world risk is minimal. Mitigation: replace with `HW_TMP="$(mktemp)"` and remove on completion. Not required to block delivery.

### Informational Notes
2. **`run()` dry-run display uses `$*`**: Arguments with embedded spaces may appear joined in `[DRY-RUN]` output lines. No execution impact; purely cosmetic in dry-run mode.
3. **README `--keep-hardware` description**: Says "from the current `/etc/nixos/`"; technically restores from the timed backup. Correct result, mildly imprecise wording.
4. **`step()` helper not in preflight.sh**: The `step()` abstraction is an improvement; the output is identical to the inline pattern used in preflight.sh.

---

## Verdict

**PASS**

All specification requirements are fully implemented. Syntax is valid. Security posture is good with one low-severity note. Style is consistent with `preflight.sh`. Dry-run mode correctly guards every mutating operation. The README accurately documents all flags, examples, GPU guidance, and backup behavior. No critical or blocking issues found.
