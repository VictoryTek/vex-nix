# Specification: Add Packages to VexOS Configuration

**Feature:** add_packages  
**Date:** 2026-03-10  
**Status:** Draft

---

## 1. Current Configuration Analysis

### Flake Inputs
- `nixpkgs`: `github:nixos/nixpkgs/nixos-unstable`
- `home-manager`: follows nixpkgs
- System: `x86_64-linux`, username: `vex`

### Existing System Packages (`hosts/default/configuration.nix`)
```
vim, wget, git, curl, htop, firefox, tailscale, cifs-utils
```
- `nixpkgs.config.allowUnfree = true` is **already set** — unfree packages (Brave) will build without additional changes.

### Existing GNOME Packages (`modules/gnome.nix` — `environment.systemPackages`)
```
gnome-tweaks, dconf-editor, gnomeExtensions.appindicator, gnomeExtensions.dash-to-dock
```
- GNOME services: `services.xserver.enable`, `services.displayManager.gdm.enable`, `services.desktopManager.gnome.enable`, `services.gnome.gnome-keyring.enable`

### Existing Home Manager Packages (`home/default.nix` — `home.packages`)
```
vscode, tree, ripgrep, fd, bat, eza, fzf, fastfetch, btop
```
- **VS Code (`pkgs.vscode`) is already present** — no action required.

### Existing User Groups (`modules/users.nix`)
```
networkmanager, wheel, audio, video
```

### Existing System Services (`modules/system.nix`)
```
openssh, tailscale, samba, gvfs, printing, bluetooth, blueman
```

---

## 2. Package Evaluation

### 2.1 Brave Browser
- **Status:** NOT present — needs to be added.
- **Verified nixpkgs attribute:** `pkgs.brave`
  - Brave is an unfree package. `nixpkgs.config.allowUnfree = true` is already configured.
  - Confirmed via nixpkgs unfree predicate examples showing `"brave"` as a named unfree package.
- **Placement decision:** `home/default.nix` → `home.packages`
  - Rationale: VS Code (another GUI user application) is already managed in Home Manager. Brave is a user-scoped browser with per-user profile data. This is consistent with existing patterns. Firefox lives in system packages as the default system browser; Brave can supplement it at the user level.

### 2.2 GNOME Boxes
- **Status:** NOT present — needs to be added.
- **Verified nixpkgs attribute:** `pkgs.gnome-boxes`
  - In nixos-unstable (post-23.11), GNOME packages were reorganized out of the `pkgs.gnome.*` attrset. The correct attribute is now `pkgs.gnome-boxes` (not `pkgs.gnome.gnome-boxes`).
  - Requires `virtualisation.libvirtd.enable = true` for the QEMU/KVM backend to function.
  - The user `vex` must be in the `libvirtd` group to manage VMs without sudo.
- **Placement decision:** `modules/gnome.nix`
  - Rationale: GNOME Boxes is a first-party GNOME application; it belongs alongside other GNOME packages in `modules/gnome.nix`. The libvirtd service option also fits here since it's a desktop virtualization feature.
  - Add `pkgs.gnome-boxes` to the existing `environment.systemPackages` list.
  - Add `virtualisation.libvirtd.enable = true;` to `modules/gnome.nix`.
  - Add `"libvirtd"` to `users.users.vex.extraGroups` in `modules/users.nix`.

### 2.3 Docker
- **Status:** NOT present — needs to be added.
- **Verified NixOS options:**
  - `virtualisation.docker.enable = true;` — enables and starts the Docker daemon via systemd.
  - `virtualisation.docker.enableOnBoot = true;` — optional; controls socket-activation vs. always-on. Defaults to socket activation in recent NixOS; setting `true` starts it at boot unconditionally.
  - User must be in the `"docker"` group to use Docker without sudo. **Note:** membership in the `docker` group is equivalent to root access — this is a known and accepted trade-off for a personal workstation.
- **Placement decision:**
  - Service config → `modules/system.nix` (consistent with other services like tailscale, openssh)
  - Group membership → `modules/users.nix` — add `"docker"` to `users.users.vex.extraGroups`

### 2.4 VS Code
- **Status:** ALREADY PRESENT in `home/default.nix` as `vscode`.
- **No changes required.**

---

## 3. Proposed Changes

### 3.1 `home/default.nix` — Add Brave Browser

**Location:** `home.packages` list (after `vscode`, before dev tools)

```nix
home.packages = with pkgs; [
  # Development tools
  vscode
  
  # Browsers
  brave

  # Terminal utilities
  tree
  ...
```

**Exact diff (conceptual):**
```diff
   home.packages = with pkgs; [
     # Development tools
     vscode
+    
+    # Browsers
+    brave
     
     # Terminal utilities
     tree
```

---

### 3.2 `modules/gnome.nix` — Add GNOME Boxes + libvirtd

**Add to `environment.systemPackages`:**
```nix
environment.systemPackages = with pkgs; [
  gnome-tweaks
  dconf-editor
  gnomeExtensions.appindicator
  gnomeExtensions.dash-to-dock
  gnome-boxes          # Virtual machine manager (GNOME)
];
```

**Add virtualisation service declaration:**
```nix
# Enable libvirt for GNOME Boxes
virtualisation.libvirtd.enable = true;
```

---

### 3.3 `modules/system.nix` — Add Docker Service

**Add after the existing services (e.g., after `services.blueman.enable`):**
```nix
# Docker container runtime
virtualisation.docker = {
  enable = true;
  enableOnBoot = true;
};
```

---

### 3.4 `modules/users.nix` — Add `docker` and `libvirtd` Groups

**Update `extraGroups` for user `vex`:**
```nix
users.users.vex = {
  isNormalUser = true;
  description = "Vex";
  extraGroups = [
    "networkmanager"
    "wheel"
    "audio"
    "video"
    "docker"      # Docker daemon access (root-equivalent — personal workstation only)
    "libvirtd"    # GNOME Boxes / libvirt VM management
  ];
  shell = pkgs.bash;
  initialPassword = "changeme";
};
```

---

## 4. File Modification Summary

| File | Action | Change |
|------|--------|--------|
| `home/default.nix` | Modify | Add `brave` to `home.packages` |
| `modules/gnome.nix` | Modify | Add `gnome-boxes` to `environment.systemPackages`; add `virtualisation.libvirtd.enable = true` |
| `modules/system.nix` | Modify | Add `virtualisation.docker.enable = true` and `virtualisation.docker.enableOnBoot = true` |
| `modules/users.nix` | Modify | Add `"docker"` and `"libvirtd"` to `extraGroups` |
| `hosts/default/configuration.nix` | No change | `allowUnfree` already set |

**Total files to modify: 4**  
**VS Code: no change needed (already present)**

---

## 5. Package Attribute Names (Context7 Verified)

| Package | nixpkgs Attribute | Source |
|---------|------------------|--------|
| Brave Browser | `pkgs.brave` | nixpkgs unfree package list |
| GNOME Boxes | `pkgs.gnome-boxes` | nixos-unstable (post-23.11 reorganization) |
| Docker daemon | `virtualisation.docker.enable` | NixOS virtualisation module |
| VS Code | `pkgs.vscode` | Already in `home/default.nix` |

> **Note on GNOME Boxes attribute:** In NixOS 23.05 and earlier the attribute was
> `pkgs.gnome.gnome-boxes`. As of nixpkgs 23.11 / nixos-unstable the GNOME scope
> was flattened and the correct attribute is `pkgs.gnome-boxes`. Since this flake
> tracks `nixos-unstable`, `pkgs.gnome-boxes` is the correct form.

---

## 6. Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `pkgs.gnome.gnome-boxes` used instead of `pkgs.gnome-boxes` | High | Use verified attribute `pkgs.gnome-boxes` per unstable nixpkgs |
| Docker group grants root-equivalent access | Medium | Accepted risk for personal workstation; document in comment |
| `virtualisation.libvirtd` conflicts with existing VM config | Low | No existing libvirtd config; no conflict expected |
| Brave fails to build due to unfree | Low | `nixpkgs.config.allowUnfree = true` already set in `hosts/default/configuration.nix` |
| User must re-login for group membership (`docker`, `libvirtd`) to take effect | Low | Expected NixOS behavior; note in docs or rebuild prompt |
| `gnome-boxes` excluded in `environment.gnome.excludePackages` | Low | Checked `gnome.nix` — not in exclude list, no conflict |

---

## 7. Implementation Order

1. `modules/users.nix` — add groups (foundation for Docker and libvirt access)
2. `modules/system.nix` — enable Docker service
3. `modules/gnome.nix` — add GNOME Boxes package + libvirtd service
4. `home/default.nix` — add Brave to home packages

---

## 8. Validation Steps

After implementation, the reviewer should run:

```bash
# Validate flake structure
nix flake check

# Confirm the configuration evaluates
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf

# Confirm packages are resolvable (optional smoke test)
nix eval .#nixosConfigurations.vexos.config.environment.systemPackages --apply 'pkgs: builtins.map (p: p.name) pkgs'
```

Expected: all commands exit 0 with no evaluation errors.
