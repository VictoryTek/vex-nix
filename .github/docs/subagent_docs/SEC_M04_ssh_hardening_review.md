# SEC-M04: SSH Defence-in-Depth Hardening — Phase 3 Review

**Phase:** 3 — Review & Quality Assurance  
**Finding ID:** M-04 (Medium)  
**Reviewer:** Senior NixOS Security Reviewer  
**Date:** 2026-03-19  
**Verdict:** ❌ NEEDS_REFINEMENT

---

## 1. Fix Completeness

All three required settings were added to `services.openssh.settings`. The full updated block as it
appears in `modules/system.nix`:

```nix
# Enable OpenSSH
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    # Secure production settings: password-based SSH login is disabled.
    # Authenticate using an SSH public key only. Keys must be provisioned
    # before enabling this service on a network-facing machine.
    # Add your public key to modules/users.nix:
    #   users.users.nimda.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    AllowUsers = "nimda";    # restrict SSH to the sole human account
    MaxAuthTries = 3;        # reduce per-connection key probing window (sshd default: 6)
    LoginGraceTime = 30;     # close unauthenticated connections after 30 s (sshd default: 120)
  };
};
```

**Status:** All three settings present — ✅ three new keys added, all with inline documentation.

---

## 2. No-Regression Check

| Setting | Expected | Present | Unchanged |
|---|---|---|---|
| `PermitRootLogin` | `"no"` | ✅ | ✅ |
| `PasswordAuthentication` | `false` | ✅ | ✅ |
| `KbdInteractiveAuthentication` | `false` | ✅ | ✅ |

The original three hardening settings are fully intact. ✅

---

## 3. Nix Type Correctness — CRITICAL FAILURE

| Setting | Implemented As | NixOS Option Type | Correct? |
|---|---|---|---|
| `AllowUsers` | `"nimda"` (string) | `null or (list of string)` | ❌ **WRONG TYPE** |
| `MaxAuthTries` | `3` (integer) | integer | ✅ |
| `LoginGraceTime` | `30` (integer) | integer | ✅ |

**`AllowUsers` is a `list of string` in NixOS, not a plain string.**

The correct Nix expression is:

```nix
AllowUsers = [ "nimda" ];
```

not:

```nix
AllowUsers = "nimda";
```

This type mismatch causes a hard evaluation error and prevents the system from being built.
The sshd_config directive `AllowUsers nimda` is generated from the list, not from a bare string.

---

## 4. Scope Check

`git diff --name-only` output (all unstaged changes in the working tree):

```
README.md
hosts/default/hardware-configuration.nix
modules/gnome.nix
modules/kernel.nix
modules/system.nix
```

`modules/system.nix` is present. ✅

The diff for `modules/system.nix` shows **only three lines added** inside the openssh `settings` block
and no other section touched:

```diff
+      AllowUsers = "nimda";    # restrict SSH to the sole human account
+      MaxAuthTries = 3;        # reduce per-connection key probing window (sshd default: 6)
+      LoginGraceTime = 30;     # close unauthenticated connections after 30 s (sshd default: 120)
```

Scope is clean — no unrelated modifications. ✅

---

## 5. Nix Syntax

The file is syntactically valid Nix (the parser accepts it). The failure occurs at **option type
evaluation**, not at parse time. Syntax: ✅. Runtime type: ❌.

---

## 6. Build Validation

### Command run:
```bash
nix eval .#nixosConfigurations.vexos.config.services.openssh.settings 2>&1
```

### Full output:
```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
{ AllowGroups = null;
  AllowUsers = «error: A definition for option `services.openssh.settings.AllowUsers' is not of
    type `null or (list of string)'. Definition values:
    - In `/nix/store/dnn0kj5zd5gr1jsmw0rvrjwwf34qh9hv-source/modules/system.nix': "nimda"»;
  ...
  KbdInteractiveAuthentication = false;
  LoginGraceTime = 30;
  MaxAuthTries = 3;
  PasswordAuthentication = false;
  PermitRootLogin = "no";
  ...
}
```

**Observations:**
- `MaxAuthTries = 3` and `LoginGraceTime = 30` evaluate successfully. ✅
- `PasswordAuthentication = false`, `PermitRootLogin = "no"`, `KbdInteractiveAuthentication = false`
  are intact. ✅
- `AllowUsers` throws an evaluation error. ❌ The NixOS option is `null or (list of string)` and
  the value `"nimda"` (a string) does not satisfy that type.

**Build result: FAIL — type error, configuration cannot be instantiated.**

---

## 7. Why `AllowUsers` Is a Meaningful Defence-in-Depth Measure

Even with `PasswordAuthentication = false`, an attacker who obtains a valid private key for any
system account (e.g., `root`, a service account, or a compromised application user) could
authenticate via key-based auth if `AllowUsers` is not set. `AllowUsers = [ "nimda" ]` ensures the
SSH daemon refuses key-based connections from every account except the explicitly whitelisted human
user, closing that residual attack surface at the sshd layer independently of what keys may exist on
the system.

---

## 8. Required Fix

**Change in `modules/system.nix`** — single character change, line ~47:

```nix
# Before (WRONG — type error):
AllowUsers = "nimda";

# After (CORRECT — list of string):
AllowUsers = [ "nimda" ];
```

No other changes required.

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 90% | A- |
| Security Fix Quality | 85% | B+ |
| Code Quality | 95% | A |
| Nix Syntax / Types | 40% | F |
| No Regression | 100% | A+ |
| Build Success | 0% | F |

**Overall Grade: D+ (68%)**

> Scores reflect that the intent and structure are correct and the no-regression bar is met, but the
> single type mistake (`"nimda"` vs `[ "nimda" ]`) causes a hard build failure, which is a blocking
> defect.

---

## Summary of Issues

| Severity | Issue | Fix |
|---|---|---|
| 🔴 CRITICAL | `AllowUsers = "nimda"` is wrong Nix type (`string` vs `list of string`) | Change to `AllowUsers = [ "nimda" ];` |

---

## Verdict

**NEEDS_REFINEMENT**

The implementation contains one blocking defect: `AllowUsers` is set to a bare string instead of a
list of strings. This causes the NixOS option type checker to reject the configuration at evaluation
time, preventing a successful build. The fix is a single-line, one-character change. All other
aspects of the implementation are correct.
