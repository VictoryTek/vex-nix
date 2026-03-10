# Specification: Rename Linux Username from `vex` to `nimda`

**Feature:** rename_user  
**Date:** 2026-03-10  
**Status:** Approved for Implementation

---

## 1. Summary

The Linux username `vex` must be renamed to `nimda` (lowercase, per Linux username convention) across the entire NixOS configuration. The user display name / `description` field may use `"Nimda"` (capital N). The system hostname (`vexos`) and project name (`VexOS`) are **out of scope** and must NOT be changed.

---

## 2. Current Configuration Analysis

The username `vex` appears in the following roles across 4 files:

| Role | Files |
|---|---|
| Home Manager user binding | `flake.nix` |
| Home Manager identity | `home/default.nix` |
| NixOS user account definition | `modules/users.nix` |
| Samba share path | `modules/system.nix` |
| README instructions | `README.md` |

The following contain `vex` as **system/OS branding only** and are **not in scope**:

- `flake.nix` — `vexos` nixosConfiguration key (hostname)
- `flake.nix` — `description = "VexOS - Personal NixOS Configuration with GNOME"`
- `hosts/default/configuration.nix` — `networking.hostName = "vexos"`
- `modules/system.nix` — `"server string" = "VexOS Samba Server"` and `"netbios name" = "vexos"`
- `README.md` — Project title, repo URL, hostname references

---

## 3. Problem Definition

All `vex` username references scattered across the configuration will cause login failures, home directory mismatches, and Samba path errors if an account named `nimda` is created instead. Every occurrence must be updated atomically.

---

## 4. Proposed Solution Architecture

A targeted find-and-replace of the username string in each affected file. No new files need to be created. No module structure changes are required. Changes must maintain the declarative nature of the NixOS configuration.

---

## 5. Complete Change Inventory

### 5.1 `flake.nix`

**1 change required.**

| Line | Attribute | Old Value | New Value |
|------|-----------|-----------|-----------|
| 29 | `home-manager.users` key | `home-manager.users.vex` | `home-manager.users.nimda` |

**Exact change:**
```nix
# OLD
home-manager.users.vex = import ./home/default.nix;

# NEW
home-manager.users.nimda = import ./home/default.nix;
```

---

### 5.2 `home/default.nix`

**5 changes required.**

| Line | Attribute / Context | Old Value | New Value |
|------|---------------------|-----------|-----------|
| 7 | `home.username` | `"vex"` | `"nimda"` |
| 8 | `home.homeDirectory` | `"/home/vex"` | `"/home/nimda"` |
| 42 | `user.name` (commented git config) | `"Vex"` | `"Nimda"` |
| 55 | `update` shell alias path | `/home/vex/Projects/vex-nix#vexos` | `/home/nimda/Projects/vex-nix#vexos` |
| 56 | `rebuild` shell alias path | `/home/vex/Projects/vex-nix#vexos` | `/home/nimda/Projects/vex-nix#vexos` |

**Exact changes:**

```nix
# OLD
home.username = "vex";
home.homeDirectory = "/home/vex";

# NEW
home.username = "nimda";
home.homeDirectory = "/home/nimda";
```

```nix
# OLD (commented block)
#    user.name = "Vex";

# NEW (commented block)
#    user.name = "Nimda";
```

```nix
# OLD
update = "sudo nixos-rebuild switch --flake /home/vex/Projects/vex-nix#vexos";
rebuild = "sudo nixos-rebuild switch --flake /home/vex/Projects/vex-nix#vexos";

# NEW
update = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
rebuild = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
```

---

### 5.3 `modules/users.nix`

**2 changes required.**

| Line | Attribute | Old Value | New Value |
|------|-----------|-----------|-----------|
| 5 | `users.users` key | `users.users.vex` | `users.users.nimda` |
| 7 | `description` | `"Vex"` | `"Nimda"` |

**Exact changes:**

```nix
# OLD
users.users.vex = {
  isNormalUser = true;
  description = "Vex";

# NEW
users.users.nimda = {
  isNormalUser = true;
  description = "Nimda";
```

---

### 5.4 `modules/system.nix`

**1 change required.**

| Line | Attribute / Context | Old Value | New Value |
|------|---------------------|-----------|-----------|
| 50 | Samba share `path` | `"/home/vex/Public"` | `"/home/nimda/Public"` |

**Exact change:**

```nix
# OLD
path = "/home/vex/Public";

# NEW
path = "/home/nimda/Public";
```

---

### 5.5 `README.md`

**2 changes required.**

| Line | Context | Old Value | New Value |
|------|---------|-----------|-----------|
| 23 | Setup instruction | `Change username from "vex"` | `Change username from "nimda"` |
| 47 | Samba setup command | `sudo smbpasswd -a vex` | `sudo smbpasswd -a nimda` |

**Exact changes:**

```markdown
# OLD
   - `modules/users.nix` - Change username from "vex"

# NEW
   - `modules/users.nix` - Change username from "nimda"
```

```markdown
# OLD
sudo smbpasswd -a vex

# NEW
sudo smbpasswd -a nimda
```

---

## 6. Files NOT Changing (Out of Scope)

| File | Occurrence | Reason |
|------|-----------|--------|
| `flake.nix` | `description = "VexOS ..."` | Project branding |
| `flake.nix` | `vexos = nixpkgs.lib.nixosSystem` | Hostname / config key |
| `flake.nix` | `# Replace "vexos" with your hostname` | Comment about hostname |
| `hosts/default/configuration.nix` | `networking.hostName = "vexos"` | System hostname |
| `modules/system.nix` | `"server string" = "VexOS Samba Server"` | Samba display name (OS branding) |
| `modules/system.nix` | `"netbios name" = "vexos"` | NetBIOS name (hostname) |
| `modules/gnome.nix` | *(no vex occurrences)* | No changes needed |
| `README.md` | `# VexOS`, `vex-nix.git`, `cd vex-nix`, `#vexos` | Project/repo/hostname branding |
| `home/default.nix` | `user.email = "vex@example.com"` (commented) | Email placeholder, not a username |

---

## 7. Implementation Steps

1. Edit `flake.nix` — rename `home-manager.users.vex` key to `home-manager.users.nimda`
2. Edit `home/default.nix` — update `home.username`, `home.homeDirectory`, git `user.name`, and both shell aliases
3. Edit `modules/users.nix` — rename `users.users.vex` key and update `description`
4. Edit `modules/system.nix` — update Samba `path` for the public share
5. Edit `README.md` — update the setup instructions and smbpasswd command

---

## 8. NixOS Packages and Options

No new packages or NixOS options are introduced. All changes are pure attribute renames and string substitutions within existing configuration expressions.

Relevant existing options:
- `users.users.<name>` — NixOS user account definition
- `home-manager.users.<name>` — Home Manager user binding
- `home.username` / `home.homeDirectory` — Home Manager identity settings

---

## 9. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Partial rename leaves `vex` in one file causing login failure | This spec enumerates every occurrence; implementation must apply all 11 changes atomically |
| Home Manager/NixOS user account mismatch | `users.users.nimda` in users.nix and `home-manager.users.nimda` in flake.nix must match exactly |
| Samba path references stale `/home/vex/Public` directory | Path updated in system.nix; user must create `/home/nimda/Public` on first login or via activation script |
| Shell aliases point to wrong home path | Both `update` and `rebuild` aliases updated to `/home/nimda/...` |
| `nix flake check` evaluation failure | All attribute names are consistent Nix identifiers; `nimda` is a valid Nix attribute name |

---

## 10. Total Change Count

| File | Changes |
|------|---------|
| `flake.nix` | 1 |
| `home/default.nix` | 5 |
| `modules/users.nix` | 2 |
| `modules/system.nix` | 1 |
| `README.md` | 2 |
| **Total** | **11** |
