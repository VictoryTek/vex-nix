# BUG-04 Specification: Auto-Login Combined with Screen Lock Disabled

**Severity:** High  
**Category:** Physical Access / Authentication  
**Status:** Open — Awaiting Implementation  
**Affected Files:** `home/default.nix`, `modules/gnome.nix`

---

## 1. Current Configuration Analysis

### `modules/gnome.nix` — lines 13–14

```nix
# Auto-login — skips the GDM lock screen on boot
services.displayManager.autoLogin.enable = true;
services.displayManager.autoLogin.user = "nimda";
```

Auto-login instructs GDM to bypass the login screen on boot, depositing the
`nimda` user directly into a live GNOME session. This is a system-level NixOS
option that operates at the display manager layer, before the user session starts.

### `home/default.nix` — `dconf.settings` block

```nix
"org/gnome/desktop/screensaver" = {
  lock-enabled = false;
};
```

This dconf override is applied declaratively through Home Manager. It sets the
GSettings key `org.gnome.desktop.screensaver lock-enabled` to `false`, which
disables the GNOME screen lock entirely. When the display blanks or a screensaver
activates, GNOME will **not** prompt for a password to resume the session.

### `modules/users.nix` — privilege surface

User `nimda` holds the following groups:

```nix
extraGroups = [
  "networkmanager"
  "wheel"        # passwordless sudo via polkit
  "audio" "video"
  "libvirtd"
  "gamemode"
];
linger = true;   # user systemd services start at boot
```

---

## 2. Problem Definition

### The Attack Scenario

These two settings form a compound physical-access vulnerability:

1. **Boot** — GDM's `autoLogin` deposits the user into a live GNOME session
   without any credential challenge. The machine is "ready to use" immediately
   after power-on.

2. **Idle** — When the user walks away, the display blanks after an inactivity
   timeout. Because `lock-enabled = false`, **no password is required to
   resume**. Anyone who wakes the screen (keyboard press, mouse move) is
   immediately inside a fully authenticated session.

3. **Attack window** — An attacker with brief, opportunistic physical access
   (colleague, visitor, breach) gains immediate, unrestricted access to:

   | Asset | Consequence |
   |-------|-------------|
   | `wheel` group | `sudo` privilege → full root escalation without additional authentication |
   | SSH keys in `~/.ssh/` | Lateral movement to every host `nimda` has SSH access to |
   | Tailscale VPN (configured in `configuration.nix`) | Entry into any private Tailscale network |
   | Browser sessions (Brave) | Authenticated web sessions, saved passwords |
   | Entire `$HOME` | Source code, secrets, tokens, config files |
   | `libvirtd` access | Running VMs may be mounted or inspected |

Neither setting alone is necessarily a bug:
- **Auto-login** is a typical convenience for a personal single-user workstation
  where the threat model excludes walk-up attacks.
- **`lock-enabled = false`** might be used intentionally when a hardware lock
  is in place, or on a fully isolated kiosk.

**Together, with a high-privilege user, they eliminate all physical-access
authentication entirely.**

### Why This Matters for a Shared/Published Config

VexOS is not a single-person's private configuration. It is a published, shared
NixOS config consumed by downstream users. A downstream user who installs VexOS
may not inspect every dconf key before deploying it to their machine. They inherit
`lock-enabled = false` silently. That user's threat model may differ significantly
from the author's expected environment.

Publishing `lock-enabled = false` as a default is therefore a **supply-chain
security issue**: downstream users opt into a physical-access bypass without
knowing they have done so.

---

## 3. Research Findings

### 3.1 GNOME dconf Keys (Context7 verified, NixOS Wiki + Home Manager docs)

| GSettings Key | GVariant Type | Default | Function |
|---------------|--------------|---------|----------|
| `org.gnome.desktop.screensaver lock-enabled` | `b` (boolean) | `true` | Master switch: whether GNOME locks the session when the screensaver activates |
| `org.gnome.desktop.screensaver lock-delay` | `u` (uint32) | `0` | Seconds after screensaver starts before locking; 0 = lock immediately |
| `org.gnome.session idle-delay` | `u` (uint32) | `300` | Seconds of inactivity before screensaver activates (5 minutes) |

**`lock-enabled`** is the single most important key. GNOME's upstream default is
`true`. VexOS explicitly overrides it to `false`, which is the primary regression.

**GDM auto-login does NOT imply `lock-enabled = false`**. These are independent
settings at two different layers:
- `autoLogin` is a GDM display-manager option that affects the initial login flow.
- `lock-enabled` is a GNOME session/screensaver GSettings key that affects
  what happens when an already-established session idles.
  
Setting `lock-enabled = false` is an active, deliberate override. Removing it
(or changing it to `true`) does not change auto-login behavior.

### 3.2 Home Manager dconf API

Home Manager's `dconf.settings` is the correct declarative mechanism for setting
these values. As of Home Manager 24.11/25.05, there are **no higher-level
Home Manager options** specifically for GNOME screensaver lock settings; dconf is
the appropriate interface.

For GSettings keys typed `u` (uint32), Home Manager provides
`lib.hm.gvariant.mkUint32` to emit the correct GVariant type. Plain Nix integers
are treated as `i` (int32) by default and may cause a type-mismatch error when
the schema enforces `u`. The `lib` argument must be present in the Home Manager
module's function signature.

**Source:** Home Manager option docs via Context7 (`/websites/home-manager-options_extranix`),
NixOS Wiki GNOME article via Context7 (`/websites/wiki_nixos_wiki`).

### 3.3 Is `autoLogin` in Scope?

Three options were evaluated:

| Option | Description | Verdict |
|--------|-------------|---------|
| **A** | Keep auto-login; restore `lock-enabled = true` | **RECOMMENDED** |
| B | Remove auto-login entirely | More secure but breaks convenience without user consent |
| C | Keep both; add documentation only | Unacceptable — does not fix the vulnerability |

**Rationale for Option A:**

Auto-login is a legitimate UX preference that users can consciously choose. It
affects only the boot-up flow and can be disabled by any downstream user with a
single option. It is explicitly labelled in `gnome.nix` with a comment.

`lock-enabled = false`, in contrast, silently removes a security control that
GNOME ships **on by default**. It provides minimal UX benefit (saves one password
entry when waking the screen) and directly enables the physical-access attack
described above. There is no defensive argument for this override in a shared
config.

The correct fix is therefore: **remove the `lock-enabled = false` override**
(restoring GNOME's upstream default of `true`), plus add explicit declarative
values for `idle-delay` and `lock-delay` to make the lock behavior transparent
and auditable. Auto-login is preserved but paired with a functioning lock.

---

## 4. Recommended Fix

### Summary

- **Remove** `lock-enabled = false` from `home/default.nix`
- **Add** explicit `lock-enabled = true` in its place (documents intent)
- **Add** `lock-delay = lib.hm.gvariant.mkUint32 0` (lock immediately on screensaver)
- **Add** `org/gnome/session` block with `idle-delay = lib.hm.gvariant.mkUint32 300` (5 min idle)
- **Add** `lib` to the Home Manager module function arguments (required for gvariant helpers)
- **Add** a security comment block in `modules/gnome.nix` explaining the auto-login + lock trade-off

---

## 5. Implementation Steps

### 5.1 `home/default.nix`

**Step 1:** Add `lib` to the module arguments  
**Step 2:** Replace the `"org/gnome/desktop/screensaver"` dconf block  
**Step 3:** Add `"org/gnome/session"` dconf block

#### Step 1 — Module signature

**Current (`home/default.nix`, line 1):**
```nix
{ config, pkgs, pkgs-unstable, inputs, ... }:
```

**Replace with:**
```nix
{ config, lib, pkgs, pkgs-unstable, inputs, ... }:
```

`lib` is needed for `lib.hm.gvariant.mkUint32`.

---

#### Step 2 — Fix the screensaver dconf block

**Current (`home/default.nix`):**
```nix
    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
    };
```

**Replace with:**
```nix
    # BUG-04 fix: restore GNOME's default lock-on-idle behaviour.
    # lock-enabled = false + autoLogin = a physical-access bypass; never disable both.
    # lock-delay = 0 → lock fires immediately when the screensaver starts.
    "org/gnome/desktop/screensaver" = {
      lock-enabled = true;
      lock-delay   = lib.hm.gvariant.mkUint32 0;
    };
```

---

#### Step 3 — Add idle-delay key

Add a new dconf block immediately **after** the screensaver block (before the
`"org/gnome/desktop/app-folders"` block):

```nix
    # 5-minute idle timeout before the screensaver (and therefore lock) fires.
    # GSettings type is uint32; plain Nix integers would emit int32 and may mismatch.
    "org/gnome/session" = {
      idle-delay = lib.hm.gvariant.mkUint32 300;
    };
```

---

### 5.2 `modules/gnome.nix`

Add a security trade-off comment to the auto-login block (lines 12–14).

**Current:**
```nix
  # Auto-login — skips the GDM lock screen on boot
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "nimda";
```

**Replace with:**
```nix
  # Auto-login — skips the GDM lock screen on boot.
  #
  # SECURITY NOTE: auto-login is a convenience feature suitable for physically
  # secure single-user machines. It MUST be paired with an active screen lock
  # (org/gnome/desktop/screensaver lock-enabled = true in home/default.nix).
  # Combining auto-login with lock-enabled = false eliminates all physical-access
  # authentication and exposes the full session to anyone who can reach the
  # keyboard. To disable auto-login for higher-security deployments, set:
  #   services.displayManager.autoLogin.enable = false;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "nimda";
```

---

## 6. Ripple Effects

| File | Impact | Action |
|------|--------|--------|
| `home/default.nix` | Primary fix target | Modify as specified |
| `modules/gnome.nix` | Comment addition only | No functional change |
| `hosts/default/configuration.nix` | Imports `gnome.nix`; unaffected by comment | No change |
| `flake.nix` | No change | No change |
| `modules/users.nix` | No change needed (groups unchanged) | No change |

No new packages, modules, or flake inputs are required. The change is purely
declarative dconf value management.

---

## 7. Verification Steps

After running `sudo nixos-rebuild switch --flake .#vexos`:

### 7.1 GSettings confirmation (run as `nimda`)

```bash
# Should return: true
gsettings get org.gnome.desktop.screensaver lock-enabled

# Should return: uint32 0
gsettings get org.gnome.desktop.screensaver lock-delay

# Should return: uint32 300
gsettings get org.gnome.session idle-delay
```

### 7.2 dconf dump (raw confirmation)

```bash
dconf read /org/gnome/desktop/screensaver/lock-enabled   # → true
dconf read /org/gnome/desktop/screensaver/lock-delay     # → uint32 0
dconf read /org/gnome/session/idle-delay                 # → uint32 300
```

### 7.3 Functional test

1. Let the machine idle for 5+ minutes (or run `gnome-screensaver-command --activate`)
2. Confirm the lock screen appears immediately
3. Attempt to wake without entering a password — should be rejected
4. Enter `nimda`'s password — session should resume normally

### 7.4 Build validation

```bash
nix flake check
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf
```

Both commands must exit 0.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Severity | Mitigation |
|------|-----------|----------|------------|
| `lib.hm.gvariant.mkUint32` not in scope | Low | Build failure | Add `lib` to module args; confirmed available in Home Manager |
| GSettings type mismatch for `idle-delay`/`lock-delay` | Low–Medium | Runtime: value ignored | Using `mkUint32` explicitly avoids int32/uint32 mismatch |
| Downstream users break existing UX | Low | Low | Auto-login unchanged; only screen-wake now requires password — expected behaviour |
| Lock screen not appearing after rebuild | Very Low | High | Verify with `gsettings` commands above; if wrong, check dconf precedence with `dconf dump /` |
| User has manually set `lock-enabled = false` via GNOME Settings | Low | Medium | Home Manager dconf overrides user dconf on next login; warn in commit/docs |

---

## 9. Sources Consulted

1. **NixOS Wiki — GNOME** (`wiki.nixos.org/wiki/GNOME`) — GDM auto-login configuration, dconf Settings patterns, NixOS 25.11 module names [Context7: `/websites/wiki_nixos_wiki`]
2. **NixOS Wiki — Gnome** (`wiki.nixos.org/wiki/Gnome`) — GNOME dconf via Home Manager patterns [Context7: `/websites/wiki_nixos_wiki`]
3. **Home Manager Options** (`home-manager-options.extranix.com`) — `dconf.settings` API, available lock-screen services [Context7: `/websites/home-manager-options_extranix`]
4. **GNOME GSettings Schema** (`org.gnome.desktop.screensaver`, `org.gnome.session`) — upstream default values for `lock-enabled`, `lock-delay`, `idle-delay`
5. **Home Manager source** (`nix-community/home-manager`) — `lib.hm.gvariant.mkUint32` availability in Home Manager module `lib` [Context7: `/nix-community/home-manager`]
6. **Current VexOS sources** — `modules/gnome.nix`, `home/default.nix`, `hosts/default/configuration.nix`, `modules/users.nix` — read directly to identify exact line-level changes required

---

## 10. Summary

The root cause is a single dconf override — `lock-enabled = false` — that was
set explicitly in `home/default.nix`, disabling GNOME's upstream-default screen
lock. Combined with GDM auto-login (also present), this eliminates all
physical-access authentication for the `nimda` session, which holds `wheel`
(sudo), SSH keys, and VPN access.

The fix is minimal: remove the `lock-enabled = false` override, replace it with
`lock-enabled = true`, and add explicit declarative values for `lock-delay` (0)
and `idle-delay` (300) so the lock policy is transparent in the configuration.
Auto-login is preserved. A security comment is added to `gnome.nix` to prevent
future regressions. No new packages or flake inputs are required.
