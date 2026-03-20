# Review: README Fresh Install Workflow Fix

**Feature:** `readme_install_fix`  
**Date:** 2026-03-20  
**Reviewer:** QA Subagent (Phase 3)  
**Files Reviewed:** `README.md`, `scripts/install.sh`, `flake.nix`, `hosts/default/hardware-configuration.nix`  
**Spec:** `.github/docs/subagent_docs/readme_install_fix_spec.md`

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 70% | C |
| Best Practices | 90% | A- |
| Functionality | 88% | B+ |
| Code Quality | 92% | A |
| Security | 90% | A- |
| Performance | 95% | A |
| Consistency | 85% | B |
| Build Success | N/A | — |

**Overall Grade: B- (87% over applicable categories, penalised by 70% spec compliance)**

---

## Build Validation

`nix flake check` cannot be executed in this Windows review environment. However:

- `flake.nix` was **not modified** by this implementation; the fix is documentation-only.
- The thin consumer flake syntax in `README.md` has been verified by reading `flake.nix` directly.
- No Nix expression changes require build validation.

**Build result: NOT RUN (Windows environment — not applicable to documentation-only change)**

---

## Validation Findings

### 1. Live ISO Section Correctness

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| Activate command | `nixos-install --flake /mnt/etc/nixos#vexos` | `nixos-install --flake /mnt/etc/nixos#vexos` | ✅ PASS |
| Flake target dir | `/mnt/etc/nixos/flake.nix` | `/mnt/etc/nixos/flake.nix` | ✅ PASS |
| `nixos-generate-config --root /mnt` before flake write | Step 2, before Step 3 | Step 2 (hardware config), Step 3 (write flake) | ✅ PASS |
| Disk partition/mount steps | Present | Present (Step 1, with UEFI example) | ✅ PASS |
| `nix-shell -p git` absent from live ISO section | Absent | Absent | ✅ PASS |
| Pre-generate `flake.lock` step | `nix flake update` in `/mnt/etc/nixos` | **MISSING** | ❌ FAIL |

**Notes:**
- The critical bug is fixed: `nixos-install` is used (not `nixos-rebuild switch`) and the path is `/mnt/etc/nixos/` (not `/etc/nixos/`).
- The `flake.lock` pre-generation step called for in spec §4 ("Step 3 — Generate flake.lock") is **not present**. `nixos-install --flake` will function without it (Nix will fetch inputs and generate its own lock during evaluation), but it deviates from the spec which explicitly included this step to pin the upstream revision before install.

---

### 2. Converting an Existing NixOS Install — Section Correctness

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| Uses `nixos-rebuild switch --flake /etc/nixos#vexos` | Yes | Yes | ✅ PASS |
| Writes to `/etc/nixos/flake.nix` | Yes | Yes | ✅ PASS |
| Has `nix-shell -p git` | Yes | Yes (Step 1) | ✅ PASS |
| Git init + flake update steps | Yes | Yes (Step 3) | ✅ PASS |
| Initial `sudo nixos-generate-config` step | Yes (spec §4, item 1) | **MISSING** | ❌ FAIL |

**Notes:**
- The spec's "Converting an Existing NixOS Install" section begins with "1. Generate (or verify) `hardware-configuration.nix`" using `sudo nixos-generate-config`. The README's Converting section jumps directly to "1. Install git", skipping this step.
- While an already-running NixOS system will always have `hardware-configuration.nix`, the spec included this step explicitly to ensure users on non-standard setups regenerate it before adopting VexOS. The step is absent.

---

### 3. Consistency With `flake.nix`

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| `vexos.lib.mkVexosSystem` in thin flake | Yes | Yes (both sections) | ✅ PASS |
| `nixosConfigurations.vexos` | Yes | Yes (both sections) | ✅ PASS |
| `hardwareModule = ./hardware-configuration.nix` | Yes | Yes (both sections) | ✅ PASS |

**Notes:**
- Both the Live ISO and Converting thin flakes exactly match the `lib.mkVexosSystem` signature exported at `outputs.lib.mkVexosSystem` in `flake.nix`. ✅
- The `#vexos` selector in the `nixos-install` and `nixos-rebuild switch` commands correctly references `nixosConfigurations.vexos`. ✅

---

### 4. Preservation of Existing Sections

| Section | Present | Intact | Result |
|---------|---------|--------|--------|
| "Keeping Your System Updated" | Yes | Yes | ✅ PASS |
| "What Lives Where" table | Yes | Yes | ✅ PASS |
| "⚠️ Alternative (Not Recommended)" section with security warnings | Yes | Yes (content unchanged) | ✅ PASS |
| "What's Included" | Yes | Yes | ✅ PASS |
| "Post-Install" | Yes | Yes | ✅ PASS |

---

### 5. Spec-Required Changes Not Implemented

These items are called out in the spec as required but are absent from the implementation:

#### 5a. Missing: `flake.lock` pre-generation in Live ISO section

**Spec §4 (Step 3):**
```bash
cd /mnt/etc/nixos
nix --extra-experimental-features 'nix-command flakes' flake update
```
This step is absent from the README. The install will still work without it (Nix fetches inputs automatically), but it is a spec deviation.

**Severity: MINOR** — functional impact is low; `nixos-install` resolves inputs itself.

---

#### 5b. Missing: `sudo nixos-generate-config` in Converting section

**Spec §4 (Converting, item 1):**
```bash
sudo nixos-generate-config
```
The Converting section in the README omits this first step. Any existing NixOS system has a `hardware-configuration.nix`, but users converting after a fresh minimal install may not have run this yet.

**Severity: MINOR** — `install.sh` checks for and rejects the template sentinel, so users are protected. But the step is missing from the manual instructions.

---

#### 5c. Missing: Alternative section heading rename

**Spec §4 (Alternative section):**  
Heading should be renamed from:
```
### ⚠️ Alternative (Not Recommended): Using the Install Script
```
to:
```
### ⚠️ Automated Option: `scripts/install.sh` (Existing Systems Only)
```
The README still uses the old heading. This framing change aligns the section with the two-scenario structure the fix introduces — making it clear `install.sh` is for existing installs, not fresh boots.

**Severity: MODERATE** — Does not affect functionality but leaves the heading inconsistent with the new section structure.

---

#### 5d. Missing: Scope clarification in Alternative section

**Spec §4 (Alternative section):**  
Should add at the top of the warning block:
```markdown
> **Scope:** `install.sh` automates the **Converting an Existing NixOS Install** steps above.
> It is not suitable for fresh installs from the live ISO.
```
This sentence is absent. Without it, a user reading the Alternative section after the Live ISO section may mistakenly believe `install.sh` can be used for fresh installs.

**Severity: MODERATE** — Directly affects user safety; the spec identified this as important for disambiguation.

---

#### 5e. Missing: `scripts/install.sh` `usage()` update

**Spec §2 ("Fix needed in `install.sh`"):**  
The `usage()` function still reads:
```
Bootstraps a fresh NixOS machine using the thin /etc/nixos/ flake model.
Requires hardware-configuration.nix to already exist at /etc/nixos/.

  The NixOS live installer generates this with:
    sudo nixos-generate-config
```
The phrase "Bootstraps a fresh NixOS machine" is misleading — `install.sh` is a Scenario B tool (converting an existing NixOS system). The hint `sudo nixos-generate-config` without `--root /mnt` could lead a live ISO user to write the hardware config into the live system's `/etc/nixos/` (ephemeral), then run `install.sh` — which subsequently fails.

The spec explicitly called this out:
> "Fix needed in `install.sh`: Update `usage()` to clarify this is for **converting an existing NixOS system**, not for fresh installs from the live ISO."

This change was **not made**.

**Severity: MODERATE** — The spec flagged this as a required change; the misleading text remains.

---

### 6. Markdown Quality

- Headings are properly structured (`####` for subsections within `###`).
- All code blocks use triple-backtick fencing with `bash` language tags. ✅
- No broken links, dangling backticks, or formatting artifacts. ✅
- Step numbering is consistent across both sub-sections. ✅

---

### 7. Positive Deviations (Improvements Over Spec)

These items differ from the spec's proposed content but are **improvements**:

1. **EFI partition label `boot` (lowercase)** — The spec's example used `BOOT` (uppercase), but the template `hardware-configuration.nix` (`hosts/default/hardware-configuration.nix`) references `/dev/disk/by-label/boot` (lowercase). The README's `mkfs.fat -F 32 -n boot` matches the template exactly, preventing label mismatch on a fresh install. This is a **better** choice than BOOT.

2. **`mount -o umask=077` for EFI mount** — The README adds `umask=077` when mounting the EFI partition. This is a security best practice (prevents world-readable EFI contents) not present in the spec's example. ✅

3. **Inline disk substitution comment** — `# Replace /dev/sda with your actual disk` appears before the partition commands, protecting users from blindly running commands against the wrong device. ✅

---

## Summary

### What is Correct (Critical Fix)

The primary purpose of this change — fixing the live ISO installation workflow — is correctly implemented:

- `nixos-install --flake /mnt/etc/nixos#vexos` replaces the broken `nixos-rebuild switch`. ✅
- All live ISO paths correctly target `/mnt/etc/nixos/`. ✅
- `nixos-generate-config --root /mnt` is present and correctly placed. ✅
- Disk setup steps are present and functional. ✅
- `nix-shell -p git` is correctly absent from the live ISO section. ✅
- The Converting section is correctly split out with the right commands. ✅
- Both thin flake examples match `flake.nix`'s `lib.mkVexosSystem` API. ✅

### What Is Missing (Spec Deviations)

Five items from the spec were not implemented:

| # | Issue | Severity |
|---|-------|----------|
| 1 | Missing `flake.lock` pre-generation step in live ISO section | Minor |
| 2 | Missing `sudo nixos-generate-config` first step in Converting section | Minor |
| 3 | Alternative section heading not renamed | Moderate |
| 4 | Scope clarification not added to Alternative section | Moderate |
| 5 | `scripts/install.sh` `usage()` not updated | Moderate |

---

## Verdict

**NEEDS_REFINEMENT**

The critical correctness fix is implemented and verified. However, three moderate-severity spec items remain unimplemented (items 3, 4, 5 above), including the `install.sh` `usage()` update which the spec explicitly identified as a required fix. These should be addressed before delivery to prevent user confusion and align fully with the specification.

### Required Actions for Refinement

1. Add `flake.lock` pre-generation step to the live ISO section (between "Write the thin flake" and "Install"):
   ```bash
   cd /mnt/etc/nixos
   nix --extra-experimental-features 'nix-command flakes' flake update
   ```

2. Add `sudo nixos-generate-config` as Step 1 of the Converting section.

3. Rename the Alternative section heading to:
   ```
   ### ⚠️ Automated Option: `scripts/install.sh` (Existing Systems Only)
   ```

4. Add scope clarification at the top of the Alternative warning block:
   ```markdown
   > **Scope:** `install.sh` automates the **Converting an Existing NixOS Install** steps above.
   > It is not suitable for fresh installs from the live ISO.
   ```

5. Update `scripts/install.sh` `usage()` to replace:
   ```
   Bootstraps a fresh NixOS machine using the thin /etc/nixos/ flake model.
   ```
   with text that clarifies this script is for **converting an existing NixOS system**, not for fresh installs from the live ISO, and update the `nixos-generate-config` hint to clarify it must be run on the target booted system (not on the live ISO).
