# Bootloader Module Specification

**Feature:** `bootloader_module`
**Date:** 2026-03-20
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current Configuration Analysis

### Relevant Files

| File | Role |
|------|------|
| `modules/gpu.nix` | Pattern to mirror — declarative option enum with `lib.mkMerge` / `lib.mkIf` |
| `hosts/default/configuration.nix` | Contains hardcoded boot loader config to be replaced |
| `hosts/default/hardware-configuration.nix` | Template hardware file; receives the usage comment |
| `flake.nix` | Defines `mkVexosSystem`; no changes required |

### Current Hardcoded Boot Loader Block (in `configuration.nix`, lines 46–51)

```nix
# Bootloader (UEFI — systemd-boot)
# Requires an EFI System Partition mounted at /boot (vfat).
# For legacy BIOS/MBR hardware, override in hardware-configuration.nix:
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub.enable = true;
#   boot.loader.grub.device = "/dev/sdX";  # replace with your actual disk
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
```

### gpu.nix Pattern Summary

- Top-level `options.<name>` block with `lib.mkOption` using `lib.types.enum`
- `config = lib.mkMerge [ (lib.mkIf ...) ... ]` blocks for conditional activation
- `let cfg = config.<name>; in { ... }` binding
- Namespace is a flat top-level attribute (e.g., `gpu.type`), **not** nested under `vexos.*`

> **Note:** The spec requested `vexos.bootLoader.type` as the option path. After
> reviewing gpu.nix (which uses `gpu.type` at the top level), the implementation
> **must use `vexos.bootLoader.type`** as explicitly required by the task. This is
> a deliberate deviation from gpu.nix's flat namespace — the sub-namespace `vexos`
> groups VexOS-specific options and avoids collision with NixOS builtins.

---

## 2. Problem Definition

`hosts/default/configuration.nix` unconditionally enables systemd-boot and sets
`canTouchEfiVariables = true`. On any BIOS/MBR system (including VMs configured
for legacy boot), this causes NixOS evaluation to abort with:

```
error: efiSysMountPoint = '/boot' is not a mounted partition
```

There is no declarative escape hatch short of editing `configuration.nix` — an
anti-pattern for a shared/reusable config.

---

## 3. Proposed Solution Architecture

Add `modules/bootloader.nix` following the gpu.nix pattern. The module exposes
two options under the `vexos.bootLoader` namespace:

- **`vexos.bootLoader.type`** — enum selecting the boot loader stack
- **`vexos.bootLoader.grub.device`** — disk path used only when type is `"grub"`

`configuration.nix` sets the default (`"systemd-boot"`) as a single declarative
line. Per-host hardware files can override to `"grub"` without touching shared
config.

---

## 4. Implementation Steps

### Step 1 — Create `modules/bootloader.nix`

### Step 2 — Update `hosts/default/configuration.nix`
- Add `../../modules/bootloader.nix` to imports
- Remove the existing 7-line boot loader comment + two `boot.loader.*` lines
- Add `vexos.bootLoader.type = "systemd-boot";` with a short inline comment

### Step 3 — Update `hosts/default/hardware-configuration.nix`
- Add a single commented override block at the bottom of the file showing the
  BIOS/legacy pattern

### Step 4 — Update `README.md`
- Insert a BIOS/legacy boot note between step 2 and step 3 of the Fresh Install
  section

---

## 5. Exact Nix Code

### 5.1 New File: `modules/bootloader.nix`

```nix
# modules/bootloader.nix
#
# Declarative boot loader selection module.
# Set `vexos.bootLoader.type` in your host configuration to configure the
# appropriate boot loader. Supported values: "systemd-boot", "grub".
#
# Usage example in hosts/default/configuration.nix:
#   vexos.bootLoader.type = "systemd-boot";
#
# To override for BIOS/MBR in hardware-configuration.nix:
#   vexos.bootLoader.type = "grub";
#   vexos.bootLoader.grub.device = "/dev/sda";

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
        Select the boot loader to configure.
          "systemd-boot" — UEFI systems. Requires an EFI System Partition
                           mounted at /boot (vfat). Default for VexOS.
          "grub"         — BIOS/MBR systems or VMs using legacy boot.
                           Set vexos.bootLoader.grub.device to the target disk.
      '';
    };

    grub.device = lib.mkOption {
      type    = lib.types.str;
      default = "nodev";
      description = ''
        Disk to install GRUB to (e.g. "/dev/sda").
        Only used when vexos.bootLoader.type = "grub".
        Use "nodev" only if the target disk is set elsewhere.
      '';
    };
  };

  # ── Configuration ───────────────────────────────────────────────────────
  config = lib.mkMerge [

    # ── systemd-boot (UEFI) ────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "systemd-boot") {
      boot.loader.systemd-boot.enable    = true;
      boot.loader.efi.canTouchEfiVariables = true;
    })

    # ── GRUB (BIOS/MBR) ────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "grub") {
      boot.loader.systemd-boot.enable = false;
      boot.loader.grub = {
        enable = true;
        device = cfg.grub.device;
      };
    })

  ]; # end mkMerge

}
```

---

### 5.2 Updated `hosts/default/configuration.nix`

#### Imports block — add one line

Replace:
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

With:
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

#### Bootloader lines — replace with declarative option

Remove (the entire comment block plus two option lines):
```nix
  # Bootloader (UEFI — systemd-boot)
  # Requires an EFI System Partition mounted at /boot (vfat).
  # For legacy BIOS/MBR hardware, override in hardware-configuration.nix:
  #   boot.loader.systemd-boot.enable = false;
  #   boot.loader.grub.enable = true;
  #   boot.loader.grub.device = "/dev/sdX";  # replace with your actual disk
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
```

Add:
```nix
  # Boot loader — set to "systemd-boot" (UEFI) or "grub" (BIOS/MBR)
  vexos.bootLoader.type = "systemd-boot";
```

---

### 5.3 Updated `hosts/default/hardware-configuration.nix`

Append the following block at the end of the file, before the closing `}`:

```nix
  # ── Boot loader override (BIOS/MBR / legacy VM) ──────────────────────────
  # Uncomment and set the correct disk if this system uses BIOS/legacy boot:
  # vexos.bootLoader.type = "grub";
  # vexos.bootLoader.grub.device = "/dev/sda";
```

---

### 5.4 Updated `README.md`

In the **Fresh Install** section, insert the following note between step 2 and
step 3:

```markdown
   > **BIOS/legacy boot systems only:** If your hardware or VM uses legacy
   > (non-UEFI) boot, add the following to `/etc/nixos/hardware-configuration.nix`
   > before rebuilding:
   > ```nix
   > vexos.bootLoader.type = "grub";
   > vexos.bootLoader.grub.device = "/dev/sda";  # replace with your actual disk
   > ```
   > UEFI systems can skip this step.
```

---

## 6. NixOS Options Used

| Option | Source | Notes |
|--------|--------|-------|
| `boot.loader.systemd-boot.enable` | NixOS core | Stable in 24.05+ |
| `boot.loader.efi.canTouchEfiVariables` | NixOS core | Required for systemd-boot |
| `boot.loader.grub.enable` | NixOS core | Stable across all versions |
| `boot.loader.grub.device` | NixOS core | Target disk for MBR install |
| `lib.mkMerge` / `lib.mkIf` | nixpkgs lib | Standard conditional module pattern |
| `lib.types.enum` / `lib.types.str` | nixpkgs lib | Standard option types |

No new flake inputs or external packages required.

---

## 7. Files Modified

| Path | Change Type |
|------|-------------|
| `modules/bootloader.nix` | **NEW** |
| `hosts/default/configuration.nix` | Modified (imports + option line) |
| `hosts/default/hardware-configuration.nix` | Modified (comment block appended) |
| `README.md` | Modified (BIOS note inserted in Fresh Install) |

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Existing hosts using raw `boot.loader.*` conflict with module defaults | Low | `lib.mkMerge` + `lib.mkIf` only sets options when the matching type is selected; raw overrides in hardware files take priority via `lib.mkDefault` / `lib.mkForce` if needed |
| `"grub"` path with `device = "nodev"` leaves system unbootable | Low | Default is `"systemd-boot"`; grub path requires explicit device opt-in; `"nodev"` is documented as requiring separate device config |
| Option namespace collision with future VexOS modules | Low | `vexos.bootLoader` sub-namespace is scoped and unlikely to conflict with NixOS builtins |
| Users on BIOS systems rebuild before seeing the note | Medium | README note is inserted before the rebuild step (step 3); comment in hardware-configuration.nix template also visible at rest |

---

## 9. Validation Criteria (for Review Phase)

- [ ] `nix flake check` passes with no errors
- [ ] `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf` returns `"string"`
- [ ] `modules/bootloader.nix` follows gpu.nix structure exactly (header comment, `let cfg`, options block, `lib.mkMerge` config block)
- [ ] `configuration.nix` contains no raw `boot.loader.*` lines
- [ ] `vexos.bootLoader.type = "systemd-boot";` present in `configuration.nix`
- [ ] `../../modules/bootloader.nix` is the first import in the imports list
- [ ] BIOS override comment present in `hardware-configuration.nix`
- [ ] README BIOS note appears between step 2 and step 3
