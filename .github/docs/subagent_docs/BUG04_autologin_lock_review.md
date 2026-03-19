# BUG-04 Review: Auto-Login + Screen Lock Fix

**Reviewer:** Security Review Subagent  
**Date:** 2026-03-19  
**Spec:** `.github/docs/subagent_docs/BUG04_autologin_lock_spec.md`  
**Files Reviewed:** `home/default.nix`, `modules/gnome.nix`  
**Review Type:** Static analysis (no build executed per instructions)

---

## Findings by Criterion

### 1. `lock-enabled = false` Removed ✅ PASS

Confirmed absent. A grep for `lock-enabled` in `home/default.nix` returns exactly one
match — `lock-enabled = true` on line 169. The insecure override is gone.

---

### 2. `lock-enabled = true` Present ✅ PASS

```nix
"org/gnome/desktop/screensaver" = {
  lock-enabled = true;   # Re-enabled: screen lock is security-critical on any unattended machine
  lock-delay   = (lib.hm.gvariant.mkUint32 0);
};
```

Explicit boolean `true` is set. GNOME's default is restored and made auditable.

---

### 3. `lock-delay` Set ✅ PASS

`lock-delay = (lib.hm.gvariant.mkUint32 0)` is present in the screensaver block.
The parentheses wrapping the function call are valid Nix expression grouping and do
not affect semantics. The GVariant type is `u` (uint32) as required by the GSettings
schema — correct.

---

### 4. `idle-delay` Set ✅ PASS

```nix
"org/gnome/session" = {
  idle-delay = (lib.hm.gvariant.mkUint32 300);  # Screensaver activates after 5 minutes of inactivity
};
```

The `"org/gnome/session"` block is present immediately after the screensaver block,
before the `"org/gnome/desktop/app-folders"` section as the spec required. Value is
300 seconds (5 minutes), typed as uint32. Correct.

---

### 5. `lib` in Function Args ✅ PASS

```nix
{ config, lib, pkgs, pkgs-unstable, inputs, ... }:
```

`lib` is present in the argument set (line 1 of `home/default.nix`). Required for
`lib.hm.gvariant.mkUint32`. Syntax is valid.

---

### 6. Security Invariant Comment in `gnome.nix` ✅ PASS (minor deviation)

The comment block is present:

```nix
  # Auto-login — skips the GDM lock screen on boot (convenience feature).
  # SECURITY INVARIANT: auto-login must NEVER be combined with
  # `lock-enabled = false` in dconf. The screen lock in home/default.nix
  # MUST remain enabled to prevent physical-access bypasses when the
  # session is unattended. Do not set lock-enabled = false downstream.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "nimda";
```

**Minor deviation:** The spec's prescribed comment is longer and includes two
additional pieces of guidance:
- "suitable for physically secure single-user machines" context
- Explicit `services.displayManager.autoLogin.enable = false;` snippet for
  disabling auto-login in higher-security deployments

The implemented comment conveys the essential security invariant and cross-references
`home/default.nix` correctly. The omitted lines are informational and their absence
does **not** compromise the security intent. Flagged as **informational only** —
not a blocking issue.

---

### 7. No Regressions ✅ PASS

All other dconf blocks inspected:

| Block | Status |
|-------|--------|
| `org/gnome/shell` (extensions, favorite-apps) | Unchanged |
| `org/gnome/desktop/interface` | Unchanged |
| `org/gnome/desktop/wm/preferences` | Unchanged |
| `org/gnome/desktop/background` | Unchanged |
| `org/gnome/shell/extensions/dash-to-dock` | Unchanged |
| `org/gnome/desktop/app-folders` (all sub-keys) | Unchanged |
| `home.packages` | Unchanged |
| `programs.bash`, `programs.starship` | Unchanged |
| `home.sessionVariables` | Unchanged |
| GTK / cursor theme config | Unchanged |
| `home.file` wallpaper sources | Unchanged |

`modules/gnome.nix` non-comment content (extensions, virtualisation, libvirtd,
overlays, excludePackages, gnome-keyring) is entirely untouched.

---

### 8. Nix Syntax Validity ✅ PASS

**Module signature:**  
`{ config, lib, pkgs, pkgs-unstable, inputs, ... }:` — valid attribute set pattern.

**`lib.hm.gvariant.mkUint32` calls:**  
`(lib.hm.gvariant.mkUint32 0)` and `(lib.hm.gvariant.mkUint32 300)` — valid Nix
function application. Outer parentheses are legal expression grouping, not function
call syntax; they correctly force `mkUint32 N` to be parsed as a single expression
when used as an attribute value.

**Brace matching in `dconf.settings`:**  
- Outer `dconf.settings = { ... };` — opens and closes correctly.
- Each sub-attrset (`"org/..."` block) has matching `{` / `};`.
- The `"org/gnome/session"` addition introduces one new attrset that is correctly
  opened and closed with `};` before the app-folders block begins.
- End-of-file structure: `"org/gnome/desktop/app-folders/folders/System"` closes
  with `};`, then `};` closes `dconf.settings`, then `programs.home-manager.enable
  = true;`, then `}` closes the module function body. Brace count is balanced.

No syntax errors detected.

---

### 9. Spec Compliance ✅ PASS (minor deviation noted)

| Spec Requirement | Implemented | Notes |
|------------------|-------------|-------|
| Add `lib` to module args | ✅ | Exact match |
| Remove `lock-enabled = false` | ✅ | Confirmed absent |
| Add `lock-enabled = true` | ✅ | Exact match |
| Add `lock-delay = mkUint32 0` | ✅ | Wrapped in parens; functionally identical |
| Add `"org/gnome/session"` with `idle-delay = mkUint32 300` | ✅ | Correct position |
| BUG-04 block comment above screensaver | ⚠️ | Replaced by inline EOL comments; conveys same information |
| Security invariant comment in `gnome.nix` | ⚠️ | Present; shorter than spec; missing `autoLogin.enable = false` snippet |

Both deviations are **style/completeness gaps**, not functional defects. All
security-critical changes are correctly implemented.

---

### 10. No Scope Creep ✅ PASS

Modifications are confined to:
1. `home/default.nix` line 1 (add `lib` to args)
2. `home/default.nix` `"org/gnome/desktop/screensaver"` block (replace values)
3. `home/default.nix` new `"org/gnome/session"` block (addition)
4. `modules/gnome.nix` auto-login comment block (comment-only change)

No other files touched. No new packages, inputs, or modules introduced. The scope
is exactly as specified.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A- |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 90% | A- |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 95% | A |
| Build Success | 92% | A (static review) |

**Overall Grade: A (95%)**

---

## Issues Summary

### CRITICAL
_None._

### MAJOR
_None._

### MINOR / INFORMATIONAL

1. **Comment style deviation (home/default.nix):** The spec prescribes a 3-line block
   comment above the `"org/gnome/desktop/screensaver"` key. The implementation uses
   inline EOL comments instead. Functionally equivalent; no fix required.

2. **Security comment truncated (modules/gnome.nix):** The implementation comment is
   5 lines; the spec prescribed 9 lines including an explicit `autoLogin.enable = false`
   code example for downstream disablement. The shortened comment preserves the security
   invariant but lacks the actionable guidance. Recommended (not required) to expand.

---

## Final Verdict

# ✅ PASS

All security-critical requirements are correctly implemented:
- The physical-access bypass (`lock-enabled = false`) is removed
- Screen lock is explicitly re-enabled with correct GVariant types
- Idle and lock timers are set declaratively
- The `lib` argument is present
- A security invariant warning guards the auto-login block in `modules/gnome.nix`
- No regressions or scope creep detected
- Nix syntax is valid

The two informational deviations (comment wording) do not affect security posture,
functionality, or build correctness. No changes are required before merging.
