# BUG-01 Security Specification: SSH Password Authentication + Weak Default Password

**Severity:** Critical  
**Affected Files:** `modules/system.nix`, `modules/users.nix`, `scripts/install.sh`  
**NixOS Target:** 25.11 (nixos-25.11 channel, as declared in `flake.nix`)  
**Date:** 2026-03-19  

---

## 1. Current Configuration Analysis

### 1.1 `modules/system.nix` — SSH Service

```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;  # Set to false and use keys for better security
  };
};
```

- `PasswordAuthentication = true` — password-based SSH login is **enabled**.  
  The in-line comment acknowledges this is insecure but takes no action.
- `KbdInteractiveAuthentication` is **not set**, defaulting to `true` in NixOS 25.11.  
  `KbdInteractiveAuthentication` is an alternative interactive password challenge path  
  that bypasses `PasswordAuthentication = false` on some OpenSSH versions; both must  
  be disabled to fully close password login over SSH.
- `PermitRootLogin = "no"` — correctly set. Root SSH is disabled.
- No `AllowUsers` restriction — any system user can attempt SSH authentication.
- SSH listens on the default port 22, which is exposed to any host that can reach the machine  
  (the firewall opens the port automatically when `services.openssh.enable = true`).

### 1.2 `modules/users.nix` — User Account

```nix
users.users.nimda = {
  isNormalUser = true;
  extraGroups = [ "networkmanager" "wheel" "audio" "video" "docker" "libvirtd" "gamemode" ];
  shell = pkgs.bash;
  initialPassword = "changeme";
};
```

- `initialPassword = "changeme"` sets a plaintext password that is compiled into the Nix  
  derivation and therefore visible in the **world-readable Nix store** (`/nix/store/…`).
- The user `nimda` is in the `wheel` group and `security.sudo.wheelNeedsPassword = true` is set,  
  so knowing the password grants full `sudo` escalation.
- `initialPassword` is intentionally a low-security bootstrap mechanism for first-boot only.  
  Its presence in a **publicly published GitHub repository** makes the password globally known.

### 1.3 `hosts/default/configuration.nix` — Host Module Imports

Both `modules/system.nix` and `modules/users.nix` are imported unconditionally for every host.  
No host-level override disables SSH password auth or replaces the default password.

### 1.4 `flake.nix` — Distribution Model

The flake exposes `lib.mkVexosSystem`, which is consumed by a thin `/etc/nixos/flake.nix`  
pointing at `github:VictoryTek/vex-nix`. This means the vulnerable configuration is  
**publicly available and applied verbatim to any machine that runs `install.sh`**.

### 1.5 `scripts/install.sh` — Install Flow

The install script:
1. Writes `/etc/nixos/flake.nix` pointing at the GitHub repository.
2. Initialises a git repo in `/etc/nixos/`.
3. Runs `nix flake update` to pin the revision.
4. Prints the `nixos-rebuild switch` command.
5. **Does NOT instruct the user to change the default password.**
6. **Does NOT instruct the user to configure SSH public keys.**
7. **Does NOT warn that SSH password auth is enabled with a known password.**

There is no mention of `passwd`, SSH key setup, or post-install hardening anywhere in the script.

---

## 2. Problem Definition

### 2.1 Attack Scenario

An attacker who can reach TCP port 22 on a VexOS machine can:

1. Attempt `ssh nimda@<target>` with password `changeme`.
2. Log in successfully because `PasswordAuthentication = true` and `initialPassword = "changeme"`.
3. Run `sudo -s` (password: `changeme`) and obtain a root shell.
4. Gain unlimited persistence: install backdoors, exfiltrate data, pivot via Tailscale or Samba.

This attack requires **zero exploits** — it is pure credential abuse using publicly known defaults.

### 2.2 Why `initialPassword` in a Published Repo Is Never Safe

- `initialPassword` compiles the plaintext secret into the Nix derivation.  
  The derivation path in `/nix/store/` is world-readable by all local users.
- Any machine that applies this flake inherits the same globally-known password.
- Even if a user runs `passwd nimda` after first boot, the `initialPassword` remains in  
  the Nix store for the lifetime of that generation.
- The NixOS manual explicitly recommends `hashedPasswordFile` (backed by `sops-nix` or  
  `agenix`) for passwords that must be in the configuration, or relying solely on  
  `openssh.authorizedKeys.keys` and removing `initialPassword` entirely.

### 2.3 Compounding Factors

| Factor | Risk Added |
|--------|-----------|
| `nimda` is in `wheel` | Password login → immediate root via sudo |
| Tailscale enabled | Machine is reachable from Tailscale network; attacker on the tailnet can exploit this |
| Samba enabled | Attacker can also mount shares after gaining credentials |
| Docker group | Container escape is trivially achievable post-compromise |
| Published on GitHub | Password is known before the machine is even installed |

---

## 3. Proposed Solution

### 3.1 Strategy Overview

The fix has two independent objectives that reinforce each other:

- **Objective A**: Prevent SSH password login regardless of what password is set.  
  → Disable `PasswordAuthentication` and `KbdInteractiveAuthentication`.

- **Objective B**: Remove the publicly-known `initialPassword` from the published module.  
  → Drop `initialPassword`; require the operator to set a password or SSH key before/during install.

These are orthogonal: if only A is applied, SSH is safe but the local console is still  
accessible with the known password. If only B is applied, first-boot is broken without  
guidance. Both must be addressed.

### 3.2 Change: `modules/system.nix`

**Current:**
```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;  # Set to false and use keys for better security
  };
};
```

**Proposed:**
```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    # Password-based SSH login is disabled. Authenticate with an SSH public key.
    # Add your public key to modules/users.nix:
    #   users.users.nimda.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };
};
```

**Rationale:**
- `PasswordAuthentication = false` — disables standard password login over SSH.
- `KbdInteractiveAuthentication = false` — disables the PAM keyboard-interactive challenge  
  path that can serve as a second route for password-based auth when  
  `PasswordAuthentication` is false. Both settings are required per the NixOS wiki  
  (source: https://wiki.nixos.org/wiki/SSH_public_key_authentication).
- The comment guides operators to the correct next step (adding an authorized key).
- `PermitRootLogin = "no"` — already correct; no change needed.

### 3.3 Change: `modules/users.nix`

The decision between four options:

| Option | Security | First-Boot UX | Suitable for Published Repo |
|--------|----------|--------------|---------------------------|
| Keep `initialPassword = "changeme"` | Critically insecure | Easy | **No** |
| Replace with `initialPassword = "..."` (stronger) | Still leaks via Nix store | Easy | **No** |
| Replace with `hashedPassword = "..."` | Hash is public; brute-forceable offline | Moderate | **No** |
| Remove `initialPassword`; add `openssh.authorizedKeys.keys` placeholder | Secure | Requires operator action | **Yes** |
| `hashedPasswordFile = "/run/secrets/nimda-password"` (sops/agenix) | Strongest | Complex setup | Yes (advanced) |

**Recommendation: Option 4** — Remove `initialPassword` entirely. Add an empty  
`openssh.authorizedKeys.keys` list with a prominent comment directing operators to  
populate it before using SSH. The install script handles the remaining first-boot concern  
(see §3.4).

**Current:**
```nix
# Initial password - CHANGE THIS AFTER FIRST LOGIN
# Use: passwd
# Or set hashedPassword instead of initialPassword
initialPassword = "changeme";
```

**Proposed:**
```nix
# ── Authentication ─────────────────────────────────────────────────────────
# No default password is set. Before or immediately after first boot, run:
#   passwd nimda
# from the physical console or a pre-existing root session.
#
# For SSH access, add your public key(s) here and rebuild:
#   openssh.authorizedKeys.keys = [
#     "ssh-ed25519 AAAA... user@host"
#   ];
# SSH password authentication is disabled in modules/system.nix.
```

**Note on first-boot TTY login:**  
Removing `initialPassword` does **not** lock the console — NixOS will let the user log in  
via the physical (or VM serial/VGA) console and set a password with `passwd`. The installer  
runs on a physical machine (install.sh requires root on the target), so there is always  
physical console access available for first boot. The install script must communicate this  
clearly (see §3.4).

### 3.4 Change: `scripts/install.sh` — Post-Install Guidance

Add a **Security Checklist** section to the install summary printed at the end of the script,  
immediately after the existing "To activate the configuration, run:" block.

**Proposed addition** (after the final `nixos-rebuild` command block at the bottom of the script):

```bash
# ── Security checklist ────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}  Security Checklist — Complete Before      ${NC}"
echo -e "${YELLOW}  Connecting This Machine to a Network      ${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""
echo "  1. Set a strong password for nimda from the local console:"
echo ""
echo -e "     ${BLUE}passwd nimda${NC}"
echo ""
echo "  2. Add your SSH public key to modules/users.nix:"
echo ""
echo "     users.users.nimda.openssh.authorizedKeys.keys = ["
echo '       "ssh-ed25519 AAAA... you@host"'
echo "     ];"
echo ""
echo "     Then rebuild: sudo nixos-rebuild switch --flake /etc/nixos#${HOSTNAME}"
echo ""
echo "  3. SSH password authentication is DISABLED by default."
echo "     Key-based authentication is required for remote access."
echo ""
echo -e "${RED}  WARNING: Do NOT skip steps 1-2 before exposing port 22.${NC}"
echo ""
```

---

## 4. Implementation Steps

Ordered list with exact file-level detail:

### Step 1 — `modules/system.nix`

**Location:** Lines ~38–44 (the `services.openssh.settings` block)

1. Change `PasswordAuthentication = true;` → `PasswordAuthentication = false;`
2. Delete the inline comment `# Set to false and use keys for better security`
3. Add `KbdInteractiveAuthentication = false;` on the next line
4. Add a multi-line block comment above `/settings` explaining the auth policy  
   and directing operators to `openssh.authorizedKeys.keys` in `modules/users.nix`

### Step 2 — `modules/users.nix`

**Location:** Lines ~20–23 (the `initialPassword` block)

1. Delete the three comment lines and `initialPassword = "changeme";`
2. Insert the replacement comment block describing how to set a password (`passwd nimda`)  
   and how to add SSH authorized keys declaratively
3. Do **not** add a placeholder `openssh.authorizedKeys.keys = []` — an empty list  
   in a published file could cause confusion versus a clear instructional comment.

### Step 3 — `scripts/install.sh`

**Location:** After the final `echo ""` at the end of the `──  Summary ──` block  
(currently the last lines of the file)

1. Insert the Security Checklist `echo` block defined in §3.4
2. Ensure the new block is inside the existing `# ── Summary ──` section so it  
   is printed unconditionally (dry-run and real runs both display the checklist)

---

## 5. Ripple Effects

| File | Impact |
|------|--------|
| `modules/system.nix` | Direct change — SSH settings |
| `modules/users.nix` | Direct change — remove `initialPassword` |
| `scripts/install.sh` | Direct change — add security checklist to output |
| `hosts/default/configuration.nix` | **No change needed** — imports unchanged modules |
| `flake.nix` | **No change needed** — module list unchanged |
| `home/default.nix` | **No change needed** — home-manager config unaffected |
| `README.md` | **Should be updated** — add a "First-Boot Setup" section documenting  the `passwd` + SSH key workflow (outside this spec's scope; treat as a follow-up) |

---

## 6. Verification Steps

### 6.1 Nix Evaluation

```bash
# 1. Flake syntax and evaluation
nix flake check

# 2. Confirm toplevel builds
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf

# 3. Inspect rendered SSH config in the Nix closure
nix eval .#nixosConfigurations.vexos.config.services.openssh.settings
# Expected output: { KbdInteractiveAuthentication = false; PasswordAuthentication = false; PermitRootLogin = "no"; }

# 4. Confirm initialPassword is absent
nix eval .#nixosConfigurations.vexos.config.users.users.nimda.initialPassword 2>&1
# Expected: error (option not set / null)
```

### 6.2 Runtime Verification (on a test VM)

```bash
# After nixos-rebuild switch:

# a) Confirm sshd_config is correct
grep -E 'PasswordAuthentication|KbdInteractiveAuthentication' /etc/ssh/sshd_config
# Expected:
#   PasswordAuthentication no
#   KbdInteractiveAuthentication no

# b) Attempt password login (should fail)
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no nimda@localhost
# Expected: "Permission denied (publickey)"

# c) Confirm no shadow entry exists for nimda (no initialPassword)
sudo getent shadow nimda | cut -d: -f2
# Expected: "!" or empty (locked/no password set)

# d) Confirm key login works (after adding a test key)
ssh -i ~/.ssh/test_key nimda@localhost
# Expected: successful login
```

### 6.3 Preflight Script

```bash
bash scripts/preflight.sh
# Expected: exit 0, all checks pass
```

---

## 7. Risks and Mitigations

### Risk 1: First-Boot Lockout

**Scenario:** Operator installs VexOS, runs `nixos-rebuild switch`, system reboots.  
Because `initialPassword` is removed, `nimda` has no password and cannot log in.

**Likelihood:** High — this will happen to every new installer who does not read the security checklist.

**Mitigations:**
- `scripts/install.sh` security checklist (§3.4) explicitly instructs running `passwd nimda`  
  **before** rebooting or disconnecting the install session.
- The install script already requires `sudo` / root access, which means the  
  operator has a root shell open at the time the instructions are displayed.  
  Running `passwd nimda` at that moment takes ~10 seconds.
- Physical console access is always available for recovery (`nixos-enter` from live ISO  
  or direct console login as root).

### Risk 2: SSH Lockout After Disabling Password Auth

**Scenario:** Operator has an existing VexOS install that uses password SSH.  
After applying `PasswordAuthentication = false` without adding an authorized key,  
they lose remote access.

**Likelihood:** Medium — affects existing installs that are upgrading via `nix flake update`.

**Mitigations:**
- Add an explicit upgrade note in the commit message and README warning existing users  
  to add their SSH public key **before** rebuilding.
- The security checklist in `install.sh` and the comment in `users.nix` both direct  
  operators to `openssh.authorizedKeys.keys`.
- Physical console or Tailscale (if already configured and the operator has another device  
  on the tailnet) provides a recovery path.

### Risk 3: `initialPassword` Removal Breaks Automated VM Tests

**Scenario:** Any NixOS VM test or CI job that boots VexOS and logs in with the  
default password will break.

**Likelihood:** Low — no automated VM tests exist in this repository.

**Mitigation:** If VM tests are added in future, they should use  
`users.users.nimda.initialHashedPassword = "$y$..."` (the NixOS test hash convention)  
scoped to the test module only, never in the shared production module.

### Risk 4: `hashedPassword` vs. `initialPassword` Confusion

**Scenario:** A future contributor re-adds `initialPassword` believing it is safe because  
the value is "just a hash."

**Likelihood:** Low but meaningful in a shared repo.

**Mitigation:** The comment block in `users.nix` should explain the difference:
- `initialPassword` — plaintext in Nix store, only applied on account creation
- `hashedPassword` — hash in Nix store (still world-readable; offline crackable)
- `hashedPasswordFile` — reads from a file NOT in version control; correct for secrets
- `openssh.authorizedKeys.keys` — no password needed at all for SSH

---

## 8. Sources and Documentation References

| Source | Topic | URL |
|--------|-------|-----|
| NixOS Wiki — SSH Public Key Auth | `PasswordAuthentication = false`, `KbdInteractiveAuthentication = false` pattern | https://wiki.nixos.org/wiki/SSH_public_key_authentication |
| NixOS Wiki — SSH | Full SSH hardening example with `AllowUsers`, custom port | https://wiki.nixos.org/wiki/SSH |
| NixOS Manual (unstable) | `services.openssh.enable`, `authorizedKeys.keys` canonical usage | https://nixos.org/manual/nixos/unstable/ |
| NixOS Wiki — User Management | `hashedPassword`, `initialPassword` semantics | https://wiki.nixos.org/wiki/User_management |
| NixOS Wiki — SSH on GCE | `openssh.authorizedKeys.keys` + wheel sudo pattern | https://wiki.nixos.org/wiki/Install_NixOS_on_GCE |
| OpenSSH `sshd_config(5)` | `KbdInteractiveAuthentication` bypass of `PasswordAuthentication` | https://man.openbsd.org/sshd_config |

---

## 9. Summary

**Two settings in combination create a critical, zero-exploit attack path:**  
`PasswordAuthentication = true` in `modules/system.nix` and  
`initialPassword = "changeme"` in `modules/users.nix` allow any network-reachable  
attacker to log in as `nimda` (a `wheel`/sudo user) using a publicly-known password.

**The fix has three components:**
1. Set `PasswordAuthentication = false` and add `KbdInteractiveAuthentication = false`  
   in `modules/system.nix`.
2. Remove `initialPassword = "changeme"` from `modules/users.nix` and replace with  
   clear instructional comments directing operators to set a password via `passwd`  
   and configure SSH keys via `openssh.authorizedKeys.keys`.
3. Add a Security Checklist to the tail of `scripts/install.sh` that explicitly  
   instructs `passwd nimda` and SSH key setup before network exposure.

**Primary risk of the fix** is first-boot lockout if the operator does not follow the  
checklist; this is mitigated by prominent install-time instructions and the fact that  
physical console access is always available on a fresh install.
