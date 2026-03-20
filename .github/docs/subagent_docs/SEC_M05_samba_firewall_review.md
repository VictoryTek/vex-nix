# SEC-M05: Samba `openFirewall` — Phase 3 Review

**Phase:** 3 — Review & Quality Assurance  
**Severity:** Medium  
**File reviewed:** `modules/system.nix`  
**Spec:** `.github/docs/subagent_docs/SEC_M05_samba_firewall_spec.md`  
**Date:** 2026-03-19  
**Reviewer:** Phase 3 Subagent  

---

## 1. Build Validation Results

### 1.1 `services.samba.openFirewall`

```
$ nix eval .#nixosConfigurations.vexos.config.services.samba.openFirewall
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
false
```

**Result: PASS** — `openFirewall` evaluates to `false`.

---

### 1.2 `networking.firewall.allowedTCPPorts`

```
$ nix eval .#nixosConfigurations.vexos.config.networking.firewall.allowedTCPPorts
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
[ 22 139 445 ]
```

**Result: PASS** — Ports `139` and `445` are present.  
Note: Port `22` is injected by `services.openssh` via NixOS module firewall
integration — not from this diff. This is expected NixOS behaviour (port lists
are merged across all modules).

---

### 1.3 `networking.firewall.allowedUDPPorts`

```
$ nix eval .#nixosConfigurations.vexos.config.networking.firewall.allowedUDPPorts
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
[ 137 138 5353 ]
```

**Result: PASS** — Ports `137` and `138` are present.  
Note: Port `5353` (mDNS/Avahi) is injected by another module — not from this
diff. Expected NixOS behaviour.

---

### 1.4 `git diff --name-only`

```
README.md
hosts/default/hardware-configuration.nix
modules/gnome.nix
modules/kernel.nix
modules/system.nix
```

`modules/system.nix` is modified. Other files in the diff are unrelated to
SEC-M05 and are pre-existing uncommitted changes.

---

## 2. Fix Completeness

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `services.samba.openFirewall` | `false` | `false` | ✓ PASS |
| `allowedTCPPorts` contains 139 | yes | yes (`[ 22 139 445 ]`) | ✓ PASS |
| `allowedTCPPorts` contains 445 | yes | yes (`[ 22 139 445 ]`) | ✓ PASS |
| `allowedUDPPorts` contains 137 | yes | yes (`[ 137 138 5353 ]`) | ✓ PASS |
| `allowedUDPPorts` contains 138 | yes | yes (`[ 137 138 5353 ]`) | ✓ PASS |

---

## 3. No-Regression Check

| Check | Present? | Status |
|-------|----------|--------|
| `"hosts allow" = "192.168. 127.0.0.1 localhost"` | Yes (line 66) | ✓ PASS |
| `"hosts deny" = "0.0.0.0/0"` | Yes (line 67) | ✓ PASS |
| `trustedInterfaces = [ "tailscale0" ]` | Yes (line 91) | ✓ PASS |
| `public` share definition unchanged | Yes (lines 74–82) | ✓ PASS |
| `valid users`, `guest ok`, `create mask`, etc. unchanged | Yes | ✓ PASS |

All existing safety guards are intact. No configuration lines were removed that
should have been retained.

---

## 4. No Duplicate Attributes

Confirmed from source and successful evaluation:

- `allowedTCPPorts` appears exactly **once** in `networking.firewall`.
- `allowedUDPPorts` appears exactly **once** in `networking.firewall`.
- No duplicate attribute evaluation error was raised by `nix eval`.

---

## 5. Nix Syntax Validity

- All braces and brackets are balanced (verified by successful `nix eval`).
- Semicolons are present on all attribute assignments.
- Inline comment style (`#`) is consistent with the surrounding file.

---

## 6. Functional Equivalence Analysis

**Before:** `openFirewall = true` caused the NixOS Samba module to
programmatically insert TCP 139/445 and UDP 137/138 rules on all interfaces.

**After:** `openFirewall = false` with explicit `allowedTCPPorts = [ 139 445 ]`
and `allowedUDPPorts = [ 137 138 ]` achieves exactly the same kernel firewall
state — the same ports, the same interface scope (all interfaces).

The net effect for LAN SMB clients is **identical**. No connectivity regression.

---

## 7. Code Quality Observations

**Positive:**

- Inline comment on the `openFirewall` line explains the intent:
  ```nix
  openFirewall = false; # ports opened explicitly in networking.firewall below
  ```
- The `networking.firewall` block includes a forward-looking comment showing
  how to scope rules to a specific NIC, supporting future per-interface
  hardening without requiring research.
- Old stale comment (`# Samba ports are opened by openFirewall = true above`)
  was correctly removed along with the empty port lists.

---

## 8. Out-of-Scope Finding (Informational Only)

The diff also includes SSH hardening settings **not in the SEC-M05 spec**:

```nix
AllowUsers = [ "nimda" ];  # restrict SSH to the sole human account
MaxAuthTries = 3;          # reduce per-connection key probing window
LoginGraceTime = 30;       # close unauthenticated connections after 30 s
```

These are valid security improvements and do not conflict with the Samba fix.
However, they were not requested under SEC-M05. They should be attributed to
a separate ticket (likely a parallel SSH hardening fix) for traceability.

**This finding does not block PASS for SEC-M05.**

---

## 9. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Security Fix Quality | 100% | A |
| Code Quality | 100% | A |
| Nix Syntax | 100% | A |
| No Regression | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

---

## 10. Verdict

**PASS**

All review criteria are satisfied:

- `openFirewall = false` is confirmed by `nix eval`.
- TCP ports 139 and 445 are confirmed present in the evaluated firewall list.
- UDP ports 137 and 138 are confirmed present in the evaluated firewall list.
- `hosts allow`, `hosts deny`, and `trustedInterfaces` are all intact.
- No duplicate attributes exist.
- Nix syntax is valid (evaluates without errors).
- Functional equivalence with the previous configuration is confirmed.

The implementation is correct, clean, and ready for commit.
