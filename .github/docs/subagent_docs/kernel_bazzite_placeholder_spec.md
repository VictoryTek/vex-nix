# VexOS Kernel — Bazzite Placeholder Specification

**Feature:** Add `bazzite` kernel option placeholder to the kernel switching infrastructure
**Date:** 2026-03-13
**Status:** Research Complete / Ready for Implementation
**Spec File:** `.github/docs/subagent_docs/kernel_bazzite_placeholder_spec.md`

---

## 1. Current Configuration Analysis

### Relevant Files

| File | Relevant State |
|------|---------------|
| `modules/kernel.nix` | 7-option enum: `stock`, `cachyos-gaming`, `cachyos-server`, `cachyos-desktop`, `cachyos-handheld`, `cachyos-lts`, `cachyos-hardened`. Uses `lib.mkMerge` + `lib.mkIf` per option. `isCachyos` prefix check (`builtins.substring 0 7 cfg.type == "cachyos"`) gates binary cache config. |
| `flake.nix` | Inputs: `nixpkgs` (25.11), `nixpkgs-unstable`, `home-manager`, `nix-gaming`, `nix-flatpak`, `nix-cachyos-kernel`. `mkVexosSystem` applies `nix-cachyos-kernel.overlays.default`, exposing `pkgs.cachyosKernels.*`. No `vex-kernels` input exists yet. |
| `justfile` | `KERNELS` array has 7 entries. `kernel` recipe uses `fzf` to select, `sed` to patch `configuration.nix`, `nixos-rebuild boot` to apply. `list-kernels` echoes all 7 options. |
| `hosts/default/configuration.nix` | `kernel.type = "stock"` with comment listing all 7 valid enum values. |

### Module Pattern

All VexOS kernel module entries follow this structure (from `modules/kernel.nix`):
1. A section comment: `# ── <Name> (<feature>) ──...`
2. A `(lib.mkIf (cfg.type == "<value>") { ... })` block inside `lib.mkMerge`
3. A single `boot.kernelPackages = <pkg>;` attribute for all real kernels

---

## 2. Problem Definition

The Bazzite Gaming Kernel (`bazzite-org/kernel-bazzite`) is a Fedora kernel-ark derivative with handheld/gaming patches. The previous kernel switching spec (see `kernel_switching_spec.md`, Section 3.3) determined that the Bazzite kernel **cannot be cleanly packaged for NixOS today** — it uses RPM spec-based builds, Fedora-specific config infrastructure, and a non-vanilla kernel-ark base.

The plan is to package the Bazzite kernel in a **separate future flake** (`vex-kernels`) when the packaging work is done. This spec defines the **placeholder** that:

1. Wires `"bazzite"` into the `kernel.type` enum now so downstream code and users can see it
2. Provides a helpful `throw` error if someone attempts to use it before `vex-kernels` is ready
3. Adds commented-out scaffolding in `flake.nix` so the final wiring is a minimal diff when `vex-kernels` is created
4. Adds the option to the `justfile` menu with a clear "pending" marker

**Goal:** Zero regressions on the current build. The `"bazzite"` enum value must be safe to have in the module even when `vex-kernels` does not exist.

---

## 3. Design Decisions

### Decision 1 — Use `throw` in the `mkIf` block instead of a stub kernel package

**Rationale:** Nix evaluates lazily. The body of `lib.mkIf (cfg.type == "bazzite") { ... }` is only forced when the condition is `true` (i.e., a user actually sets `kernel.type = "bazzite"`). If the current deployment uses any other kernel type, the `throw` is never reached and the build succeeds normally.

This means:
- All 7 existing kernel options continue to work identically
- `nix flake check` passes (the CI config uses `kernel.type = "stock"`)
- A user who accidentally sets `bazzite` gets a clear, actionable error message rather than a cryptic missing-attribute error

**Alternative rejected:** Pointing to a hypothetical `pkgs.vexKernels.linuxPackages-bazzite` would cause an `attribute 'vexKernels' missing` error the moment any evaluation touches `pkgs`, before even reaching the mkIf condition. This would break the build for all configs. The `throw` approach avoids this entirely.

### Decision 2 — `vex-kernels` overlay is fully commented out in `flake.nix`

**Rationale:** Nix flakes fail evaluation if an input is declared but the URL is unreachable or the repo does not exist. Leaving `vex-kernels` commented out in `inputs` means the flake can be evaluated and built without the future repo existing yet.

Two separate comment blocks are required:
- In `inputs` — declares the future input URL
- In the `mkVexosSystem` `modules` list — applies the future overlay

Both blocks are marked with `# TODO:` to make the wiring step obvious.

### Decision 3 — `isCachyos` prefix check must NOT match `"bazzite"`

**Rationale:** The existing `isCachyos = builtins.substring 0 7 cfg.type == "cachyos"` check (first 7 chars) will not match `"bazzite"` (first 7 chars = `"bazzite"` ≠ `"cachyos"`). This is already correct behavior — no change needed. The Bazzite kernel will need its **own** binary cache configuration in a future spec, not the CachyOS caches.

### Decision 4 — Justfile menu adds `"bazzite"` with a visible "(pending)" marker

**Rationale:** Users running `just kernel` should see the option but understand it is not yet functional. If they select it, they will get a clear error from the `throw` during `nixos-rebuild`. The description must communicate this clearly.

### Decision 5 — Placeholder attribute path: `pkgs.vexKernels.linuxPackages-bazzite`

**Rationale:** This mirrors the pattern established by `pkgs.cachyosKernels.*` from `nix-cachyos-kernel`. The naming convention assumes the `vex-kernels` flake will expose an overlay that injects a `vexKernels` attribute set into `pkgs`, containing `linuxPackages-bazzite`. This attribute path is referenced only in comments and documentation — **not** in live Nix code until `vex-kernels` exists.

---

## 4. Implementation Plan

### 4.1 File Changes Summary

| File | Action | Scope |
|------|--------|-------|
| `modules/kernel.nix` | **Modify** | Add `"bazzite"` to enum; add `mkIf` block with `throw`; update header comment |
| `flake.nix` | **Modify** | Add commented-out `vex-kernels` input + overlay |
| `justfile` | **Modify** | Add `"bazzite"` to `KERNELS` array; add to `list-kernels` |
| `hosts/default/configuration.nix` | **Modify** | Update comment listing valid enum values to include `"bazzite"` |

---

### 4.2 `modules/kernel.nix` — Detailed Changes

#### 4.2.1 File Header Comment

The header comment currently lists 7 supported values. Add `"bazzite"` to the list:

**Current (line 6):**
```
#   "cachyos-desktop", "cachyos-handheld", "cachyos-lts", "cachyos-hardened".
```

**New:**
```
#   "cachyos-desktop", "cachyos-handheld", "cachyos-lts", "cachyos-hardened",
#   "bazzite" (placeholder — requires vex-kernels flake).
```

#### 4.2.2 `lib.types.enum` List

Add `"bazzite"` as the eighth entry after `"cachyos-hardened"`:

```nix
type = lib.types.enum [
  "stock"
  "cachyos-gaming"
  "cachyos-server"
  "cachyos-desktop"
  "cachyos-handheld"
  "cachyos-lts"
  "cachyos-hardened"
  "bazzite"
];
```

#### 4.2.3 Description String

Add a `"bazzite"` entry to the `description` field. The description should communicate its pending status:

```
"bazzite"          — Bazzite Gaming Kernel (PENDING). Requires the vex-kernels
                     flake input. Selection will throw an error until wired up.
                     See flake.nix and kernel_bazzite_placeholder_spec.md.
```

#### 4.2.4 New `mkIf` Block

Insert after the `# ── CachyOS Hardened (security-focused) ──` block (line ~93) and before the `# ── Binary cache for CachyOS kernels ──` block:

```nix
# ── Bazzite Gaming Kernel (placeholder) ───────────────────────────────
# Requires vex-kernels flake input — see flake.nix for wiring instructions.
# Once vex-kernels is available, replace the throw with:
#   boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;
(lib.mkIf (cfg.type == "bazzite") {
  boot.kernelPackages = throw ''

    kernel.type = "bazzite" is not yet available.

    The Bazzite kernel requires the vex-kernels flake input, which has
    not been created yet. To enable this:
      1. Create the vex-kernels flake at github:<owner>/vex-kernels
      2. Uncomment the vex-kernels input block in flake.nix
      3. Uncomment the vex-kernels overlay in flake.nix (mkVexosSystem)
      4. Replace this throw with:
           boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;

    See: .github/docs/subagent_docs/kernel_bazzite_placeholder_spec.md
  '';
})
```

**Key properties of this implementation:**
- The `throw` string is only evaluated when `cfg.type == "bazzite"` is `true` (lazy evaluation)
- If `kernel.type` is anything else, this block is entirely inert
- The error message is actionable — it lists exactly what steps are required to complete the wiring

---

### 4.3 `flake.nix` — Detailed Changes

#### 4.3.1 `inputs` Section — Add Commented `vex-kernels` Input

Insert after the `nix-cachyos-kernel` block (lines 24–28), before the closing `};` of `inputs`:

```nix
# TODO: Uncomment when the vex-kernels repo is ready.
# Bazzite and custom kernels for NixOS.
# Provides: overlays.default (pkgs.vexKernels.*)
# vex-kernels = {
#   url = "github:<owner>/vex-kernels";
#   inputs.nixpkgs.follows = "nixpkgs";
# };
```

**Note:** `<owner>` is a placeholder — the actual GitHub org/user should be substituted when the real repo is created.

#### 4.3.2 `mkVexosSystem` Modules List — Add Commented Overlay

Insert after the CachyOS overlay line (`{ nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.default ]; }`):

```nix
# TODO: Uncomment when vex-kernels input is added above.
# Bazzite kernel overlay — exposes pkgs.vexKernels.*
# { nixpkgs.overlays = [ inputs.vex-kernels.overlays.default ]; }
```

---

### 4.4 `justfile` — Detailed Changes

#### 4.4.1 `KERNELS` Array in `kernel` Recipe

Add `"bazzite"` as the last entry in the `KERNELS` array:

**Current last entry:**
```bash
"cachyos-hardened|CachyOS Hardened — Security-focused with hardening patches"
```

**Add after:**
```bash
"bazzite|Bazzite Gaming Kernel (pending — requires vex-kernels, see docs)"
```

#### 4.4.2 `list-kernels` Recipe

Add `bazzite` entry at the end of the echo list, before the blank line and `Current setting:` block:

```bash
@echo "  bazzite           — Bazzite Gaming Kernel (pending: requires vex-kernels flake)"
```

---

### 4.5 `hosts/default/configuration.nix` — Detailed Changes

Update the comment above `kernel.type` to include `"bazzite"`:

**Current:**
```nix
# Valid: "stock", "cachyos-gaming", "cachyos-server", "cachyos-desktop",
#        "cachyos-handheld", "cachyos-lts", "cachyos-hardened"
```

**New:**
```nix
# Valid: "stock", "cachyos-gaming", "cachyos-server", "cachyos-desktop",
#        "cachyos-handheld", "cachyos-lts", "cachyos-hardened",
#        "bazzite" (pending — requires vex-kernels flake)
```

---

## 5. Safety Analysis

### Build Safety

The following scenarios are safe:

| Scenario | Outcome |
|----------|---------|
| `kernel.type = "stock"` (CI default) | `throw` never evaluated — build succeeds |
| `kernel.type = "cachyos-*"` (any CachyOS variant) | `throw` never evaluated — build succeeds |
| `kernel.type = "bazzite"` | `throw` triggered at eval time — clear error message |
| `nix flake check` (uses `kernel.type = "stock"`) | Passes — no breakage |
| `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel` | Passes — no breakage |

### Lazy Evaluation Guarantee

`lib.mkIf false { boot.kernelPackages = throw "..."; }` is safe in Nix because:
1. `lib.mkIf` internally produces `lib.mkMerge []` when the condition is false
2. The inner attrset is never forced
3. `boot.kernelPackages` is therefore never evaluated to `throw "..."`
4. This is standard NixOS module practice — used for all conditional configurations

### `isCachyos` Check — No Impact

`builtins.substring 0 7 "bazzite" == "bazzite"` (7 chars of `"bazzite"` = `"bazzite"`), which is not equal to `"cachyos"`. The CachyOS binary cache stanza does NOT apply to bazzite. This is correct — bazzite will need its own binary cache config in a future spec.

### Flake Inputs — No Impact

All `vex-kernels`-related content is inside Nix comments (`#`). Nix ignores comments entirely. No new inputs are declared, so no new flake lock entries are required, and `nix flake check` will not attempt to fetch any new URLs.

### Shell Injection — No New Risk

Adding `"bazzite"` to the `KERNELS` array in the justfile follows the same pattern as all other entries. The key (`bazzite`) is a hardcoded string — it is never constructed from user input. The existing sed injection analysis from `kernel_switching_review.md` (section 2.2) applies without change.

---

## 6. Future Completion Steps (Out of Scope Here)

When `vex-kernels` is eventually created, the following steps complete the wiring:

1. **Create `github:<owner>/vex-kernels` flake** — packages `linuxPackages-bazzite` and exposes `overlays.default` injecting `pkgs.vexKernels`
2. **`flake.nix`** — Uncomment the `vex-kernels` input block; uncomment the overlay module in `mkVexosSystem`
3. **`modules/kernel.nix`** — Replace the `throw` in the `bazzite` mkIf block with:
   ```nix
   boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;
   ```
4. **Add binary cache config** — Add a `lib.mkIf (cfg.type == "bazzite")` block for `nix.settings.extra-substituters` / `nix.settings.extra-trusted-public-keys` pointing to the vex-kernels binary cache
5. **Run `nix flake update`** — Locks the new `vex-kernels` input in `flake.lock`
6. **Update header comment** — Remove the `(placeholder — requires vex-kernels flake)` qualifier

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `throw` evaluated unexpectedly | Very Low | Lazy eval guarantees it only fires for `kernel.type = "bazzite"` |
| Future `vex-kernels` overlay uses a different attr name than `vexKernels` | Low | Attribute path is only in comments — no live code to break |
| `nix flake check` fails due to new enum value | None | `check` evaluates `kernel.type = "stock"` which is unaffected |
| Justfile fzf menu includes pending option and user accidentally selects it | Medium | The description clearly labels it as pending; rebuild will fail with clear message from `throw` |
| `sed` in justfile matches `bazzite` entry incorrectly | None | `sed` targets `kernel.type = "..."` pattern, `KERNEL_TYPE` from array key is well-formed |

---

## 8. Implementation Checklist for Phase 2

- [ ] `modules/kernel.nix`: Update file header comment (lines 5-6)
- [ ] `modules/kernel.nix`: Add `"bazzite"` to `lib.types.enum` list (after `"cachyos-hardened"`)
- [ ] `modules/kernel.nix`: Add `"bazzite"` description entry in `lib.mkOption` description string
- [ ] `modules/kernel.nix`: Add `(lib.mkIf (cfg.type == "bazzite") { ... })` block with `throw`
- [ ] `flake.nix`: Add commented-out `vex-kernels` input after `nix-cachyos-kernel` block
- [ ] `flake.nix`: Add commented-out overlay application in `mkVexosSystem` modules list
- [ ] `justfile`: Add `"bazzite|..."` entry to `KERNELS` array in `kernel` recipe
- [ ] `justfile`: Add `bazzite` line to `list-kernels` recipe
- [ ] `hosts/default/configuration.nix`: Update `kernel.type` comment to include `"bazzite"`
- [ ] Verify: `nix flake check` still passes with no changes to `kernel.type = "stock"`
- [ ] Verify: No live Nix code references `inputs.vex-kernels` or `pkgs.vexKernels`

---

## 9. References

- `modules/kernel.nix` — current implementation (7 kernels, `isCachyos` prefix check)
- `flake.nix` — current inputs and `mkVexosSystem` structure
- `justfile` — current kernel menu implementation
- `.github/docs/subagent_docs/kernel_switching_spec.md` — prior spec (decision: Bazzite not packageable for NixOS today; see Section 3.3)
- `.github/docs/subagent_docs/kernel_switching_review.md` — prior review (PASS, A 97%)
- [Nix language — lazy evaluation and `throw`](https://nixos.org/manual/nix/stable/language/builtins.html#builtins-throw)
- [NixOS modules — `lib.mkIf`](https://nixos.org/manual/nixpkgs/stable/#sec-option-declarations)
- [bazzite-org/kernel-bazzite](https://github.com/bazzite-org/kernel-bazzite) — Bazzite kernel source (RPM-based, Fedora kernel-ark)
