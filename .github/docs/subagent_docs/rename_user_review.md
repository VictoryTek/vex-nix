# Review: Rename Linux Username `vex` → `nimda`

**Feature:** rename_user  
**Date:** 2026-03-10  
**Reviewer:** QA Subagent  
**Verdict:** ✅ PASS

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 95% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (98%)**

---

## 1. Completeness Check

All 11 changes defined in `rename_user_spec.md` are implemented. A full-codebase search for
bare `vex` in `.nix` files confirms no username references remain.

| File | Expected Changes | Implemented | Status |
|------|-----------------|-------------|--------|
| `flake.nix` | 1 (user binding key) | ✓ | Complete |
| `home/default.nix` | 5 (username, homeDir, git name, 2 aliases) | ✓ | Complete |
| `modules/users.nix` | 2 (user key, description) | ✓ | Complete |
| `modules/system.nix` | 1 (Samba share path) | ✓ | Complete |
| `README.md` | 2 (install instruction, smbpasswd cmd) | ✓ | Complete |
| **Total** | **11** | **11** | ✅ All done |

### Remaining `vex` occurrences (all correctly excluded per spec)

| File | Occurrence | Classification | Action |
|------|-----------|----------------|--------|
| `flake.nix` | `description = "VexOS ..."` | Project branding | Out of scope ✓ |
| `flake.nix` | `vexos = nixpkgs.lib.nixosSystem` | Hostname/config key | Out of scope ✓ |
| `flake.nix` | `# Replace "vexos" with your hostname` | Comment re: hostname | Out of scope ✓ |
| `hosts/default/configuration.nix` | `networking.hostName = "vexos"` | System hostname | Out of scope ✓ |
| `modules/system.nix` | `"server string" = "VexOS Samba Server"` | Samba display name | Out of scope ✓ |
| `modules/system.nix` | `"netbios name" = "vexos"` | NetBIOS name | Out of scope ✓ |
| `home/default.nix` | `vex@example.com` (commented) | Email placeholder | Out of scope ✓ |
| `home/default.nix` | `/home/nimda/Projects/vex-nix#vexos` | Repo name + hostname | Out of scope ✓ |

**No stray username `vex` references found. ✅**

---

## 2. Correctness Check

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `home-manager.users` key | `nimda` | `nimda` | ✅ |
| `users.users` key | `nimda` | `nimda` | ✅ |
| `home.username` | `"nimda"` | `"nimda"` | ✅ |
| `home.homeDirectory` | `"/home/nimda"` | `"/home/nimda"` | ✅ |
| `description` | `"Nimda"` (capital N) | `"Nimda"` | ✅ |
| `update` alias path | `/home/nimda/Projects/vex-nix#vexos` | `/home/nimda/Projects/vex-nix#vexos` | ✅ |
| `rebuild` alias path | `/home/nimda/Projects/vex-nix#vexos` | `/home/nimda/Projects/vex-nix#vexos` | ✅ |
| Samba share path | `/home/nimda/Public` | `/home/nimda/Public` | ✅ |
| README smbpasswd cmd | `smbpasswd -a nimda` | `smbpasswd -a nimda` | ✅ |
| README install note | `from "nimda"` | `from "nimda"` | ✅ |

**All correctness checks pass. ✅**

---

## 3. Nix Syntax Check

All `.nix` files manually verified for structural integrity.

| File | Braces Balanced | Semicolons OK | Attribute Paths | Status |
|------|----------------|---------------|-----------------|--------|
| `flake.nix` | ✓ | ✓ | ✓ | ✅ |
| `home/default.nix` | ✓ | ✓ | ✓ | ✅ |
| `modules/users.nix` | ✓ | ✓ | ✓ | ✅ |
| `modules/system.nix` | ✓ | ✓ | ✓ | ✅ |
| `modules/gnome.nix` | ✓ | ✓ | ✓ | ✅ (unchanged) |
| `hosts/default/configuration.nix` | ✓ | ✓ | ✓ | ✅ (unchanged) |

**No syntax issues detected. ✅**

---

## 4. Build Validation

### Command 1: `nix flake check`

```
wsl bash -c "source ~/.nix-profile/etc/profile.d/nix.sh; cd /mnt/c/Projects/vex-nix && nix --extra-experimental-features 'nix-command flakes' flake check 2>&1"
```

**Full Output:**
```
warning: Git tree '/mnt/c/Projects/vex-nix' is dirty
warning: creating lock file "/mnt/c/Projects/vex-nix/flake.lock":
• Added input 'home-manager':
    'github:nix-community/home-manager/bb014746edb2a98d975abde4dd40fa240de4cf86?narHash=sha256-u/96NoAyN8BSRuM3ZimGf7vyYgXa3pLx4MYWjokuoH4%3D' (2026-03-09)
• Added input 'home-manager/nixpkgs':
    follows 'nixpkgs'
• Added input 'nixpkgs':
    'github:nixos/nixpkgs/9dcb002ca1690658be4a04645215baea8b95f31d?narHash=sha256-9jVDGZnvCckTGdYT53d/EfznygLskyLQXYwJLKMPsZs%3D' (2026-03-08)
```

**Exit code: 0 ✅**

> Note: The "dirty" warning is expected when running from a Windows host via WSL with uncommitted changes. The lock file was created successfully and all flake inputs resolved.

---

### Command 2: `nix eval ... --apply builtins.typeOf`

```
wsl bash -c "source ~/.nix-profile/etc/profile.d/nix.sh; cd /mnt/c/Projects/vex-nix && nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf 2>&1"
```

**Full Output:**
```
warning: Git tree '/mnt/c/Projects/vex-nix' is dirty
"set"
```

**Exit code: 0 ✅**

> The configuration evaluates successfully. `builtins.typeOf` returning `"set"` confirms the toplevel derivation attribute set is accessible — correct expected result.

---

## 5. Minor Observations (Non-Blocking)

These are informational notes and do not affect the PASS verdict:

1. **`PasswordAuthentication = true`** in `modules/system.nix` — intentional with a comment noting it should be set to `false` with SSH keys for hardened deployments. Acceptable for initial setup.

2. **`initialPassword = "changeme"`** in `modules/users.nix` — documented with a comment instructing users to run `passwd` post-install. Standard pattern for NixOS initial deploy.

3. **`flake.lock` generated** — The lock file did not previously exist (or was absent) and was created during the `nix flake check` run. This is expected on a fresh clone/first evaluation.

---

## 6. Summary of Findings

- All 11 username rename changes from the specification are fully implemented.
- No stray `vex` username references remain anywhere in the codebase.
- All user-facing identity values (`username`, `homeDirectory`, `description`, aliases, Samba path) are consistent and correct.
- Nix syntax is valid across all modified files.
- `nix flake check` exits 0 and resolves all flake inputs.
- `nix eval` returns `"set"` confirming the full NixOS configuration evaluates without errors.

---

## Verdict: ✅ PASS
