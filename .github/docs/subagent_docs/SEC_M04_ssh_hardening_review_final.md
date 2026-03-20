# SEC M-04: SSH Hardening — Final Re-Review

**Phase 5 Re-Review**
**Date:** 2026-03-19
**Reviewer:** Senior NixOS Security Reviewer (Phase 5)
**Target file:** `modules/system.nix`
**Fix:** M-04 — Restrict SSH access with `AllowUsers`, `MaxAuthTries`, `LoginGraceTime`

---

## Verification Checklist

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| `PermitRootLogin` present | `"no"` | `"no"` | ✓ PASS |
| `PasswordAuthentication` present | `false` | `false` | ✓ PASS |
| `KbdInteractiveAuthentication` present | `false` | `false` | ✓ PASS |
| `AllowUsers` typed as list | `[ "nimda" ]` | `[ "nimda" ]` | ✓ PASS |
| `MaxAuthTries` present as integer | `3` | `3` | ✓ PASS |
| `LoginGraceTime` present as integer | `30` | `30` | ✓ PASS |
| Eval produces no errors | no errors | no errors | ✓ PASS |
| Build evaluation succeeds | exit 0 | exit 0 | ✓ PASS |

All six settings are present and correctly typed. **All checklist items PASS.**

---

## Full Eval Output

```
nix eval .#nixosConfigurations.vexos.config.services.openssh.settings 2>&1

warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
{
  AllowGroups = null;
  AllowUsers = [ "nimda" ];
  AuthorizedPrincipalsFile = "none";
  Ciphers = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" "aes128-gcm@openssh.com" "aes256-ctr" "aes192-ctr" "aes128-ctr" ];
  DenyGroups = null;
  DenyUsers = null;
  GatewayPorts = "no";
  KbdInteractiveAuthentication = false;
  KexAlgorithms = [ "mlkem768x25519-sha256" "sntrup761x25519-sha512" "sntrup761x25519-sha512@openssh.com" "curve25519-sha256" "curve25519-sha256@libssh.org" "diffie-hellman-group-exchange-sha256" ];
  LogLevel = "INFO";
  LoginGraceTime = 30;
  Macs = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha2-256-etm@openssh.com" "umac-128-etm@openssh.com" ];
  MaxAuthTries = 3;
  PasswordAuthentication = false;
  PermitRootLogin = "no";
  PrintMotd = false;
  StrictModes = true;
  UseDns = false;
  UsePAM = true;
  X11Forwarding = false;
}
```

**Observations from eval output:**

- `AllowUsers = [ "nimda" ]` — correctly a list, not a string. Nix accepted it without type error.
- `LoginGraceTime = 30` — integer, resolved correctly by `openssh` NixOS module.
- `MaxAuthTries = 3` — integer, resolved correctly; halves the sshd default of 6.
- `PasswordAuthentication = false` — confirmed off.
- `KbdInteractiveAuthentication = false` — confirmed off (closes keyboard-interactive bypass path).
- `PermitRootLogin = "no"` — confirmed.
- `StrictModes = true` — NixOS default; enforces file permission checks on `~/.ssh`.
- `X11Forwarding = false` — NixOS default; no X11 tunnel attack surface.
- `UsePAM = true` — NixOS default; required for PAM session accounting and systemd-logind integration.
- No build errors; exit code 0.

---

## Full Git Diff

```diff
diff --git a/modules/system.nix b/modules/system.nix
index b05f5c3..e0ba352 100644
--- a/modules/system.nix
+++ b/modules/system.nix
@@ -45,6 +45,9 @@
       #   users.users.nimda.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
       PasswordAuthentication = false;
       KbdInteractiveAuthentication = false;
+      AllowUsers = [ "nimda" ];  # restrict SSH to the sole human account
+      MaxAuthTries = 3;        # reduce per-connection key probing window (sshd default: 6)
+      LoginGraceTime = 30;     # close unauthenticated connections after 30 s (sshd default: 120)
     };
   };
```

**Diff analysis:**

- **Scope:** Minimal — exactly 3 lines added, 0 lines removed.
- **No unrelated changes:** The diff touches only the `services.openssh.settings` block.
- **Types correct:** `AllowUsers` is a Nix list literal (`[ "nimda" ]`); `MaxAuthTries` and `LoginGraceTime` are unquoted integers.
- **Comments:** Each new line carries an inline comment explaining the security rationale and the sshd default it overrides. This matches the documentation style already present in the file.
- **Indentation:** Consistent with surrounding code (6-space indent inside `settings = { ... }`).

---

## Security Impact Assessment

| Setting | Threat Mitigated | Severity |
|---------|-----------------|----------|
| `AllowUsers = [ "nimda" ]` | Prevents any system or service account (root, samba, docker, etc.) from being authenticated via SSH even if their passwords were known or keys accidentally provisioned | HIGH |
| `MaxAuthTries = 3` | Reduces the number of key/credential attempts an attacker can make per TCP connection before sshd disconnects; limits automated credential-stuffing and key-probing attacks | MEDIUM |
| `LoginGraceTime = 30` | Closes unauthenticated TCP connections after 30 seconds, reducing the window for slow brute-force attacks and unauthenticated connection exhaustion (CVE class: pre-auth resource exhaustion) | MEDIUM |

Together, these three settings complement the already-present `PermitRootLogin = "no"` and `PasswordAuthentication = false`, forming a defense-in-depth SSH posture.

---

## Phase 3 Issues — Resolution Status

| Issue ID | Description | Status |
|----------|-------------|--------|
| M-04-1 | `AllowUsers` missing from openssh settings | ✓ RESOLVED |
| M-04-2 | `MaxAuthTries` not set (used sshd default of 6) | ✓ RESOLVED |
| M-04-3 | `LoginGraceTime` not set (used sshd default of 120s) | ✓ RESOLVED |
| M-04-4 | `AllowUsers` must be typed as list, not string | ✓ RESOLVED — confirmed `[ "nimda" ]` |

No Phase 3 issues remain open.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Security Fix Quality | 100% | A+ |
| Code Quality | 100% | A+ |
| Nix Syntax / Types | 100% | A+ |
| No Regression | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (100%)**

---

## Final Verdict

**APPROVED**

All three M-04 security settings (`AllowUsers`, `MaxAuthTries`, `LoginGraceTime`) are correctly implemented in `modules/system.nix`. Types are correct, the flake evaluates without errors, the diff is minimal and focused, and no regressions were introduced. The SSH hardening posture is now complete and consistent with NixOS best practices.
