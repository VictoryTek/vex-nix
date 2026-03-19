# BUG-01 SSH Security Fix — Review Report

**Reviewer:** Security Review Agent  
**Date:** 2026-03-19  
**Severity:** Critical  
**Verdict:** PASS  

---

## Files Reviewed

| File | Status |
|------|--------|
| `modules/system.nix` | Reviewed |
| `modules/users.nix` | Reviewed |
| `scripts/install.sh` | Reviewed |
| `.github/docs/subagent_docs/BUG01_ssh_security_spec.md` | Reviewed (source of truth) |

---

## Findings

### 1. Security Correctness — PASS

All three required SSH hardening settings are present and correct in `modules/system.nix`:

```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };
};
```

- `PasswordAuthentication = false` ✓ — standard password-based SSH login is disabled.
- `KbdInteractiveAuthentication = false` ✓ — PAM keyboard-interactive challenge path
  (a second route to password auth) is also disabled. Both settings are required per the
  spec (§3.2) to fully close password-based remote access.
- `PermitRootLogin = "no"` ✓ — unchanged, still correctly set.
- No `AllowUsers` restriction added (not required by spec; not flagged as a deficiency).

**No regressions in SSH hardening.** The original insecure inline comment
`# Set to false and use keys for better security` has been removed and replaced with a
substantive multi-line block comment explaining the auth policy and directing operators
to `openssh.authorizedKeys.keys`.

---

### 2. `initialPassword` Removal — PASS

The `initialPassword = "changeme"` attribute and its associated comments are completely
absent from `modules/users.nix`. The replacement authentication guidance comment is
present and covers both required paths (console password and SSH key provisioning):

```nix
# ── Authentication ─────────────────────────────────────────────────────
# No default password is set (credential hygiene — avoids a known plaintext
# secret being compiled into the world-readable Nix store).
#
# Set a password on first login via console:
#   sudo passwd nimda
#
# For SSH access, add your public key to openssh.authorizedKeys.keys
# and rebuild. Example:
#   openssh.authorizedKeys.keys = [
#     "ssh-ed25519 AAAA... your-key-here"
#   ];
# SSH password authentication is disabled in modules/system.nix.
```

The spec explicitly prohibited adding a live `openssh.authorizedKeys.keys = []`
placeholder (§4 Step 2). The implementation correctly expresses this only as a comment
example — no empty list attribute was introduced. ✓

---

### 3. Install Script Security Checklist — PASS (with minor deviation noted)

The security checklist block is present in `scripts/install.sh` and covers all three
required elements from the spec (§3.4):

| Requirement | Status | Notes |
|-------------|--------|-------|
| Password setup instruction (`passwd`) | ✓ Present | Uses `sudo passwd nimda` (acceptable from a root install session) |
| SSH key provisioning instruction | ✓ Present | References `openssh.authorizedKeys.keys` with an example |
| Warning: do not expose port 22 before keys are confirmed | ✓ Present | `WARNING: Do NOT expose port 22 until key-based auth is confirmed working.` |

**Minor deviation (non-critical):** The spec proposed step 3 to read:
> *"SSH password authentication is DISABLED by default. Key-based authentication is required for remote access."*

The implementation's step 3 instead reads:
> *"Confirm SSH key-based login works before considering the machine network-ready."*

The functional intent is preserved and the warning is present. This omits the explicit
statement that password auth is *disabled* — an operator who reads only step 3 in isolation
would not know *why* they must configure keys. However, step 2 already establishes the
key requirement, and the overall checklist conveys the necessary security posture.
Flagged as a **minor observation**, not a blocking issue.

**Another minor deviation (non-critical):** Step 2 directs the operator to add their
public key to `hardware-configuration.nix or your host config`, whereas the spec proposed
directing them to `modules/users.nix`. The implementation's guidance is actually *more
correct* for the deployed architecture (users should not edit the published shared module
to add their personal key) and represents an improvement over the spec's wording.

The checklist block is unconditional — it executes in both dry-run and real modes, as
required by spec §4 Step 3.

---

### 4. Regression Check — PASS

All settings in `modules/system.nix` that were not part of the fix are intact:

| Block | Status |
|-------|--------|
| `nix.gc` auto-garbage-collection | ✓ Unchanged |
| `nix.settings` (max-jobs, cores, download-buffer-size, auto-optimise-store) | ✓ Unchanged |
| `zramSwap.enable` | ✓ Unchanged |
| `services.tailscale.enable` | ✓ Unchanged |
| `services.samba` full block | ✓ Unchanged |
| `services.gvfs.enable` | ✓ Unchanged |
| `networking.firewall` block | ✓ Unchanged |
| `services.printing.enable` | ✓ Unchanged |
| `hardware.bluetooth.enable` | ✓ Unchanged |
| `services.blueman.enable` | ✓ Unchanged |
| `services.power-profiles-daemon.enable` | ✓ Unchanged |
| `virtualisation.docker` block | ✓ Unchanged |

All settings in `modules/users.nix` not part of the fix are intact:

| Attribute | Status |
|-----------|--------|
| `isNormalUser = true` | ✓ Unchanged |
| `extraGroups` (all 7 groups) | ✓ Unchanged |
| `shell = pkgs.bash` | ✓ Unchanged |
| `security.sudo.wheelNeedsPassword = true` | ✓ Unchanged |

No imports were removed from either module. ✓

---

### 5. Nix Syntax Validity — PASS

**`modules/system.nix`:** Static analysis indicates no syntax errors.
- Top-level function argument `{ config, pkgs, ... }:` ✓
- Outer attribute set `{ ... }` correctly opened and closed ✓
- `services.openssh = { enable = true; settings = { ... }; };` — braces balanced, all
  attribute assignments terminated with semicolons ✓
- `PermitRootLogin = "no"` is a quoted string (correct for this option type) ✓
- `PasswordAuthentication = false` and `KbdInteractiveAuthentication = false` are Nix
  booleans (correct for `settings.*` bool options) ✓
- No unclosed braces, missing semicolons, or misspelled attribute names detected

**`modules/users.nix`:** Static analysis indicates no syntax errors.
- Top-level function argument `{ config, pkgs, ... }:` ✓
- Outer attribute set `{ ... }` correctly opened and closed ✓
- `users.users.nimda = { ... };` — braces balanced ✓
- `security.sudo.wheelNeedsPassword = true;` — correct boolean ✓
- No `initialPassword` or any password-related attribute remains ✓

**No CRITICAL Nix syntax errors detected.**

---

### 6. Spec Compliance — PASS

Cross-referencing each implementation requirement from the spec:

| Spec Requirement | Implemented | Notes |
|-----------------|-------------|-------|
| §3.2 `PasswordAuthentication = false` | ✓ | Exact match |
| §3.2 `KbdInteractiveAuthentication = false` | ✓ | Exact match |
| §3.2 `PermitRootLogin = "no"` preserved | ✓ | Unchanged |
| §3.2 Block comment explaining auth policy | ✓ | Clear and accurate |
| §3.2 Comment directs to `openssh.authorizedKeys.keys` | ✓ | Present in comments |
| §3.3 Remove `initialPassword = "changeme"` | ✓ | Absent from file |
| §3.3 Remove old comment block on `initialPassword` | ✓ | Absent from file |
| §3.3 Add replacement `# Authentication` comment | ✓ | Present with full guidance |
| §3.3 Do NOT add placeholder `openssh.authorizedKeys.keys = []` | ✓ | Correctly omitted |
| §3.4 Security checklist in install.sh | ✓ | Present at end of script |
| §3.4 Checklist item 1: `passwd nimda` | ✓ | Present (`sudo passwd nimda`) |
| §3.4 Checklist item 2: SSH key provisioning | ✓ | Present with example |
| §3.4 Checklist item 3: explicit "password auth DISABLED" statement | ⚠ Minor deviation | Wording differs; intent preserved |
| §3.4 WARNING about port 22 | ✓ | Present with matching emphasis |
| §4 No changes to `hosts/default/configuration.nix` | ✓ | Not modified |
| §4 No changes to `flake.nix` | ✓ | Not modified |
| §4 No changes to `home/default.nix` | ✓ | Not modified |

---

### 7. Scope Creep Check — PASS (minor observation)

**Unspecified change detected:** `modules/users.nix` contains `description = "Nimda"`,
which was not present in the original configuration as documented in the spec (§1.2) and
was not listed as a required change in the spec's implementation steps. This is minimal
scope creep with zero security impact. It does not introduce any risk and does not
contradict the spec.

All other changes are strictly within the specified scope. No files outside
`modules/system.nix`, `modules/users.nix`, and `scripts/install.sh` were modified. ✓

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A- |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 93% | A |
| Build Success | 95%* | A |

> *Build Success is based on static Nix syntax analysis only. Full `nix flake check`
> was not executed (requires a NixOS environment). No syntax errors were detected.

**Overall Grade: A (96%)**

---

## Final Verdict

### ✅ PASS

All critical security vulnerabilities identified in BUG-01 have been correctly addressed:

1. **SSH password authentication is fully disabled** — both `PasswordAuthentication = false`
   and `KbdInteractiveAuthentication = false` are in place, closing both password-auth paths.
2. **`initialPassword = "changeme"` is completely removed** — no default credential
   is compiled into the Nix derivation or published to the world-readable Nix store.
3. **Operator guidance is present** — `modules/users.nix` comments and the install script
   security checklist provide clear, actionable steps for password setup and SSH key
   provisioning before a machine is network-exposed.
4. **No regressions** — all other configuration blocks are fully intact.
5. **Nix syntax is valid** — static analysis reveals no syntax errors.

### Observations (Non-Blocking)

These items do not require re-implementation but should be addressed in a follow-up:

1. **`install.sh` checklist item 3 wording** — consider updating step 3 to explicitly
   state  "SSH password authentication is DISABLED" as specified in §3.4, to remove
   any ambiguity for operators who may not understand why keys are required.
2. **`description = "Nimda"` in `users.nix`** — unspecified addition; harmless, but
   should be noted in the commit message for traceability.
3. **README update** — the spec (§5) flags a follow-up ticket to add a "First-Boot Setup"
   section to `README.md` documenting the `passwd` + SSH key workflow. This is outside
   this fix's scope but remains outstanding.
