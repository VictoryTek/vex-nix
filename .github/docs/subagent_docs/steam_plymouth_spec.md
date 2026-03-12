# Specification: Steam Comment-Out & Plymouth Fix

**Feature Name**: steam_plymouth  
**Date**: 2026-03-12  
**Status**: DRAFT  

---

## 1. Overview

Two independent changes are required:

1. **Comment out Steam setup** — The deployment network blocks Steam servers and the
   `nix-gaming.cachix.org` binary cache, causing `nixos-rebuild build` to stall or
   fail. Steam configuration must be commented out (not deleted) so it can be
   re-enabled by removing comments when on an unrestricted network.

2. **Fix Plymouth not appearing on startup** — Plymouth is configured but the boot
   splash is invisible. Root-cause analysis and a targeted fix are documented below.

---

## 2. Current Configuration Analysis

### 2.1 Steam-related configuration

| File | What it contains |
|------|-----------------|
| `flake.nix` | `nix-gaming` flake input; imports `pipewireLowLatency` and `platformOptimizations` modules |
| `modules/gaming.nix` | `nix.settings` Cachix block (nix-gaming.cachix.org); `programs.steam` block with `proton-ge-bin`; `programs.gamemode`; `services.pipewire.lowLatency` |
| `home/default.nix` | `protonplus` package in `home.packages` |

**Exact blocks subject to change in `modules/gaming.nix`:**

```
# Block A – Cachix binary cache (lines ~18–24)
nix.settings = {
  extra-substituters = [ "https://nix-gaming.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
  ];
};

# Block B – Steam (lines ~27–38)
programs.steam = {
  enable = true;
  remotePlay.openFirewall = true;
  dedicatedServer.openFirewall = false;
  localNetworkGameTransfers.openFirewall = true;
  extraCompatPackages = [ pkgs.proton-ge-bin ];
};
```

**Exact line subject to change in `home/default.nix`:**

```
protonplus   # line ~30, under # Gaming Utilities
```

**NOT touching:**
- `programs.gamemode` — CPU scheduler, no network dependency
- `services.pipewire.lowLatency` — audio tuning, no network dependency
- `nix-gaming` flake input / modules in `flake.nix` — `pipewireLowLatency` and
  `platformOptimizations` do not require Steam or the Cachix cache to evaluate

### 2.2 Plymouth-related configuration

| File | What it contains |
|------|-----------------|
| `modules/plymouth.nix` | `boot.plymouth.enable/theme`; kernel params; `boot.initrd.kernelModules`; GRUB timeout |
| `hosts/default/configuration.nix` | `gpu.type = "none"` (CI/template default); GRUB on `/dev/sda` (legacy BIOS/MBR) |

**Current `boot.initrd.kernelModules` expression:**

```nix
boot.initrd.kernelModules = lib.optionals (config.gpu.type == "intel") [ "i915" ]
  ++ lib.optionals (config.gpu.type == "amd") [ "amdgpu" ]
  ++ lib.optionals (config.gpu.type == "nvidia") [
    "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"
  ];
```

When `gpu.type = "none"` (the current default in `configuration.nix`), this expression
evaluates to `[]` — an **empty list**. No kernel module is loaded in the initrd for
display output, so Plymouth has no framebuffer device to render onto.

---

## 3. Root Cause Analysis — Plymouth Not Appearing

### Primary cause: No framebuffer/KMS module in initrd

Plymouth requires a DRM/KMS framebuffer device present **before** the main system
userspace initialises. The `boot.initrd.kernelModules` list controls which modules are
packed into the initrd and loaded early. With `gpu.type = "none"` the list is empty,
so:

- No KMS device is exposed during initrd
- Plymouth daemon starts but finds no display device
- Boot continues silently; Plymouth never renders

This is the single most impactful issue. All other configuration (kernel params,
theme, `quiet splash`) is correct per the NixOS Wiki reference implementation.

### Secondary cause: initrd uses legacy shell scripts (not systemd)

`boot.initrd.systemd.enable` is **not set** (defaults to `false`). The legacy
initrd init scripts have known races where Plymouth may start after the kernel
has already switched the display away from the framebuffer. Enabling systemd in
the initrd provides ordered service dependencies so Plymouth starts at the right
time.

Reference: NixOS manual — `boot.initrd.systemd.enable = true` is the documented
prerequisite for `boot.plymouth.tpm2-totp` and is generally recommended for
modern Plymouth usage.

### Tertiary cause: kernel parameter name ambiguity

The current kernel param `udev.log_priority=3` is valid on older kernels. Modern
kernels (≥ 6.x, as used by NixOS 25.11) prefer `rd.udev.log_priority=3` (the `rd.`
prefix scopes the parameter to the initrd phase). The NixOS Wiki examples use
`udev.log_priority=3` (without `rd.`), so this is low-risk but worth noting.
No change is required here.

### Why `gpu.type = "none"` is the correct CI default but breaks Plymouth

The "none" type is intentionally safe for headless VMs and CI. Real deployments that
want Plymouth must set `gpu.type` to their actual GPU type in their thin local flake,
or the plymouth module must handle the "none" case explicitly.

The fix adds a fallback generic framebuffer for `gpu.type == "none"` so Plymouth
works in both VMs and on real hardware without requiring a specific GPU type.

---

## 4. Proposed Fix — Plymouth

### Fix 1: Add fallback framebuffer modules for `gpu.type = "none"`

Extend the `boot.initrd.kernelModules` expression in `modules/plymouth.nix` to
include generic framebuffer drivers when no GPU type is selected:

```nix
boot.initrd.kernelModules =
  # Fallback: load generic framebuffer drivers when no dedicated GPU module
  # is configured. simpledrm binds to any firmware-provided simple framebuffer
  # (VESA/VBE on BIOS, GOP on UEFI). bochs_drm covers QEMU/KVM VMs.
  lib.optionals (config.gpu.type == "none") [ "simpledrm" "bochs_drm" ]
  ++ lib.optionals (config.gpu.type == "intel") [ "i915" ]
  ++ lib.optionals (config.gpu.type == "amd") [ "amdgpu" ]
  ++ lib.optionals (config.gpu.type == "nvidia") [
    "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"
  ];
```

**`simpledrm`** — Modern kernel DRM driver that binds to any pre-existing simple
framebuffer set up by the firmware or bootloader (VBE on BIOS, GOP on UEFI). Works
on physical hardware and VMs with display output. Available since kernel 5.14.

**`bochs_drm`** — DRM driver for the Bochs/QEMU virtual GPU. Required for QEMU/KVM
VMs that use the default Bochs VGA device.

### Fix 2: Enable systemd in the initrd

Add to `modules/plymouth.nix`:

```nix
# Use systemd as the initrd init system.
# This provides correct ordering of Plymouth startup relative to KMS device
# enumeration, preventing races where Plymouth starts before a display is available.
boot.initrd.systemd.enable = true;
```

**Risk**: systemd initrd is a significant change. It is well-tested on NixOS 25.11
and is the recommended approach for Plymouth. However, it removes some legacy initrd
hooks. Any custom `boot.initrd.postDeviceCommands` or similar scripting hooks must be
migrated if present. The current config has none, so the risk is low.

---

## 5. Implementation Steps

### Step 1: Comment out Steam in `modules/gaming.nix`

Comment out the **entire `nix.settings` Cachix block** and the **entire
`programs.steam` block**. Do not modify `programs.gamemode` or
`services.pipewire.lowLatency`.

Before:
```nix
  # ── Cachix binary cache (avoids building wine-ge from source) ─────────
  nix.settings = {
    extra-substituters = [ "https://nix-gaming.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  };

  # ── Steam ────────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };
```

After:
```nix
  # ── Cachix binary cache (avoids building wine-ge from source) ─────────
  # DISABLED: Network blocks nix-gaming.cachix.org — re-enable when off restricted network.
  # nix.settings = {
  #   extra-substituters = [ "https://nix-gaming.cachix.org" ];
  #   extra-trusted-public-keys = [
  #     "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
  #   ];
  # };

  # ── Steam ────────────────────────────────────────────────────────────
  # DISABLED: Network blocks Steam — re-enable when off restricted network.
  # programs.steam = {
  #   enable = true;
  #   remotePlay.openFirewall = true;
  #   dedicatedServer.openFirewall = false;
  #   localNetworkGameTransfers.openFirewall = true;
  #   extraCompatPackages = [ pkgs.proton-ge-bin ];
  # };
```

### Step 2: Comment out `protonplus` in `home/default.nix`

Locate `protonplus` under `# Gaming Utilities` in `home.packages` and comment it out:

Before:
```nix
    # Gaming Utilities
    protonplus
```

After:
```nix
    # Gaming Utilities
    # protonplus  # DISABLED: requires unrestricted network access
```

### Step 3: Fix Plymouth in `modules/plymouth.nix`

Replace the existing `boot.initrd.kernelModules` block and add
`boot.initrd.systemd.enable = true`.

The complete updated `modules/plymouth.nix` relevant section:

```nix
  # Use systemd as the initrd init system for correct Plymouth startup ordering.
  boot.initrd.systemd.enable = true;

  # KMS (Kernel Mode Setting) modules for early Plymouth display.
  # These must be loaded in initrd so Plymouth can show the splash
  # before the full kernel drivers are loaded.
  boot.initrd.kernelModules =
    # Fallback: load generic framebuffer drivers when no dedicated GPU module
    # is configured. simpledrm binds to any firmware-provided framebuffer
    # (VBE on BIOS, GOP on UEFI). bochs_drm covers QEMU/KVM VMs.
    lib.optionals (config.gpu.type == "none") [ "simpledrm" "bochs_drm" ]
    ++ lib.optionals (config.gpu.type == "intel") [ "i915" ]
    ++ lib.optionals (config.gpu.type == "amd") [ "amdgpu" ]
    ++ lib.optionals (config.gpu.type == "nvidia") [
      "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"
    ];
```

---

## 6. Files to be Modified

| File | Change |
|------|--------|
| `modules/gaming.nix` | Comment out `nix.settings` Cachix block and `programs.steam` block |
| `home/default.nix` | Comment out `protonplus` line |
| `modules/plymouth.nix` | Add `boot.initrd.systemd.enable = true`; add `simpledrm`/`bochs_drm` fallback to `boot.initrd.kernelModules` |

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| `boot.initrd.systemd.enable = true` may break custom initrd hooks | Medium | No custom hooks exist in the current config; standard NixOS modules handle migration automatically |
| `simpledrm` may not bind if GRUB does not set a video mode (BIOS) | Low | GRUB on BIOS systems sets VBE mode by default; `boot.loader.grub.gfxmode` can be set explicitly if needed |
| `bochs_drm` module build fails if kernel does not include Bochs DRM | Very Low | The module is part of the standard NixOS/Linux kernel package; `lib.optionals` gracefully handles missing modules at list-build time (build will warn, not fail) |
| Removing Steam from NixOS config leaves firewall rules in inconsistent state | None | Steam's `remotePlay.openFirewall` is also commented out; no orphan firewall rules remain |
| nix-gaming flake modules remain in flake.nix after Steam is disabled | Low | `pipewireLowLatency` and `platformOptimizations` are independent of Steam; they do not download Steam-related packages. No change needed to flake.nix |

---

## 8. Sources Consulted

1. **NixOS Wiki — Plymouth** (`wiki.nixos.org/wiki/Plymouth`): Reference kernel params, theme config, loader timeout pattern
2. **NixOS Wiki — Graphics** (`wiki.nixos.org/wiki/Graphics`): Early KMS module requirement for Plymouth (`boot.initrd.kernelModules`)
3. **NixOS Manual (unstable)** — `boot.initrd.systemd.enable` documented as prerequisite for Plymouth tpm2-totp; general systemd initrd guidance
4. **NixOS Wiki — Linux Kernel** (`wiki.nixos.org/wiki/Linux_Kernel`): `boot.kernelParams` usage
5. **nixpkgs source — `nixos/modules/system/boot/plymouth.nix`**: Plymouth module implementation confirming initrd integration
6. **fufexan/nix-gaming README** (`github.com/fufexan/nix-gaming`): Cachix cache URL/key confirmation, `pipewireLowLatency` independence from Steam
