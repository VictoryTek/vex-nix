# Specification: Package Management, Gaming & ASUS TUF Laptop Support

**Feature Name:** package_gaming_asus  
**Date:** 2026-03-10  
**Status:** Draft  

---

## 1. Current Configuration Analysis

### 1.1 Repository Structure

| File | Purpose |
|------|---------|
| `flake.nix` | Flake entry point; nixos-25.11, home-manager release-25.11, single host `vexos` |
| `hosts/default/configuration.nix` | Host config; imports 4 modules, gpu.type="none", GRUB bootloader, vim in systemPackages |
| `hosts/default/hardware-configuration.nix` | Template hardware config; Intel CPU, kvm-intel, ext4 root |
| `modules/gnome.nix` | GNOME desktop; GDM, extensions (appindicator, dash-to-dock), Boxes + libvirtd, partial excludePackages |
| `modules/gpu.nix` | Declarative GPU module; supports none/intel/amd/nvidia with full graphics stack |
| `modules/system.nix` | System services; SSH, Tailscale, Samba, Docker, Bluetooth, CUPS, power-profiles-daemon |
| `modules/users.nix` | User `nimda`; groups include wheel, docker, libvirtd; bash shell |
| `home/default.nix` | Home Manager for `nimda`; vscode, brave, CLI tools (tree, ripgrep, fd, bat, eza, fzf, fastfetch, btop), bash aliases |
| `scripts/preflight.sh` | CI validation: flake check, eval, formatting, linting |
| `scripts/deploy.sh` | Deployment script with hardware config handling |

### 1.2 Current Package Locations

**System packages** (`hosts/default/configuration.nix`):
- vim, wget, git, curl, htop, firefox, tailscale, cifs-utils

**GNOME packages** (`modules/gnome.nix`):
- gnome-tweaks, dconf-editor, gnomeExtensions.appindicator, gnomeExtensions.dash-to-dock, gnome-boxes

**GNOME excluded packages** (`modules/gnome.nix`):
- gnome-weather, gnome-clocks, gnome-maps, simple-scan, gnome-characters, gnome-tour, gnome-user-docs, yelp, epiphany

**User packages** (`home/default.nix`):
- vscode, brave, tree, ripgrep, fd, bat, eza, fzf, fastfetch, btop

### 1.3 Notable Gaps

- No gaming support (Steam, GameMode, Gamescope)
- No ASUS laptop hardware support (asusd, supergfxctl)
- `gpu.type` set to `"none"` — must be set for actual hardware
- Bootloader is legacy GRUB (`/dev/sda`) — ASUS TUF laptops use UEFI (user must update)
- No Starship prompt configuration
- No Ghostty terminal
- `vim` is installed but unwanted
- Several GNOME default apps not yet excluded (gnome-extensions-app, xterm, geary, gnome-music)

---

## 2. Problem Definition

### 2.1 Packages to Remove

| Package | Current Location | NixOS Attribute |
|---------|-----------------|-----------------|
| vim | `hosts/default/configuration.nix` systemPackages | `pkgs.vim` |
| GNOME Extensions App | GNOME default (not explicitly installed) | `pkgs.gnome-extensions-app` |
| XTerm | GNOME/X11 default (not explicitly installed) | `pkgs.xterm` |
| Geary | GNOME default email client | `pkgs.geary` |
| GNOME Music | GNOME default music player | `pkgs.gnome-music` |
| Rhythmbox | Alternative GNOME music player (may be pulled in) | `pkgs.rhythmbox` |

### 2.2 Packages to Add

| Package | Type | Where to Add | NixOS Attribute / Option |
|---------|------|-------------|--------------------------|
| ghostty | Terminal emulator | `home/default.nix` packages | `pkgs.ghostty` |
| blivet-gui | Storage management | `home/default.nix` packages | `pkgs.blivet-gui` |
| inxi | System info CLI | `home/default.nix` packages | `pkgs.inxi` |
| tmux | Terminal multiplexer | `home/default.nix` packages | `pkgs.tmux` |
| pavucontrol | PulseAudio volume control | `home/default.nix` packages | `pkgs.pavucontrol` |
| starship | Cross-shell prompt | `home/default.nix` programs.starship | Home Manager `programs.starship` |
| steam | Gaming platform | New `modules/gaming.nix` | `programs.steam.enable` (NixOS module) |
| gamemode | Gaming optimizer | New `modules/gaming.nix` | `programs.gamemode.enable` (NixOS module) |

### 2.3 ASUS TUF Laptop Gaming Gaps (Bazzite-Inspired)

Bazzite (Fedora-based gaming distro) provides for ASUS laptops:
- **asusctl / asusd**: Fan profile control, keyboard LED/RGB, performance profiles, charge limiting
- **supergfxctl**: GPU mode switching (Integrated / Hybrid / Dedicated / Compute / VFIO)
- **Power management**: TLP or power-profiles-daemon with custom tuning
- **Gaming kernel tweaks**: Transparent hugepages, split lock mitigate, vm.max_map_count, futex2
- **GameMode**: Process niceness, CPU governor, GPU optimizations
- **Gamescope**: SteamOS session compositing window manager

NixOS has native modules for all of these:
- `services.asusd` — Full asusd daemon with config options
- `services.supergfxd` — GPU switching daemon
- `programs.rog-control-center` — GUI control panel (auto-enables services.asusd)
- `programs.steam` — Steam with FHS environment and controller support
- `programs.gamemode` — GameMode with renice capabilities
- `programs.gamescope` — Gamescope compositor

---

## 3. Proposed Solution Architecture

### 3.1 Files to Modify

| File | Changes |
|------|---------|
| `modules/gnome.nix` | Add gnome-extensions-app, xterm, geary, gnome-music, rhythmbox to `environment.gnome.excludePackages` |
| `hosts/default/configuration.nix` | Remove `vim` from systemPackages; import new modules |
| `home/default.nix` | Add ghostty, blivet-gui, inxi, tmux, pavucontrol to packages; add `programs.starship` config |
| `modules/users.nix` | Add `gamemode` group to user's extraGroups |

### 3.2 Files to Create

| File | Purpose |
|------|---------|
| `modules/gaming.nix` | Steam, GameMode, Gamescope, gaming kernel tweaks |
| `modules/asus.nix` | ASUS TUF laptop support: asusd, supergfxctl, rog-control-center, power tweaks |

### 3.3 Architecture Diagram

```
flake.nix
  └── hosts/default/configuration.nix
        ├── modules/system.nix        (existing, unchanged)
        ├── modules/gnome.nix         (MODIFIED: more excludePackages)
        ├── modules/users.nix         (MODIFIED: add gamemode group)
        ├── modules/gpu.nix           (existing, unchanged)
        ├── modules/gaming.nix        (NEW: Steam, GameMode, kernel tweaks)
        └── modules/asus.nix          (NEW: asusd, supergfxd, ROG control)
  └── home/default.nix               (MODIFIED: new packages + starship)
```

---

## 4. Detailed Implementation Steps

### Step 1: Modify `modules/gnome.nix` — Expand GNOME Exclusions

Add the following packages to `environment.gnome.excludePackages`:

```nix
environment.gnome.excludePackages = with pkgs; [
  # Existing exclusions
  gnome-weather
  gnome-clocks
  gnome-maps
  simple-scan
  gnome-characters
  gnome-tour
  gnome-user-docs
  yelp
  epiphany

  # New exclusions (per user request)
  gnome-extensions-app   # GNOME Extensions management app
  xterm                  # Legacy X11 terminal
  geary                  # GNOME email client
  gnome-music            # GNOME music player
  rhythmbox              # Alternative music player
];
```

### Step 2: Modify `hosts/default/configuration.nix` — Remove vim, Add Module Imports

**Remove `vim`** from `environment.systemPackages`:

```nix
environment.systemPackages = with pkgs; [
  # vim  -- removed per user request
  wget
  git
  curl
  htop
  firefox
  tailscale
  cifs-utils
];
```

**Add new module imports:**

```nix
imports = [
  ../../modules/system.nix
  ../../modules/gnome.nix
  ../../modules/users.nix
  ../../modules/gpu.nix
  ../../modules/gaming.nix
  ../../modules/asus.nix
];
```

### Step 3: Modify `home/default.nix` — Add Packages and Starship

**Add new packages** to `home.packages`:

```nix
home.packages = with pkgs; [
  # Development tools
  vscode

  # Browsers
  brave

  # Terminal emulators
  ghostty

  # Terminal utilities
  tree
  ripgrep
  fd
  bat
  eza
  fzf
  tmux

  # System utilities
  fastfetch
  btop
  inxi
  pavucontrol
  blivet-gui
];
```

**Add Starship prompt configuration** (after `programs.bash` block):

```nix
# Starship cross-shell prompt
programs.starship = {
  enable = true;
  enableBashIntegration = true;
};
```

### Step 4: Modify `modules/users.nix` — Add gamemode Group

Add `"gamemode"` to the user's `extraGroups`:

```nix
extraGroups = [
  "networkmanager"
  "wheel"
  "audio"
  "video"
  "docker"
  "libvirtd"
  "gamemode"
];
```

### Step 5: Create `modules/gaming.nix` — Gaming Support

```nix
{ config, pkgs, ... }:

{
  # ── Steam ────────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = true;
  };

  # ── GameMode (Feral Interactive) ──────────────────────────────────────
  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = 0;
      };
    };
  };

  # ── Gaming Kernel Tweaks (Bazzite-inspired) ──────────────────────────
  # Increase vm.max_map_count for games that need many memory mappings
  # (required by many modern games, Star Citizen, etc.)
  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642;
    # Split lock performance (avoid performance penalty from split locks)
    "kernel.split_lock_mitigate" = 0;
  };
}
```

**Design notes:**
- `programs.steam.enable = true` handles the FHS environment, hardware udev rules, controller support, 32-bit graphics, and firewall automatically
- `programs.gamemode` with `enableRenice = true` wraps gamemoded with CAP_SYS_NICE
- GPU optimizations in gamemode are opt-in with `accept-responsibility`
- `vm.max_map_count` = 2147483642 matches SteamOS/Bazzite defaults
- `kernel.split_lock_mitigate` = 0 prevents performance drops from split lock detection

### Step 6: Create `modules/asus.nix` — ASUS TUF Laptop Support

```nix
# modules/asus.nix
#
# ASUS TUF / ROG laptop support module.
# Provides: asusd (fan control, LED, profiles), supergfxd (GPU switching),
#           rog-control-center (GUI), and Bazzite-inspired power tweaks.
#
# This module should only be imported on ASUS TUF / ROG hardware.
# On non-ASUS systems, remove or comment out this import from configuration.nix.

{ config, pkgs, ... }:

{
  # ── asusd — ASUS system daemon ──────────────────────────────────────
  # Controls: fan profiles, keyboard LED/RGB, charge limit, performance profiles
  services.asusd = {
    enable = true;
  };

  # ── supergfxd — GPU switching daemon ────────────────────────────────
  # Modes: Integrated, Hybrid, Dedicated, Compute, VFIO
  # Enabled by default when services.asusd is enabled, but explicit is better
  services.supergfxd.enable = true;

  # ── ROG Control Center — GUI ────────────────────────────────────────
  programs.rog-control-center = {
    enable = true;
    autoStart = true;
  };

  # ── Power management tweaks ─────────────────────────────────────────
  # power-profiles-daemon is already enabled in modules/system.nix
  # These are additional laptop-friendly tweaks

  # Ensure firmware updates work on ASUS hardware
  services.fwupd.enable = true;
}
```

**Design notes:**
- `services.asusd` provides the core ASUS daemon — fan profiles, keyboard LED, power profiles, charge limiting
- `services.supergfxd` handles GPU mode switching (Integrated/Hybrid/Dedicated) — critical for laptop battery life
- `programs.rog-control-center` provides a GUI for all asusd/supergfxd controls with autoStart in the systray
- `services.fwupd` enables firmware update support for ASUS hardware
- `power-profiles-daemon` is already in `modules/system.nix` and works with asusd for profile switching
- Config files (anime.ron, profile.ron, fan_curves.ron) are left at defaults initially — user can customize via the ROG Control Center GUI or by adding NixOS config options later
- The module adds a comment noting it should only be imported on ASUS hardware

---

## 5. NixOS Packages and Options Reference

### 5.1 Verified NixOS Module Options (from nixpkgs source)

| Option | Module File | Purpose |
|--------|-------------|---------|
| `programs.steam.enable` | `nixos/modules/programs/steam.nix` | Steam FHS environment + hardware support |
| `programs.steam.remotePlay.openFirewall` | same | UDP/TCP ports for Remote Play |
| `programs.steam.localNetworkGameTransfers.openFirewall` | same | TCP 27040 for LAN transfers |
| `programs.gamemode.enable` | `nixos/modules/programs/gamemode.nix` | GameMode daemon + polkit |
| `programs.gamemode.enableRenice` | same | CAP_SYS_NICE wrapper (default: true) |
| `programs.gamemode.settings` | same | INI-format /etc/gamemode.ini |
| `services.asusd.enable` | `nixos/modules/services/hardware/asusd.nix` | ASUS daemon |
| `services.asusd.animeConfig` | same | AniMe Matrix LED config |
| `services.asusd.profileConfig` | same | Performance profile config |
| `services.asusd.fanCurvesConfig` | same | Fan curve config |
| `services.supergfxd.enable` | `nixos/modules/services/hardware/supergfxd.nix` | GPU switching daemon |
| `services.supergfxd.settings` | same | JSON config for supergfxd |
| `programs.rog-control-center.enable` | `nixos/modules/programs/rog-control-center.nix` | GUI panel (auto-enables asusd) |
| `programs.rog-control-center.autoStart` | same | XDG autostart entry |

### 5.2 Verified Home Manager Options

| Option | Purpose |
|--------|---------|
| `programs.starship.enable` | Enable Starship prompt |
| `programs.starship.enableBashIntegration` | Hook into Bash init |

### 5.3 Package Availability (nixpkgs)

| Package | Attribute | Status | Notes |
|---------|-----------|--------|-------|
| ghostty | `pkgs.ghostty` | Available | GPU-accelerated terminal emulator |
| blivet-gui | `pkgs.blivet-gui` | Available | Anaconda's storage manager GUI |
| inxi | `pkgs.inxi` | Available | System information CLI tool |
| tmux | `pkgs.tmux` | Available | Terminal multiplexer |
| pavucontrol | `pkgs.pavucontrol` | Available | PulseAudio/PipeWire volume control |
| starship | `pkgs.starship` | Available | Cross-shell prompt (used via HM module) |
| steam | `pkgs.steam` | Available (unfree) | Used via programs.steam NixOS module |
| gamemode | `pkgs.gamemode` | Available | Used via programs.gamemode NixOS module |
| asusctl | `pkgs.asusctl` | Available (v6.3.4) | ASUS laptop control daemon + CLI |
| supergfxctl | `pkgs.supergfxctl` | Available (v5.2.7) | GPU switching utility |

---

## 6. Configuration Changes Summary

### 6.1 Flake Inputs
No changes needed — all packages are in nixpkgs, all modules are NixOS-native.

### 6.2 nixpkgs.config
`allowUnfree = true` is already set in `configuration.nix` — required for Steam.

### 6.3 Module Import Chain

```
configuration.nix imports:
  ├── modules/system.nix      (no changes)
  ├── modules/gnome.nix       (add 5 packages to excludePackages)
  ├── modules/users.nix       (add "gamemode" to extraGroups)
  ├── modules/gpu.nix         (no changes; user must set gpu.type for their hardware)
  ├── modules/gaming.nix      (NEW: Steam + GameMode + kernel tweaks)
  └── modules/asus.nix        (NEW: asusd + supergfxd + ROG GUI + fwupd)
```

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `ghostty` or `blivet-gui` not in nixpkgs 25.11 | Medium | If unavailable, the package will cause eval failure; remove from list and document. Can be added from unstable overlay if needed. |
| Steam requires `allowUnfree = true` | Low | Already set in configuration.nix. |
| ASUS module imported on non-ASUS hardware | Medium | Module will load harmlessly (services won't start without hardware), but adds comment warning to only import on ASUS systems. |
| `gpu.type` is `"none"` — Steam requires GPU drivers | High | **User MUST set `gpu.type`** to `"nvidia"` (or `"amd"`) in configuration.nix before deploying gaming module. Add a comment in gaming.nix. |
| `vm.max_map_count` sysctl conflict | Low | NixOS merges sysctl values; only one definition expected. |
| GameMode GPU optimizations risk | Medium | Guarded by `accept-responsibility` flag. GPU device defaults to 0. |
| Bootloader is GRUB for `/dev/sda` but ASUS TUF uses UEFI | High | **User must update** `hosts/default/hardware-configuration.nix` and bootloader config for their actual hardware. This spec does NOT modify bootloader/hardware config. |
| `programs.rog-control-center` auto-enables `services.asusd` | Low | Explicit `services.asusd.enable = true` is still set for clarity; NixOS handles merge. |
| `services.supergfxd` requires `kmod` and `pciutils` in PATH | Low | NixOS module handles this automatically via systemd service path. |
| `power-profiles-daemon` conflict with TLP | Low | Only `power-profiles-daemon` is enabled (in system.nix). No TLP is configured. They are mutually exclusive — do not add both. |

---

## 8. Implementation Checklist

- [ ] Modify `modules/gnome.nix` — add 5 packages to excludePackages
- [ ] Modify `hosts/default/configuration.nix` — remove `vim`, add `gaming.nix` and `asus.nix` imports
- [ ] Modify `home/default.nix` — add 5 packages + `programs.starship` configuration
- [ ] Modify `modules/users.nix` — add `"gamemode"` to extraGroups
- [ ] Create `modules/gaming.nix` — Steam, GameMode, kernel sysctl tweaks
- [ ] Create `modules/asus.nix` — asusd, supergfxd, rog-control-center, fwupd
- [ ] Verify `nix flake check` passes
- [ ] Verify `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf` succeeds
