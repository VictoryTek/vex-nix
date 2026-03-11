# Thin Flake Architecture — Review

**Feature:** `thin_flake_arch`
**Date:** 2026-03-11
**Reviewer:** QA Subagent
**Status:** PASS

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A- |
| Best Practices | 85% | B |
| Functionality | 95% | A |
| Code Quality | 90% | A- |
| Security | 85% | B |
| Performance | 95% | A |
| Consistency | 88% | B+ |
| Build Success (Static) | 95% | A |

**Overall Grade: A- (90%)**

---

## 1. Static Analysis — `flake.nix`

Full brace-balance trace performed manually:

```
{                                   ← outer flake attrset (1)
  inputs = {                        ← (2)
    home-manager = { ... };         ← (3) → closed
    nix-gaming   = { ... };         ← (3) → closed
  };                                ← close (2)
  outputs = { self, nixpkgs, home-manager, ... }@inputs:   ← λ pattern (not a brace)
  let
    mkVexosSystem = { hardwareModule, system ? ... }:       ← λ pattern (not a brace)
      nixpkgs.lib.nixosSystem {                             ← (3)
        specialArgs = { inherit inputs; };                  ← (4) → closed inline
        modules = [
          {                                                  ← (4) home-manager inline module
            home-manager.extraSpecialArgs = { inherit inputs; };  ← (5) → closed inline
          }                                                  ← close (4)
        ];
      };                                                     ← close (3); terminates let binding
  in
  {                                                          ← (3) let body / outputs attrset
    lib.mkVexosSystem = mkVexosSystem;
    nixosConfigurations = {                                  ← (4)
      vexos = mkVexosSystem {                               ← (5)
        hardwareModule = ./hosts/default/hardware-configuration.nix;
      };                                                     ← close (5)
    };                                                       ← close (4)
  };                                                         ← close (3); terminates outputs = field
}                                                            ← close (1)
```

**Result: All braces balanced. Structure is syntactically correct.**

### Attribute path verification

| Path | Expected | Found | Status |
|------|----------|-------|--------|
| `lib.mkVexosSystem` | exported function | `mkVexosSystem` let-binding assigned to `lib.mkVexosSystem` | ✓ |
| `nixosConfigurations.vexos` | preserved for CI | calls `mkVexosSystem { hardwareModule = ./hosts/default/hardware-configuration.nix; }` | ✓ |
| `specialArgs.inputs` | all flake inputs | `{ inherit inputs; }` where `inputs` is `@inputs` capturing all | ✓ |
| `home-manager.users.nimda` | Home Manager module for user | `import ./home/default.nix` (returns module function) | ✓ |
| `inputs.nix-gaming.nixosModules.pipewireLowLatency` | nix-gaming module | referenced from `inputs` (via `@inputs`) | ✓ |
| `inputs.nix-gaming.nixosModules.platformOptimizations` | nix-gaming module | referenced from `inputs` (via `@inputs`) | ✓ |

**`nix-gaming` is only passed via `...` in the outputs destructure, but captured by `@inputs`.** This is correct — `inputs.nix-gaming` will be accessible in `specialArgs` even though it is not explicitly named in `{ self, nixpkgs, home-manager, ... }@inputs`.

---

## 2. Specification Compliance

### 2.1 `lib.mkVexosSystem` Exported

```nix
lib.mkVexosSystem = mkVexosSystem;   ✓
```

Correct. Exposed at `.#lib.mkVexosSystem` as required by Goal G5.

### 2.2 `nixosConfigurations.vexos` Preserved

```nix
nixosConfigurations = {
  vexos = mkVexosSystem {
    hardwareModule = ./hosts/default/hardware-configuration.nix;
  };
};
```

Correct. Uses the in-repo template hardware config for CI validation (Goal G6).

### 2.3 Thin Flake Template in `install.sh`

The written `flake.nix` content is:

```nix
{
  description = "VexOS local machine flake";

  inputs.vexos.url = "github:VexTrex87/vex-nix";

  outputs = { self, vexos }: {
    nixosConfigurations.<HOSTNAME> = vexos.lib.mkVexosSystem {
      hardwareModule = ./hardware-configuration.nix;
    };
  };
}
```

- References `./hardware-configuration.nix` ✓ (Goal G4)
- Uses `vexos.lib.mkVexosSystem` ✓
- `hardwareModule` passed correctly ✓

**Minor deviation:** The spec (Section 7) uses `{ self, vexos, ... }:` in the outputs pattern while the implementation uses `{ self, vexos }:` (no `...`). Since only `vexos` is declared as an input, omitting `...` is functionally correct — Nix only passes declared inputs to the outputs function. However, adding `...` is conventional for forward compatibility.

### 2.4 GitHub URL Discrepancy

The spec's ASCII diagram and Section 7 example use `github:VictoryTek/vex-nix`, but both `install.sh` and `README.md` consistently use `github:VexTrex87/vex-nix`. Since:
- `install.sh` and `README.md` are consistent with each other
- The curl URL in README references `VexTrex87`
- This appears to be the actual GitHub username

**Assessment:** Implementation is consistent. Spec examples appear to contain a placeholder username. This is flagged for confirmation only — not a build-critical issue.

### 2.5 `git init` + `git add` Steps

```bash
run git -C /etc/nixos init -b main
run git -C /etc/nixos add flake.nix hardware-configuration.nix
# ... nix flake update ...
run git -C /etc/nixos add flake.lock
```

All three git steps are present ✓ (required for pure flake evaluation per Goal G2).

---

## 3. Shell Script Quality — `install.sh`

| Check | Result |
|-------|--------|
| `set -euo pipefail` | ✓ Line 4 |
| `--dry-run` support | ✓ `OPT_DRYRUN` flag + `run()` helper |
| `--yes` support | ✓ `OPT_YES` flag skips interactive prompt |
| `--help` | ✓ `usage()` function, exits 0 |
| `--hostname NAME` | ✓ Sets `HOSTNAME` variable (interpolated into thin flake) |
| Error trap | ✓ `trap 'cleanup_on_error $LINENO' ERR` |
| Root check | ✓ Step 1, allows dry-run without root |
| Sentinel detection | ✓ Checks for "This is a template hardware configuration" comment |
| Dependency check | ✓ Checks for `nix` and `git` |
| No secrets written | ✓ |
| Correct `/etc/nixos/` path | ✓ |

**One note:** `git init -b main` requires git ≥ 2.28. NixOS 25.11 ships git 2.46+, so this is safe in the target environment. However, on unusual install media it could be a concern.

---

## 4. `deploy.sh` Deprecation

The deploy script has been replaced with a clean deprecation notice:
- Colour helpers preserved ✓
- Clear migration instructions pointing to `install.sh` ✓
- Update workflow steps documented ✓
- `exit 0` (non-error exit) ✓

**Minor issue:** The deprecation notice hardcodes `#vexos` in example commands:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos
```
If a user previously installed with `--hostname mymachine`, this example would be misleading. This is a documentation-only concern and does not affect any installed system.

---

## 5. `preflight.sh` — New Step 2b

```bash
LIB_CMD="nix ... eval .#lib.mkVexosSystem --apply builtins.typeOf"
LIB_RESULT=$(eval "$LIB_CMD" 2>&1) || true
if echo "$LIB_RESULT" | grep -q '"lambda"'; then
```

- Correctly validates `lib.mkVexosSystem` is a function (`"lambda"`) ✓
- `|| true` prevents `set -e` from killing the script on eval failure ✓
- **Minor:** Using `eval` on a fully static string is unnecessary but harmless. There is zero injection risk — `$LIB_CMD` is hardcoded with no user input. Alternative: call `nix` directly. This is a style issue only.

---

## 6. `home/default.nix` — Alias Consistency

```nix
update  = "cd /etc/nixos && sudo nix flake update && sudo git add flake.lock && sudo nixos-rebuild switch --flake /etc/nixos#vexos";
rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#vexos";
```

**Matches spec exactly** (Section 8, Phase 2). Old hardcoded
`/home/nimda/Projects/vex-nix` path is gone. Both aliases correctly target `/etc/nixos`. ✓

---

## 7. `README.md` — Install Flow Accuracy

| Step | Content | Status |
|------|---------|--------|
| Step 1 | `sudo nixos-generate-config` | ✓ correct |
| Step 2 | `curl ... \| sudo bash` bootstraps thin flake | ✓ correct |
| Step 3 | `sudo nixos-rebuild switch --flake /etc/nixos#vexos` | ✓ correct |
| Update flow | `nix flake update && git add flake.lock && nixos-rebuild switch` | ✓ matches alias |
| Manual bootstrap | Matches `install.sh` output exactly | ✓ |
| What Lives Where table | Accurate 3-file description | ✓ |

**Security note:** `curl ... | sudo bash` is a known-risky pattern that is widely used in the NixOS community for installer scripts. The risk is a MITM or compromised GitHub serving a malicious script. The `https://` URL mitigates passive eavesdropping. This is an accepted tradeoff in the ecosystem, but the README could optionally advise users to inspect the script before running it.

---

## 8. `hosts/default/configuration.nix` — Unchanged (Correct)

No changes made. Hardware configuration is injected via `mkVexosSystem { hardwareModule }`, not imported inside `configuration.nix`. This is the correct design. ✓

---

## 9. `hosts/default/hardware-configuration.nix` — Template Sentinel

Contains the identifying comment:
```
# This is a template hardware configuration.
```

This sentinel is correctly detected by `install.sh` Step 3. The `nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"` declaration is the modern NixOS way to set the build platform (not a deprecated `system` argument). ✓

---

## 10. Issues Summary

### CRITICAL
*None found.*

### MEDIUM

1. **GitHub username in spec vs implementation:** Spec uses `VictoryTek/vex-nix`; implementation consistently uses `VexTrex87/vex-nix`. Verify the actual GitHub username is `VexTrex87` before any public use. Not a build-breaking issue because the flake.nix (GitHub repo) itself has no URL self-reference.

2. **`curl | sudo bash` in README:** Accepted community pattern but worth adding a "inspect first" note for security-conscious users.

### MINOR

3. `{ self, vexos }:` in thin flake template omits `...` — recommend `{ self, vexos, ... }:` for forward compatibility.

4. `eval` in `preflight.sh` Step 2b is unnecessary (safe, but can be replaced with a direct `nix` invocation).

5. `git init -b main` requires git ≥ 2.28. Safe on NixOS 25.11 installer media.

6. `deploy.sh` deprecation notice hardcodes `#vexos` — users who installed with a custom hostname will see a misleading example.

---

## Verdict

**PASS**

All specification requirements are met. The `lib.mkVexosSystem` function is correctly defined, exported, and consumed. The `nixosConfigurations.vexos` CI configuration is preserved. Static analysis of `flake.nix` shows balanced braces, correct let...in structure, and valid attribute paths. Shell scripts follow the project's coding standards with `set -euo pipefail`, error traps, and complete option handling. No critical issues were found.
