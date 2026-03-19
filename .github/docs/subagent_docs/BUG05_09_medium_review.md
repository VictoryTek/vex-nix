# BUG-05 through BUG-09 — Medium-Severity Combined Review

**Date:** 2026-03-19
**Reviewer:** Static Review Pass
**Spec:** `.github/docs/subagent_docs/BUG05_09_medium_spec.md`
**Files Reviewed:**
- `modules/gnome.nix`
- `flake.nix`
- `modules/system.nix`
- `scripts/preflight.sh`
- `hosts/default/configuration.nix`

---

## Per-Check Results

### BUG-05 — Duplicate `gnomeExtensions.appindicator` (`modules/gnome.nix`)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | `gnomeExtensions.appindicator` appears exactly ONCE in `environment.systemPackages` | ✅ PASS | `grep -c` returns 1 match at line 33 |
| 2 | First occurrence (near top of list) is preserved | ✅ PASS | Line 33 — third entry after `gnome-tweaks` and `dconf-editor`, identical to original first occurrence |
| 3 | No other package entries accidentally removed | ✅ PASS | All 14 remaining packages present: `gnome-tweaks`, `dconf-editor`, `gnomeExtensions.appindicator`, `dash-to-dock`, `alphabetical-app-grid`, `gamemode-shell-extension`, `gnome-40-ui-improvements`, `nothing-to-say`, `steal-my-focus-window`, `tailscale-status`, `caffeine`, `restart-to`, `blur-my-shell`, `background-logo`, `gnome-boxes` |

**BUG-05 verdict: ALL PASS**

---

### BUG-06 — `nix-flatpak` missing `inputs.nixpkgs.follows` (`flake.nix`)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 4 | Comment exists immediately above `nix-flatpak.url` explaining why `follows` is omitted | ✅ PASS | Lines 19–21: `# No inputs.nixpkgs.follows — nix-flatpak has no inputs in its flake` / `# (outputs = _: { ... }); adding follows would be silently ignored.` directly precede line 22 `nix-flatpak.url` |
| 5 | `inputs.nixpkgs.follows` was NOT added to the nix-flatpak block | ✅ PASS | `nix-flatpak.url` remains a single-attribute declaration with no braces block and no `follows` line |
| 6 | No other flake inputs modified | ✅ PASS | `nixpkgs`, `nixpkgs-unstable`, `home-manager`, `nix-gaming`, `nix-cachyos-kernel`, `up` all unchanged |

**BUG-06 verdict: ALL PASS**

---

### BUG-07 — Samba `map to guest = bad user` (`modules/system.nix`)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 7 | `"map to guest" = "never"` is present in the Samba global config | ✅ PASS | Line 67: `"map to guest" = "never";  # Fail explicitly on bad credentials; no silent guest fallback` |
| 8 | `"bad user"` value is GONE | ✅ PASS | `grep "bad user" modules/system.nix` produces no match |
| 9 | No other Samba settings modified | ✅ PASS | `workgroup`, `server string`, `netbios name`, `security`, `hosts allow`, `hosts deny`, `guest account`, and the `public` share block are all unchanged |

**BUG-07 verdict: ALL PASS**

---

### BUG-08 — `eval`-based nix command construction (`scripts/preflight.sh`)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 10 | No bash `eval` builtin calls remain for nix eval commands | ✅ PASS | All occurrences of the string `eval` in the file are either (a) the word `evaluation` in echo/pass/fail strings, or (b) the `nix eval` subcommand name in the argument to `nix`. No `eval "$..."` bash builtin pattern exists. |
| 11 | No `EVAL_CMD` or `LIB_CMD` string variables exist | ✅ PASS | `grep "EVAL_CMD\|LIB_CMD" scripts/preflight.sh` produces no match |
| 12 | Step 2 uses direct `nix ... eval` invocation | ✅ PASS | Lines 30–32: `RESULT=$(nix --extra-experimental-features 'nix-command flakes' \` / `  eval .#nixosConfigurations.vexos.config.system.build.toplevel \` / `  --apply builtins.typeOf 2>&1) || RESULT=""` |
| 13 | Step 2b uses direct `nix ... eval` invocation | ✅ PASS | Lines 44–46: `LIB_RESULT=$(nix --extra-experimental-features 'nix-command flakes' \` / `  eval .#lib.mkVexosSystem \` / `  --apply builtins.typeOf 2>&1) || LIB_RESULT=""` |
| 14 | `\|\| true` replaced with `\|\| RESULT=""` / `\|\| LIB_RESULT=""` | ✅ PASS | Line 32: `|| RESULT=""` confirmed; line 46: `|| LIB_RESULT=""` confirmed; `|| true` absent from file |
| 15 | All surrounding echo/pass/fail/info/grep lines unchanged | ✅ PASS | Lines 27–39 (Step 2) and 41–53 (Step 2b) match spec's proposed fix verbatim for all non-command lines |

**BUG-08 verdict: ALL PASS**

---

### BUG-09 — Redundant `tailscale` in `systemPackages` (`hosts/default/configuration.nix`)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 16 | `tailscale` is ABSENT from `environment.systemPackages` | ✅ PASS | `grep tailscale hosts/default/configuration.nix` produces no matches |
| 17 | All other packages in `systemPackages` are unchanged | ✅ PASS | List contains exactly `wget`, `git`, `curl`, `htop`, `firefox`, `cifs-utils` — matches pre-fix list minus `tailscale` |

**BUG-09 verdict: ALL PASS**

---

### General / Regression Checks

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 18 | No regressions — nothing else accidentally changed in any file | ✅ PASS | Each file has exactly the minimum change prescribed by the spec: one line removed (gnome.nix), two comment lines added (flake.nix), one value changed (system.nix), two code blocks refactored (preflight.sh), one line removed (configuration.nix) |
| 19 | All `.nix` files remain syntactically valid | ✅ PASS | `gnome.nix`: list brackets balanced, `with pkgs;` scope correct; `flake.nix`: comment-only addition, no structural change; `system.nix`: attribute unchanged except value string; `configuration.nix`: list item removed, brackets balanced |
| 20 | `preflight.sh` remains syntactically valid bash | ✅ PASS | `$(...)` command substitution properly closed before `||`; backslash line continuations on lines 30–31, 44–45 are syntactically correct (no trailing whitespace risk observed); single-quote pairing in `'nix-command flakes'` is correct; all function calls (`pass`, `fail`, `info`) are unchanged |

**General verdict: ALL PASS**

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

> Note: "Build Success" is assessed by static analysis per the review instructions.
> No live build was executed. All `.nix` files are structurally valid; `preflight.sh`
> passes `bash -n` syntax rules as verified by manual static inspection.

---

## Summary

All 20 review criteria pass without exception. Each of the five bug fixes is minimal,
correct, and precisely scoped:

- **BUG-05**: Second `gnomeExtensions.appindicator` removed; first occurrence and all
  surrounding entries intact.
- **BUG-06**: Two-line comment added immediately above `nix-flatpak.url` matching the
  spec text exactly; no `follows` line added; no other inputs touched.
- **BUG-07**: `"map to guest"` changed from `"bad user"` to `"never"` with an inline
  clarifying comment; no other Samba settings modified.
- **BUG-08**: `EVAL_CMD`/`LIB_CMD` string variables and `eval "$..."` bash builtin
  calls eliminated; direct multi-line `nix eval` invocations used; `|| true`
  replaced with `|| RESULT=""`/`|| LIB_RESULT=""` preserving `set -euo pipefail`
  semantics.
- **BUG-09**: `tailscale` removed from `environment.systemPackages`; service remains
  managed via `services.tailscale.enable = true` in `modules/system.nix`.

No regressions detected. No syntax errors. No spec deviations.

---

## Final Verdict

**PASS**
