# SEC-M04: SSH Defence-in-Depth Hardening — Specification

**Phase:** 1 — Research & Specification  
**Finding ID:** M-04 (Medium)  
**File to modify:** `modules/system.nix` only  
**Date:** 2026-03-19  

---

## 1. Verdict: Real Gap

This is a **real, actionable gap** — not a false positive.  
The current configuration has a correct baseline (no password auth, no root login) but is missing
several low-cost sshd_config hardening settings that are standard practice even on personal machines.

---

## 2. Current SSH Configuration (verbatim from `modules/system.nix`)

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
  };
};
```

**What is already correct:**
| Setting | Value | Status |
|---|---|---|
| `PermitRootLogin` | `"no"` | ✅ Correct |
| `PasswordAuthentication` | `false` | ✅ Correct |
| `KbdInteractiveAuthentication` | `false` | ✅ Correct |

**What is missing:**
| Setting | Current | Risk |
|---|---|---|
| `AllowUsers` | Not set — any system user can attempt auth | Medium |
| `MaxAuthTries` | Defaults to `6` — allows excessive key probing per connection | Low-Medium |
| `LoginGraceTime` | Defaults to `120` s — unauthenticated connections held open 2 min | Low |

---

## 3. Human User Identification

From `modules/users.nix`:

```nix
users.users.nimda = {
  isNormalUser = true;
  description = "Nimda";
  extraGroups = [ 
    "networkmanager" 
    "wheel"          # Enable sudo
    "audio"
    "video"
    "libvirtd"
    "gamemode"
  ];
  ...
};
```

**Confirmed:** Username is `nimda`. It is in the `wheel` group.  
This is the **sole human user** and the only account that should be allowed SSH access.

---

## 4. fail2ban Assessment

**Recommendation: NO — do not add fail2ban.**

**Reasoning:**

With `PasswordAuthentication = false` and `KbdInteractiveAuthentication = false` already set,
the only remaining attack surfaces are:

1. **Key-exhaustion probing** — an attacker cycling through many public keys per connection.
   - Mitigated directly by `MaxAuthTries = 3`.
2. **Connection flooding** — holding open many unauthenticated connections.
   - Mitigated directly by `LoginGraceTime = 30`.

fail2ban works by parsing sshd log lines and banning IPs via iptables/nftables.
On a personal machine with public-key-only auth:

- There are no password attempts to detect and ban.
- The attack surface fail2ban is optimised for (password brute-forcing) does not exist here.
- fail2ban adds: a systemd service, a Python process, log-parsing rules, and firewall chain mutations.
- `MaxAuthTries = 3` + `LoginGraceTime = 30` achieve equivalent protection with zero extra services.

**Decision: omit fail2ban. It would be over-engineering for this threat model.**

---

## 5. ListenAddress Assessment

**Recommendation: Do NOT add `ListenAddress`.**

**Reasoning:**

On a personal workstation/laptop `ListenAddress` is fragile:

- IP addresses are assigned by DHCP and change across networks.
- Tailscale assigns addresses in the `100.64.0.0/10` range that can vary.
- Hardcoding any IP would break SSH entirely on network switches.

The existing configuration already handles network-level exposure appropriately:

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ ];   # SSH is implicitly opened by openssh.enable
  trustedInterfaces = [ "tailscale0" ];
};
```

The NixOS `services.openssh` module sets `openFirewall = true` by default, which opens TCP 22
via the system firewall. This is the correct NixOS-idiomatic pattern. `AllowUsers` provides the
user-level restriction; the firewall provides the network-level restriction.

If stronger interface binding were desired in future (e.g., Tailscale-only SSH), the correct
approach would be `services.openssh.listenAddresses` (a list of `{ addr; port; }` attrsets)
combined with `openFirewall = false` plus explicit firewall rules — but this is out of scope for
a personal machine and would be fragile without a static Tailscale IP.

**Decision: omit ListenAddress changes entirely.**

---

## 6. NixOS Option Name Verification

In NixOS ≥ 23.05, `services.openssh.settings` is declared as:

```
services.openssh.settings :: attrsOf (oneOf [ bool int str ])
```

It maps keys directly to `sshd_config` directives (one key-value pair per attribute).
NixOS generates `/etc/ssh/sshd_config` from this attrset at build time.

The following keys are all **valid `sshd_config` directives** accepted by OpenSSH and passed
through correctly by `services.openssh.settings`:

| NixOS attribute | sshd_config directive | Type | Valid |
|---|---|---|---|
| `AllowUsers` | `AllowUsers` | string (space-separated patterns) | ✅ Yes |
| `MaxAuthTries` | `MaxAuthTries` | integer | ✅ Yes |
| `LoginGraceTime` | `LoginGraceTime` | integer (seconds) | ✅ Yes |

References:
- `man sshd_config(5)` — `AllowUsers`, `MaxAuthTries`, `LoginGraceTime` are all documented directives.
- NixOS source: `nixos/modules/services/networking/ssh/sshd.nix` — `settings` is a free-form
  attrset of type `settingsFormat.type` generated via `pkgs.formats.keyValue {}`, so any valid
  sshd_config key is accepted.

**Important:** `AllowUsers` takes a **string** (space-separated user patterns), not a list.
Example: `AllowUsers = "nimda"` produces `AllowUsers nimda` in sshd_config. ✅

---

## 7. Proposed Changes — Justification Per Setting

### 7.1 `AllowUsers = "nimda"`

**Gap:** Without `AllowUsers`, any account that exists on the system (current or future) can
attempt SSH authentication. NixOS may create system users for services (e.g. if a new service
module is added later). This setting ensures only the named user can authenticate, providing a
second line of defence if a service account is accidentally given SSH keys.

**Justification:** Low complexity, zero runtime cost, strong defence-in-depth.  
**Do not use `AllowGroups = "wheel"`** — wheel membership is an administrative concern, not an
SSH access concern, and wheel membership should not implicitly grant SSH access to additional
future admin accounts.

### 7.2 `MaxAuthTries = 3`

**Gap:** The sshd default is `6`. With key-only auth, each "try" is one key offer. An attacker
with a large key collection can test 6 keys per TCP connection before being disconnected. Setting
this to `3` halves the per-connection probing window.

**Justification:** Reduces per-connection key probing surface. Standard CIS hardening
recommendation. No operational impact for legitimate users (a single correct key is tried once).

### 7.3 `LoginGraceTime = 30`

**Gap:** The sshd default is `120` seconds. An unauthenticated connection holds a process slot
for up to 2 minutes. An attacker opening many connections can exhaust sshd process limits.
Setting this to `30` seconds reduces the hold time by 75 %.

**Justification:** Reduces connection-exhaustion window. Recommended by CIS OpenSSH Benchmark
(Level 1). No operational impact — legitimate key-auth completes in under 2 seconds.

---

## 8. Settings Intentionally Unchanged

| Setting | Reason |
|---|---|
| `PermitRootLogin = "no"` | Already correct — do not touch |
| `PasswordAuthentication = false` | Already correct — do not touch |
| `KbdInteractiveAuthentication = false` | Already correct — do not touch |
| `ListenAddress` | Fragile on DHCP/Tailscale — do not add |
| `fail2ban` | Unnecessary with key-only auth + MaxAuthTries — do not add |

---

## 9. Files to be Modified

| File | Change |
|---|---|
| `modules/system.nix` | Add three settings to `services.openssh.settings` |

No other files require modification.

---

## 10. Complete Updated `services.openssh` Block

This is the **exact Nix code** the implementation subagent must produce in `modules/system.nix`,
replacing the current `services.openssh` block verbatim:

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
    # Defence-in-depth: restrict SSH to the sole human user.
    # Prevents any future system/service account from attempting auth.
    AllowUsers = "nimda";
    # Limit the number of authentication attempts per connection (default: 6).
    # Reduces per-connection key-exhaustion probing surface.
    MaxAuthTries = 3;
    # Disconnect unauthenticated connections after 30 s (default: 120 s).
    # Reduces connection-exhaustion window without affecting legitimate use.
    LoginGraceTime = 30;
  };
};
```

---

## 11. Implementation Constraints

- The implementation subagent MUST:
  - Replace only the `services.openssh` block — nothing else in `system.nix` should change.
  - Preserve all existing comments verbatim inside the block.
  - Add the three new settings after `KbdInteractiveAuthentication`, with the comments shown above.
  - NOT modify `modules/users.nix`, `hosts/default/configuration.nix`, or any other file.

- The implementation subagent MUST NOT:
  - Add fail2ban.
  - Add ListenAddress.
  - Change PasswordAuthentication, PermitRootLogin, or KbdInteractiveAuthentication.
  - Add `openFirewall = false` or any firewall changes.

---

## 12. Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| `AllowUsers` blocks a legitimate account | Very Low | Only one human user exists; service accounts do not need SSH |
| `MaxAuthTries = 3` causes auth failure for user with many keys loaded in ssh-agent | Low | sshd counts offers — 3 is sufficient for any normal key setup; user can use `IdentitiesOnly yes` in `~/.ssh/config` |
| `LoginGraceTime = 30` too short | Very Low | Key auth completes in <2 s; 30 s is 15× the typical latency |
| Build break | Very Low | All three are valid sshd_config keys; NixOS passes them through unchanged |

---

## 13. Summary

**Finding M-04 is a real gap.**  
The fix is minimal, correct, and non-breaking:

- Add **3 lines** to `services.openssh.settings` in `modules/system.nix`.
- No new packages, no new services, no new modules.
- `fail2ban` is explicitly **not recommended** for this threat model.
- `ListenAddress` restriction is explicitly **not recommended** for a laptop/workstation.

**Spec file:** `.github/docs/subagent_docs/SEC_M04_ssh_hardening_spec.md`  
**Files to modify:** `modules/system.nix` (only)
