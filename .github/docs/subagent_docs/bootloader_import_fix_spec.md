# Bootloader Import Fix — Specification

**Feature:** `bootloader_import_fix`  
**Date:** 2026-03-20  
**Status:** READY FOR IMPLEMENTATION  
**Severity:** BUILD-BREAKING

---

## 1. Summary of the Problem

Two interrelated bugs cause `sudo nixos-rebuild switch --flake /etc/nixos#vexos` to fail
with:

```
Failed assertions:
- You must set the option 'boot.loader.grub.devices' or
  'boot.loader.grub.mirroredBoots' to make the system bootable.
```

### Bug A — Impure `builtins.pathExists` in `modules/bootloader.nix`

`modules/bootloader.nix` line 17 contains:

```nix
isUefi = builtins.pathExists /sys/firmware/efi;
```

NixOS flakes evaluate in **pure mode** (`--pure-eval`) by default since Nix 2.4+.  
In pure evaluation mode the Nix evaluator is restricted to paths inside the Nix store.  
Accessing `/sys/firmware/efi` — a live kernel virtual filesystem — is outside the store.  
Nix silently returns `false` for `builtins.pathExists` on such paths in pure mode.

Result chain:
1. `isUefi = false` (always, in pure flake evaluation)
2. `type` option default resolves to `"grub"` (the `else` branch)
3. `cfg.grub.device` defaults to `"nodev"` (never overridden)
4. `lib.mkIf (cfg.type == "grub")` block activates and sets `boot.loader.grub.enable = true`
5. NixOS's built-in GRUB assertion fires because no device is specified

### Bug B — `bootloader.nix` is never imported

`hosts/default/configuration.nix` does not include `../../modules/bootloader.nix` in its
`imports` list. The implementation subagent created the file but forgot to wire it in.

Because the module is not imported, the `vexos.bootLoader` namespace is never declared.
There is also no `vexos.bootLoader.type` option set anywhere in `configuration.nix`.
Additionally, `configuration.nix` has no raw `boot.loader.*` fallback lines — these were
presumably removed by the implementation subagent with the intent that `bootloader.nix`
would own them, but the import was never added.

### Combined effect

Depending on what the user's `/etc/nixos/hardware-configuration.nix` contains:

- **If the installer-generated hardware config lacks boot.loader settings:** No bootloader
  is configured at all → NixOS aborts.
- **If `bootloader.nix` somehow gets loaded through another path with `isUefi = false`:**
  GRUB with `device = "nodev"` activates → NixOS's GRUB assertion fires as seen above.

Both bugs must be fixed together.

---

## 2. Files Read and Current State

### `modules/bootloader.nix` (current — broken)

Key offending section (lines 14–25):

```nix
let
  cfg      = config.vexos.bootLoader;
  isUefi   = builtins.pathExists /sys/firmware/efi;   ← impure, always false in pure mode
in {
  options.vexos.bootLoader = {
    type = lib.mkOption {
      type    = lib.types.enum [ "systemd-boot" "grub" ];
      default = if isUefi then "systemd-boot" else "grub";  ← resolves to "grub" in pure mode
```

The rest of the file — option declarations, assertion, `lib.mkMerge` config blocks — is
correct and matches the original `bootloader_module_spec.md` specification exactly.

### `hosts/default/configuration.nix` (current — broken)

Current imports block (lines 3–13):

```nix
  imports = [
    ../../modules/system.nix
    ../../modules/gnome.nix
    ../../modules/users.nix
    ../../modules/gpu.nix
    ../../modules/gaming.nix
    ../../modules/asus.nix
    ../../modules/flatpak.nix
    ../../modules/plymouth.nix
    ../../modules/kernel.nix
  ];
```

`../../modules/bootloader.nix` is absent. No `vexos.bootLoader.type` line exists anywhere
in the file. No raw `boot.loader.*` lines exist in the file either.

### `hosts/default/hardware-configuration.nix` (current — functional but inconsistent)

Bottom of file (lines 63–66) contains direct NixOS options:

```nix
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
```

These were added as a CI sentinel. They work correctly for template/CI evaluation because
they bypass the missing module. However, once `bootloader.nix` is imported and active,
having BOTH the module AND direct `boot.loader.*` settings in the template creates
redundancy. More critically, if the type were ever switched to `"grub"` for BIOS testing,
`bootloader.nix` would attempt to set `boot.loader.systemd-boot.enable = false` while
the template sets it to `true` — a conflicting definition error in NixOS module evaluation.

The template `hardware-configuration.nix` must be updated:
1. Remove the two direct `boot.loader.*` lines
2. Add the BIOS/legacy commented override block (per original `bootloader_module_spec.md`
   Section 5.3, which was never implemented)

### `README.md` (current — correct, no changes required)

The Fresh Install section contains exactly the clean 3-step flow the user wants:

1. Install git via `nix-shell -p git`
2. Write the thin flake with `tee` + `git init`
3. `sudo nixos-rebuild switch --flake /etc/nixos#vexos && reboot`

The README is correct as-is. No modifications needed.

---

## 3. Research: `builtins.pathExists` in Pure Flake Evaluation

`builtins.pathExists` is an impure Nix built-in that queries the real filesystem.  
NixOS flakes enforce `--pure-eval` which disallows access to paths outside the Nix store
during evaluation. The behavior on paths like `/sys/firmware/efi` in pure mode:

- Nix 2.4–2.18: `builtins.pathExists` on non-store absolute paths returns `false` silently
  in pure mode without throwing an error.
- Nix 2.19+: Same behavior — returns `false` for paths outside the store in pure mode.

This is by design: pure evaluation must be deterministic and reproducible across machines.
Access to live system paths (`/sys`, `/proc`, `/dev`) would make evaluation machine-specific
and non-reproducible, violating the flake guarantee.

**The fix:** Remove the `isUefi` binding entirely. Set `default = "systemd-boot"` as a
plain string. The option type is already `lib.types.enum [ "systemd-boot" "grub" ]`, so
the default is statically known, deterministic, and pure-evaluation safe.

The module header comment should be updated to remove the "Auto-detects UEFI vs BIOS at
evaluation time via /sys/firmware/efi" language and replace it with guidance for BIOS users
to override explicitly.

---

## 4. Exact Changes Required

### 4.1 `modules/bootloader.nix` — Remove impure detection, fix default

**Change:** Replace the header comment block and the `let` binding.

**Current (lines 1–25):**

```nix
# modules/bootloader.nix
#
# Declarative bootloader selection module.
# Auto-detects UEFI vs BIOS at evaluation time via /sys/firmware/efi.
#
# On BIOS/MBR systems, set the install disk in hardware-configuration.nix:
#   vexos.bootLoader.grub.device = "/dev/sda";  # replace with your actual disk
#
# To override auto-detection:
#   vexos.bootLoader.type = "systemd-boot";  # force UEFI
#   vexos.bootLoader.type = "grub";          # force BIOS

{ config, lib, ... }:

let
  cfg      = config.vexos.bootLoader;
  isUefi   = builtins.pathExists /sys/firmware/efi;
in {

  # ── Option Declaration ──────────────────────────────────────────────────
  options.vexos.bootLoader = {

    type = lib.mkOption {
      type    = lib.types.enum [ "systemd-boot" "grub" ];
      default = if isUefi then "systemd-boot" else "grub";
      description = ''
        Bootloader to configure. Auto-detected from /sys/firmware/efi at
        evaluation time: UEFI systems get systemd-boot, BIOS/MBR systems
        get grub. Override explicitly if auto-detection is incorrect.
          "systemd-boot" — UEFI systems with an EFI System Partition at /boot.
          "grub"         — Legacy BIOS/MBR systems (requires grub.device to be set).
      '';
    };
```

**Replace with:**

```nix
# modules/bootloader.nix
#
# Declarative bootloader selection module.
# Default: "systemd-boot" (UEFI). BIOS/MBR systems must explicitly override.
#
# To configure for BIOS/MBR in hardware-configuration.nix:
#   vexos.bootLoader.type = "grub";
#   vexos.bootLoader.grub.device = "/dev/sda";  # replace with your actual disk
#
# To explicitly confirm UEFI (redundant but clear):
#   vexos.bootLoader.type = "systemd-boot";

{ config, lib, ... }:

let
  cfg = config.vexos.bootLoader;
in {

  # ── Option Declaration ──────────────────────────────────────────────────
  options.vexos.bootLoader = {

    type = lib.mkOption {
      type    = lib.types.enum [ "systemd-boot" "grub" ];
      default = "systemd-boot";
      description = ''
        Bootloader to configure. Defaults to systemd-boot for UEFI systems.
        BIOS/MBR systems must set this to "grub" and also set grub.device.
          "systemd-boot" — UEFI systems with an EFI System Partition at /boot.
          "grub"         — Legacy BIOS/MBR systems (requires grub.device to be set).
      '';
    };
```

**No other changes to `bootloader.nix`** — the rest of the file (grub.device option,
assertion, mkMerge config blocks) is correct and must not be modified.

---

### 4.2 `hosts/default/configuration.nix` — Add import and explicit type

**Change 1:** Add `../../modules/bootloader.nix` as the first entry in imports.

**Current imports block:**

```nix
  imports = [
    ../../modules/system.nix
    ../../modules/gnome.nix
    ../../modules/users.nix
    ../../modules/gpu.nix
    ../../modules/gaming.nix
    ../../modules/asus.nix
    ../../modules/flatpak.nix
    ../../modules/plymouth.nix
    ../../modules/kernel.nix
  ];
```

**Replace with:**

```nix
  imports = [
    ../../modules/bootloader.nix
    ../../modules/system.nix
    ../../modules/gnome.nix
    ../../modules/users.nix
    ../../modules/gpu.nix
    ../../modules/gaming.nix
    ../../modules/asus.nix
    ../../modules/flatpak.nix
    ../../modules/plymouth.nix
    ../../modules/kernel.nix
  ];
```

**Change 2:** Add explicit bootloader type after the `gpu.type` line.

**Current (after imports block, around lines 15–17):**

```nix
  # GPU driver selection — set to "nvidia", "amd", "intel", or "none"
  gpu.type = "none";

  # Kernel selection — see `just list-kernels` for all options
```

**Replace with:**

```nix
  # GPU driver selection — set to "nvidia", "amd", "intel", or "none"
  gpu.type = "none";

  # Boot loader — "systemd-boot" (UEFI) or "grub" (BIOS/MBR)
  vexos.bootLoader.type = "systemd-boot";

  # Kernel selection — see `just list-kernels` for all options
```

---

### 4.3 `hosts/default/hardware-configuration.nix` — Remove direct boot.loader lines, add override comment

The current bottom section of the file contains a `── Bootloader ──` block with direct
options. These must be replaced to avoid conflicting definitions once the module is active.

**Current (bottom of file, approximately lines 52–66):**

```nix
  # ── Bootloader ────────────────────────────────────────────────────────────
  # nixos-generate-config sets the correct bootloader for your hardware.
  # This sentinel uses systemd-boot for CI (UEFI with vfat /boot above).
  # On a real machine, your generated hardware-configuration.nix already
  # has the correct settings — no manual changes needed.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
```

**Replace with:**

```nix
  # ── Bootloader override (BIOS/MBR / legacy VM) ───────────────────────────
  # The default in modules/bootloader.nix is "systemd-boot" (UEFI).
  # UEFI systems: no change needed here.
  # BIOS/MBR systems: uncomment and set the correct disk:
  # vexos.bootLoader.type = "grub";
  # vexos.bootLoader.grub.device = "/dev/sda";  # replace with your actual disk
}
```

**Why:** The module (`bootloader.nix`) now owns all `boot.loader.*` settings. Keeping
direct `boot.loader.systemd-boot.enable = true` in the template alongside the module
creates duplicate definitions. If `type = "grub"` is ever used for testing, the module
would set `boot.loader.systemd-boot.enable = false` while the template sets it `true` —
a conflicting definition error at equal priority in the NixOS module system.

---

### 4.4 `README.md` — No changes required

The 3-step install is already correct and clean:
1. `nix-shell -p git` — install git in shell
2. `tee /etc/nixos/flake.nix` + `git init` — write the thin flake
3. `sudo nixos-rebuild switch --flake /etc/nixos#vexos && reboot` — rebuild

No modifications to README.md.

---

## 5. Expected Behavior After Fix

| Scenario | Before Fix | After Fix |
|----------|-----------|-----------|
| UEFI system, thin flake install | Fails — GRUB assertion from impure detection | Passes — `type = "systemd-boot"` explicit default |
| BIOS system, `vexos.bootLoader.type = "grub"` set | Fails — module not imported, option unknown | Passes — GRUB activated with specified device |
| BIOS system, no override | Fails — same as above | Fails gracefully — custom assertion message guides user |
| CI / `nix flake check` in repo | May fail or produce unexpected behavior | Passes — module imported, default is "systemd-boot" |
| `nix eval .#nixosConfigurations.vexos...` | Fails — evaluation error | Returns `"string"` |

---

## 6. Files Modified

| Path | Change Type | Description |
|------|-------------|-------------|
| `modules/bootloader.nix` | Modified | Remove `isUefi` binding + impure `builtins.pathExists`; set `default = "systemd-boot"` |
| `hosts/default/configuration.nix` | Modified | Add `../../modules/bootloader.nix` to imports; add `vexos.bootLoader.type = "systemd-boot"` |
| `hosts/default/hardware-configuration.nix` | Modified | Replace direct `boot.loader.*` lines with commented `vexos.bootLoader` override block |
| `README.md` | No change | Already correct — 3-step install is intact |

---

## 7. Verification Steps

After implementation, run:

```bash
# 1. Flake evaluation check (catches all assertion and type errors)
nix flake check

# 2. Explicit evaluation test (confirms the configuration evaluates to a derivation)
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf
# Expected output: "string"

# 3. Confirm bootloader option is correct
nix eval .#nixosConfigurations.vexos.config.vexos.bootLoader.type
# Expected output: "systemd-boot"

# 4. Confirm systemd-boot is enabled
nix eval .#nixosConfigurations.vexos.config.boot.loader.systemd-boot.enable
# Expected output: true

# 5. Confirm GRUB is NOT enabled
nix eval .#nixosConfigurations.vexos.config.boot.loader.grub.enable
# Expected output: false
```

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| User's installer-generated hardware-configuration.nix also has `boot.loader.systemd-boot.enable = true` alongside the module | Medium | Both set the option to `true` — NixOS merges identical bool definitions without error |
| BIOS user doesn't set `vexos.bootLoader.type = "grub"` | Medium | Custom assertion in `bootloader.nix` fires with clear guidance message |
| Template hardware-configuration.nix change breaks CI | Low | The module default is `"systemd-boot"`, which is what the CI template was already testing |
| Conflicting definitions with other modules setting boot.loader options | Low | Module uses standard priority; `lib.mkForce` available if explicit overrides needed |
