# BUG-05 through BUG-09 — Medium-Severity Combined Implementation Specification

**Date:** 2026-03-19  
**Scope:** `modules/gnome.nix`, `flake.nix`, `modules/system.nix`, `scripts/preflight.sh`, `hosts/default/configuration.nix`  
**Status:** Specification — awaiting implementation

---

## Summary

| Bug ID | File | Category | Action |
|--------|------|----------|--------|
| BUG-05 | `modules/gnome.nix` | Duplication | Remove duplicate `gnomeExtensions.appindicator` entry |
| BUG-06 | `flake.nix` | Dependency hygiene | Add clarifying comment; no `follows` possible (nix-flatpak has no inputs) |
| BUG-07 | `modules/system.nix` | Security | Change `map to guest = bad user` → `never` |
| BUG-08 | `scripts/preflight.sh` | Shell injection / correctness | Replace `eval "$EVAL_CMD"` pattern with direct invocation |
| BUG-09 | `hosts/default/configuration.nix` | Redundancy | Remove manual `tailscale` from `systemPackages` |

---

## BUG-05 — Duplicate `gnomeExtensions.appindicator`

### Current Code

**File:** `modules/gnome.nix`, lines 29–46

```nix
environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
    gnomeExtensions.appindicator          # ← first occurrence (line 33)
    gnomeExtensions.dash-to-dock
    gnomeExtensions.alphabetical-app-grid
    gnomeExtensions.gamemode-shell-extension
    gnomeExtensions.gnome-40-ui-improvements
    gnomeExtensions.nothing-to-say
    gnomeExtensions.steal-my-focus-window
    gnomeExtensions.tailscale-status
    gnomeExtensions.caffeine
    gnomeExtensions.restart-to
    gnomeExtensions.blur-my-shell
    gnomeExtensions.appindicator          # ← second occurrence (line 45) — BUG
    gnomeExtensions.background-logo
    gnome-boxes
  ];
```

### Problem

Nix deduplicates list entries by store path at evaluation time, so the duplicate
causes no build failure today. However:

1. It is a copy-paste error that obscures the true package list.
2. If `gnomeExtensions.appindicator` is ever versioned independently (e.g. via an
   overlay or explicit version pin), Nix's deduplication would silently pick one
   copy, masking the inconsistency.
3. Code reviewers and future maintainers will assume an intentional difference
   that does not exist.

### Proposed Fix

Remove the second occurrence of `gnomeExtensions.appindicator` (line 45).

**Exact replacement — remove this line:**
```nix
    gnomeExtensions.appindicator          # (second copy, between blur-my-shell and background-logo)
```

**Result — the list reads:**
```nix
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
    gnomeExtensions.alphabetical-app-grid
    gnomeExtensions.gamemode-shell-extension
    gnomeExtensions.gnome-40-ui-improvements
    gnomeExtensions.nothing-to-say
    gnomeExtensions.steal-my-focus-window
    gnomeExtensions.tailscale-status
    gnomeExtensions.caffeine
    gnomeExtensions.restart-to
    gnomeExtensions.blur-my-shell
    gnomeExtensions.background-logo
    gnome-boxes
  ];
```

### Files to Change

- `modules/gnome.nix`

### Verification

```bash
grep -c 'gnomeExtensions.appindicator' modules/gnome.nix
# Expected output: 1
nix --extra-experimental-features 'nix-command flakes' flake check
```

---

## BUG-06 — `nix-flatpak` missing `inputs.nixpkgs.follows`

### Research Finding (Context7 + Direct Source Inspection)

**Source inspected:** `https://raw.githubusercontent.com/gmodena/nix-flatpak/main/flake.nix`

```nix
{
  description = "Manage flatpak apps declaratively.";

  outputs = _:
    {
      nixosModules = { nix-flatpak = ./modules/nixos.nix; };
      homeManagerModules = { nix-flatpak = ./modules/home-manager.nix; };
    };
}
```

**Finding:** `nix-flatpak` declares **no inputs whatsoever**. The `outputs` function
takes `_` (ignored). It is pure Nix module code with no nixpkgs dependency in the
flake graph. Therefore:

- There is **no separate nixpkgs tree** being fetched by nix-flatpak.
- Adding `inputs.nixpkgs.follows = "nixpkgs"` to the `nix-flatpak` input block in
  VexOS's `flake.nix` would be **silently ignored** by Nix — Nix only applies
  `follows` overrides to inputs that actually exist in the target flake's `inputs`
  attrset.
- The original bug hypothesis (extra nixpkgs fetch due to missing `follows`) is
  **incorrect** for this specific flake.

The `nix-cachyos-kernel` input already has an explicit comment noting it must NOT
override nixpkgs. The same category of comment is warranted for `nix-flatpak` so
maintainers understand the omission is intentional.

### Current Code

**File:** `flake.nix`, lines 21–23

```nix
    # Declarative Flatpak management
    # Provides: nixosModules.nix-flatpak, homeManagerModules.nix-flatpak
    nix-flatpak.url = "github:gmodena/nix-flatpak";
```

### Problem

The absence of a `follows` line — while technically harmless — is visually
inconsistent with the rest of the file and will trigger "why no follows?" questions
on every future review. Without a comment, a developer will add `follows` thinking
it is safe, which is a no-op and misleading.

### Proposed Fix

Add an inline comment documenting why `follows` is omitted:

```nix
    # Declarative Flatpak management
    # Provides: nixosModules.nix-flatpak, homeManagerModules.nix-flatpak
    # No inputs.nixpkgs.follows — nix-flatpak has no inputs in its flake
    # (outputs = _: { ... }); adding follows would be silently ignored.
    nix-flatpak.url = "github:gmodena/nix-flatpak";
```

### Files to Change

- `flake.nix`

### Verification

```bash
# Confirm nix-flatpak has no separate nixpkgs in the lock file
grep -A3 '"nix-flatpak"' flake.lock
# Should show no "nixpkgs" node referenced under nix-flatpak
nix --extra-experimental-features 'nix-command flakes' flake check
```

---

## BUG-07 — Samba `map to guest = bad user` silent auth fallback

### Research: Samba `map to guest` Directive

The `map to guest` global parameter controls what Samba does when authentication fails:

| Value | Behaviour |
|-------|-----------|
| `never` | Authentication failure always returns `NT_STATUS_LOGON_FAILURE`. Guest access is never granted on a failed login. **Explicit and secure.** |
| `bad user` | If the supplied username does not exist in the Unix password database, the connection is treated as guest. A known username with the wrong password still fails normally. |
| `bad password` | Any authentication failure — unknown username OR wrong password for a known user — is mapped to guest. Most permissive; effectively disables authentication for all shares that allow guests. |

Source: Samba documentation (`man smb.conf`, `map to guest` parameter).

**Why `bad user` is a logic trap here:**

- The current `public` share has `"guest ok" = "no"`, which prevents guest sessions
  from accessing it. The combination *appears* safe today.
- However, `map to guest = bad user` is a **global** setting. Any future share added
  to this configuration (even accidentally, without `"guest ok" = "no"`) will be
  transparently accessible to any connection that supplies an unknown username,
  because Samba will silently reclassify the failed login as an authenticated guest.
- The correct secure default is `never`: authentication failures should always return
  an explicit error. Shares that genuinely need guest access should opt-in via
  `"guest ok" = "yes"` — guest access via `map to guest` is an implicit default that
  is easy to forget.

### Current Code

**File:** `modules/system.nix`, lines 63–76 (global Samba settings block)

```nix
      global = {
        workgroup = "WORKGROUP";
        "server string" = "VexOS Samba Server";
        "netbios name" = "vexos";
        security = "user";
        "hosts allow" = "192.168. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";    # ← BUG
      };
```

### Problem

`map to guest = bad user` means any connection using a username that does not exist
in the Samba/Unix user database is transparently authenticated as `nobody`. This is a
security footgun: future shares without an explicit `"guest ok" = "no"` will be
silently world-readable.

### Proposed Fix

Change `"map to guest"` from `"bad user"` to `"never"`:

```nix
      global = {
        workgroup = "WORKGROUP";
        "server string" = "VexOS Samba Server";
        "netbios name" = "vexos";
        security = "user";
        "hosts allow" = "192.168. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        # "never" ensures authentication failures always return NT_STATUS_LOGON_FAILURE.
        # Shares that need guest access must explicitly set "guest ok" = "yes".
        "map to guest" = "never";
      };
```

The `"guest account" = "nobody"` line can be retained (it specifies which Unix
account is used if guest access is ever explicitly enabled on a share) or removed
since `never` makes it unreachable. Retaining it is safer for clarity.

### Files to Change

- `modules/system.nix`

### Verification

```bash
# After rebuild, confirm testparm output
sudo testparm -s 2>/dev/null | grep 'map to guest'
# Expected: map to guest = Never

# Attempt connection with unknown user — should receive access denied, not guest
smbclient //localhost/public -U nonexistent_user%wrongpass 2>&1 | grep -i 'denied\|logon'
```

---

## BUG-08 — `eval` used for shell command construction in `scripts/preflight.sh`

### Research: Safe Bash pattern to replace `eval` for commands with quoted arguments

The danger with `eval "$VAR"` is that the shell re-parses the entire string,
including any shell metacharacters embedded in variable values. Even with trusted
content, it is fragile: a single-quote in a flake attribute path, a branch name, or
a `--apply` expression would silently alter command parsing.

The correct pattern is **direct invocation** — call the command with its arguments
directly, using bash quoting to pass strings with spaces, rather than building and
evaluating a string. The single quotes in `'nix-command flakes'` are normal bash
quoting for a space-containing string; they work identically whether written inline
or stored differently.

Additionally, the `|| true` on the `eval` line explicitly suppresses the exit code,
bypassing `set -euo pipefail`. The correct approach is to capture the failure case
explicitly with `|| VAR=""` (or similar), which preserves pipefail semantics without
swallowing unrelated errors.

### Current Code

**File:** `scripts/preflight.sh`, lines 32–47 (Steps 2 and 2b)

```bash
# ── Step 2: Configuration evaluation ─────────────────────────────────────────
echo ""
echo "==> Step 2: NixOS configuration evaluation"
EVAL_CMD="nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf"
RESULT=$(eval "$EVAL_CMD" 2>&1) || true
if echo "$RESULT" | grep -qE '"string"|"set"'; then
  pass "Configuration evaluation (.#nixosConfigurations.vexos)"
else
  fail "Configuration evaluation failed"
  info "$RESULT"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2b: Verify lib.mkVexosSystem is exported ────────────────────────────
echo ""
echo "==> Step 2b: Verify lib.mkVexosSystem output"
LIB_CMD="nix --extra-experimental-features 'nix-command flakes' eval .#lib.mkVexosSystem --apply builtins.typeOf"
LIB_RESULT=$(eval "$LIB_CMD" 2>&1) || true
if echo "$LIB_RESULT" | grep -q '"lambda"'; then
  pass "lib.mkVexosSystem is exported and is a function"
else
  fail "lib.mkVexosSystem is missing or not a function"
  info "$LIB_RESULT"
  ERRORS=$((ERRORS + 1))
fi
```

### Problem

1. **Injection risk:** `EVAL_CMD` is a string containing shell metacharacters
   (single quotes). If any portion of the command (e.g. a flake URL, attribute
   path, or `--apply` expression) ever contains user-controlled or dynamically
   constructed content, the `eval` would execute unintended shell commands.
   Even with static content, `eval` is an anti-pattern that invites future
   injection vulnerabilities.

2. **`set -euo pipefail` bypass:** `|| true` discards the exit code of the `eval`
   command entirely. Any error — even an unrelated one (e.g. `nix` binary not
   found, env corruption) — is silently swallowed. The intent was to capture
   failure output for reporting, but `|| true` does so too broadly.

### Proposed Fix

Delete the `EVAL_CMD` / `LIB_CMD` string variables entirely. Invoke `nix` directly
with inline bash quoting. Replace `|| true` with `|| RESULT=""` / `|| LIB_RESULT=""`
to preserve `set -euo pipefail` semantics while still capturing graceful failure:

```bash
# ── Step 2: Configuration evaluation ─────────────────────────────────────────
echo ""
echo "==> Step 2: NixOS configuration evaluation"
RESULT=$(nix --extra-experimental-features 'nix-command flakes' \
  eval .#nixosConfigurations.vexos.config.system.build.toplevel \
  --apply builtins.typeOf 2>&1) || RESULT=""
if echo "$RESULT" | grep -qE '"string"|"set"'; then
  pass "Configuration evaluation (.#nixosConfigurations.vexos)"
else
  fail "Configuration evaluation failed"
  info "$RESULT"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2b: Verify lib.mkVexosSystem is exported ────────────────────────────
echo ""
echo "==> Step 2b: Verify lib.mkVexosSystem output"
LIB_RESULT=$(nix --extra-experimental-features 'nix-command flakes' \
  eval .#lib.mkVexosSystem \
  --apply builtins.typeOf 2>&1) || LIB_RESULT=""
if echo "$LIB_RESULT" | grep -q '"lambda"'; then
  pass "lib.mkVexosSystem is exported and is a function"
else
  fail "lib.mkVexosSystem is missing or not a function"
  info "$LIB_RESULT"
  ERRORS=$((ERRORS + 1))
fi
```

**Why `|| RESULT=""` is safe:**
- If the `nix eval` command itself exits non-zero (e.g. eval error), `RESULT` is set
  to empty string and execution continues to the `grep` check, which will fail and
  increment `ERRORS`. This is the correct behaviour.
- Unlike `|| true`, this does not suppress unrelated errors from the command
  substitution subshell (syntax errors, missing binary, etc.) — those paths don't
  produce a non-zero exit from the assignment with `||`.

### Files to Change

- `scripts/preflight.sh`

### Verification

```bash
bash -n scripts/preflight.sh          # syntax check
shellcheck scripts/preflight.sh       # static analysis (should pass with no eval warnings)
bash scripts/preflight.sh             # functional run
# Confirm no 'eval' remains in the script:
grep -n 'eval' scripts/preflight.sh
# Expected: no output (no eval calls)
```

---

## BUG-09 — Redundant `tailscale` in `environment.systemPackages`

### Current Code

**File:** `hosts/default/configuration.nix`, lines 73–80 (systemPackages block)

```nix
  # System packages
  environment.systemPackages = with pkgs; [
    wget
    git
    curl
    htop
    firefox
    tailscale        # ← BUG: redundant
    cifs-utils  # For mounting SMB shares
  ];
```

**File:** `modules/system.nix`, line 47

```nix
  # Enable Tailscale VPN
  services.tailscale.enable = true;
```

### Problem

`services.tailscale.enable = true` (in `modules/system.nix`) already:
- Installs the `tailscale` package into the system closure.
- Sets up and enables the `tailscaled` systemd service.
- Manages the package version in lockstep with the NixOS module.

The explicit `tailscale` entry in `environment.systemPackages` is a redundant
second declaration. While Nix deduplicates it silently today, it creates a
maintenance hazard:

1. If `services.tailscale` is ever disabled (e.g. switching to a different VPN),
   the `tailscale` CLI binary would remain installed via `systemPackages`, giving
   false confidence that Tailscale is still active.
2. It obscures the convention: NixOS service modules own their packages. Adding
   service packages manually to `systemPackages` implies they are not managed by
   a service, which is incorrect here.
3. Version tracking: `services.tailscale` controls the package version via the
   NixOS module system. A manual `systemPackages` entry bypasses this tracking
   path.

### Proposed Fix

Remove `tailscale` from `environment.systemPackages` in
`hosts/default/configuration.nix`:

```nix
  # System packages
  environment.systemPackages = with pkgs; [
    wget
    git
    curl
    htop
    firefox
    cifs-utils  # For mounting SMB shares
  ];
```

### Files to Change

- `hosts/default/configuration.nix`

### Verification

```bash
# Confirm tailscale is still available after rebuild (provided by services.tailscale)
which tailscale           # should resolve to /run/current-system/sw/bin/tailscale
systemctl status tailscaled   # service still present and managed

# Confirm it is no longer listed manually in configuration
grep 'tailscale' hosts/default/configuration.nix
# Expected: no output (no manual systemPackages entry)
# services.tailscale.enable is in modules/system.nix, not here

nix --extra-experimental-features 'nix-command flakes' flake check
```

---

## Implementation Order

Apply fixes in this order to allow incremental verification:

1. **BUG-09** — trivial one-line removal, no logic change.
2. **BUG-05** — trivial one-line removal, no logic change.
3. **BUG-06** — comment-only change to `flake.nix`.
4. **BUG-07** — single value change in `modules/system.nix`; verify Samba restarts cleanly.
5. **BUG-08** — multi-line refactor in `scripts/preflight.sh`; run `bash -n` and `shellcheck` after.

Run `nix flake check` after each change.

---

## Risk Assessment

| Bug ID | Risk of Fix | Notes |
|--------|-------------|-------|
| BUG-05 | None | Deduplication means removing the copy has no functional effect. |
| BUG-06 | None | Comment-only change. |
| BUG-07 | Low — service restart | Samba will restart with new config. Existing authenticated sessions reconnect normally. No impact on the `public` share since `"guest ok" = "no"` is already set. |
| BUG-08 | Low — shell refactor | Functionally equivalent output; `|| RESULT=""` pattern tested against same nix eval calls. |
| BUG-09 | None | Package remains installed via `services.tailscale`. |

---

## Spec Path

`/home/nimda/Projects/vex-nix/.github/docs/subagent_docs/BUG05_09_medium_spec.md`
