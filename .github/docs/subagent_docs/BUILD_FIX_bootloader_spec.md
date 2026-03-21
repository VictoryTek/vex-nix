# BUILD_FIX_bootloader — Specification

**Status:** Ready for Implementation  
**Priority:** Critical — Blocks all deployments  
**Date:** 2026-03-21  
**Scope:** `modules/bootloader.nix`, `hosts/default/hardware-configuration.nix`, deployment workflow

---

## 1. Current Configuration Analysis

### 1.1 `flake.nix`

`mkVexosSystem` does **not** set any bootloader defaults. It assembles modules in this order:

1. `hardwareModule` (caller-supplied — the machine's `hardware-configuration.nix`)
2. `./hosts/default/configuration.nix`
3. Various external NixOS module inputs (nix-gaming, nix-flatpak, home-manager)

**Bootloader responsibility is fully delegated to the `hardwareModule` and
`modules/bootloader.nix` (imported via `configuration.nix`).** No bootloader
hardcoding occurs in `mkVexosSystem`.

The `nixosConfigurations.vexos` CI target uses `./hosts/default/hardware-configuration.nix`
as the `hardwareModule`. This is labelled "NOT the configuration deployed to real machines."

### 1.2 `hosts/default/configuration.nix`

Imports `../../modules/bootloader.nix`. **Does not set `vexos.bootLoader.type` or any
`boot.loader.*` option.** Bootloader selection is entirely deferred to the hardware module.
This is the correct design — bootloader choice is hardware-specific.

### 1.3 `hosts/default/hardware-configuration.nix` (in-repo template)

Current state of the relevant section:

```nix
# Filesystems
fileSystems."/" = {
  device = "/dev/disk/by-label/nixos";
  fsType = "ext4";
};

# fileSystems."/boot" = {
#   device = "/dev/disk/by-label/boot";  # Only needed for UEFI/ESP systems
#   fsType = "vfat";
# };

# ── Bootloader ────────────────────────────────────────────────────────────
# This VM uses legacy BIOS/MBR — override the default systemd-boot here.
vexos.bootLoader.type = "grub";
vexos.bootLoader.grub.device = "/dev/sda";  # UPDATE: verify with `lsblk`
```

**Key observations:**
- `vexos.bootLoader.type = "grub"` — CORRECT for BIOS/MBR
- `vexos.bootLoader.grub.device = "/dev/sda"` — placeholder; QEMU/KVM VMs often use `/dev/vda`
- `fileSystems."/boot"` entry is commented out — CORRECT for BIOS/MBR (no EFI partition needed)

### 1.4 `modules/bootloader.nix`

```nix
type = lib.mkOption {
  type    = lib.types.enum [ "systemd-boot" "grub" ];
  default = "systemd-boot";   # <── DANGEROUS DEFAULT for BIOS/MBR
  ...
};
```

When `cfg.type == "systemd-boot"`:
```nix
boot.loader.systemd-boot.enable      = true;
boot.loader.efi.canTouchEfiVariables = true;
```

When `cfg.type == "grub"`:
```nix
boot.loader.systemd-boot.enable = false;
boot.loader.grub.enable         = true;
boot.loader.grub.device         = cfg.grub.device;
```

The module is logically correct. The GRUB branch explicitly disables systemd-boot.
The `default = "systemd-boot"` is **the root structural risk** — any hardware
configuration that omits `vexos.bootLoader.type = "grub"` silently activates
the UEFI bootloader path.

### 1.5 `scripts/deploy.sh`

**DEPRECATED.** Prints a migration notice and exits 0. The script references
`/etc/nixos#vexos` in its help text but does not execute any rebuild command.
No active build breakage from this file.

### 1.6 `justfile`

```
rebuild:
    sudo nixos-rebuild switch --flake .#vexos

rebuild-boot:
    sudo nixos-rebuild boot --flake .#vexos
```

Uses `.#vexos` — the **current directory flake**. When invoked from
`/home/nimda/Projects/vex-nix`, this correctly builds the in-repo configuration.
**No path problem in the justfile.**

---

## 2. Root Cause Analysis

### Root Cause 1 — `bootloader.nix` introduced with unsafe default (PRIMARY)

During the codebase audit, `modules/bootloader.nix` was introduced as a declarative
bootloader abstraction. Its option `vexos.bootLoader.type` defaults to `"systemd-boot"`.

**Before the audit:** bootloader was configured directly in a module or hardware config
via native `boot.loader.*` options — likely `boot.loader.grub.enable = true` with an
explicit device. The BIOS/MBR VM booted successfully.

**After the audit:** The module abstraction replaced direct options. If the
`hardware-configuration.nix` in use at switch time did **not** include
`vexos.bootLoader.type = "grub"`, the module applied its default
(`"systemd-boot"`), which:

1. Enabled `boot.loader.systemd-boot.enable = true`
2. Set `boot.loader.efi.canTouchEfiVariables = true`
3. The `nixos-rebuild switch` activation script (`check-mountpoints`) verified
   that `/boot` is a mounted EFI System Partition — which it is not on a BIOS/MBR
   system — and aborted with:

```
efiSysMountPoint = '/boot' is not a mounted partition.
subprocess.CalledProcessError: Command '['.../check-mountpoints']' returned non-zero exit status 1.
Failed to install bootloader
```

### Root Cause 2 — `/etc/nixos` does not exist on the build machine

The README and `deploy.sh` both document the **thin local flake** workflow:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos
```

`/etc/nixos` does not exist on this machine (`ls -la /etc/nixos/` → exit code 2).
This means:

- Any procedure following the documented workflow fails immediately
- The `justfile` recipes (`just rebuild`, `just rebuild-boot`) use `--flake .#vexos`
  and work correctly **only** when invoked from `/home/nimda/Projects/vex-nix`
- There is no `/etc/nixos/hardware-configuration.nix` to provide machine-specific GRUB settings

### Root Cause 3 — Thin flake + auto-generated hardware config omits GRUB settings (STRUCTURAL)

The README's installation workflow:

1. Run `nixos-generate-config` (auto-generates `/etc/nixos/hardware-configuration.nix`)
2. Create `/etc/nixos/flake.nix` pointing to `github:VictoryTek/vex-nix`
3. Run `sudo nixos-rebuild switch --flake /etc/nixos#vexos`

`nixos-generate-config` output **never** includes `vexos.bootLoader.type` — it is a
VexOS-specific option unknown to NixOS tooling. The generated file will set raw
`boot.loader.*` options directly.

When the thin flake uses this generated hardware config:
- `vexos.bootLoader.type` is unset → defaults to `"systemd-boot"`
- Module activates UEFI path → `check-mountpoints` fails on BIOS/MBR

### Root Cause 4 — GRUB device path is a placeholder

`hosts/default/hardware-configuration.nix` sets:

```nix
vexos.bootLoader.grub.device = "/dev/sda";  # UPDATE: verify with `lsblk`
```

QEMU/KVM virtual machines typically expose disks as `/dev/vda` (virtio block device),
not `/dev/sda` (emulated SATA/IDE). If the VM uses virtio, GRUB installation will
fail with a "cannot find device" error after the bootloader module config issue is
fixed. This must be verified against the actual VM's block device name.

---

## 3. Proposed Solution

### 3.1 `hosts/default/hardware-configuration.nix` — verify and finalize device path

This file is the **authoritative hardware specification for the BIOS/MBR VM**. It is used:
- By `nixosConfigurations.vexos` in `flake.nix` for CI and local builds
- As the template for documenting expected hardware configuration

Required final state:

```nix
# ── Bootloader ────────────────────────────────────────────────────────────
# BIOS/MBR VM — overrides the default systemd-boot in modules/bootloader.nix.
# Verified device: run `lsblk -d -o NAME,TYPE | grep disk` to confirm.
vexos.bootLoader.type = "grub";
vexos.bootLoader.grub.device = "/dev/vda";  # Use /dev/sda for SATA/IDE; /dev/vda for virtio
```

The `/boot` filesystem entry must remain commented out:

```nix
# fileSystems."/boot" is intentionally absent for BIOS/MBR systems.
# GRUB does not require a dedicated EFI System Partition.
```

**Implementation note:** The implementer MUST run `lsblk` on the target VM to confirm
the correct device (`/dev/sda` vs `/dev/vda`). Default to `/dev/vda` for QEMU/KVM VMs.

### 3.2 `modules/bootloader.nix` — add explicit NixOS assertion to catch omitted type

The module default of `"systemd-boot"` cannot be changed to `"grub"` without also
requiring `grub.device`, which breaks UEFI machines that use this via thin flakes.
Instead, add an assertion that fires if the option is left at its default on a system
that has no EFI partition:

No change required to the module logic itself — it is structurally sound. The assertion
already present (`grub.device != "nodev"`) is sufficient to catch unconfigured GRUB.

**No changes needed to `modules/bootloader.nix`.**

### 3.3 `scripts/install.sh` — must inject GRUB settings for BIOS/MBR machines

Read the install script to determine if it needs updating. The thin flake install
workflow must prompt the user for their bootloader type and disk device, then inject
the correct `vexos.bootLoader.*` options into the thin flake's
`hardware-configuration.nix` (or add a separate bootloader override file).

This is a **separate implementation task** and is out of scope for this immediate
build fix. It is documented here as a required follow-on.

### 3.4 No changes to `configuration.nix`

`configuration.nix` correctly does **not** set any bootloader options. Bootloader
configuration is hardware-specific and belongs exclusively in `hardware-configuration.nix`.
This must not change.

### 3.5 No changes to `justfile` or `deploy.sh`

- `justfile` is correct: uses `--flake .#vexos` with the local repo
- `deploy.sh` is deprecated and harmless

---

## 4. Implementation Steps

### Step 1 — Verify the VM's disk device name

Run on the target VM:
```bash
lsblk -d -o NAME,TYPE | grep disk
```

Expected output examples:
- `sda   disk` → use `/dev/sda` (SATA emulation)
- `vda   disk` → use `/dev/vda` (virtio block)

### Step 2 — Update `hosts/default/hardware-configuration.nix`

**File:** `hosts/default/hardware-configuration.nix`

Changes:
1. Update `vexos.bootLoader.grub.device` to the correct device (verified in Step 1)
2. Add an explicit comment clarifying the `/boot` filesystem is intentionally absent
3. Verify no uncommented `fileSystems."/boot"` entry exists

**Before:**
```nix
vexos.bootLoader.type = "grub";
vexos.bootLoader.grub.device = "/dev/sda";  # UPDATE: verify with `lsblk`
```

**After (if virtio disk):**
```nix
vexos.bootLoader.type = "grub";
vexos.bootLoader.grub.device = "/dev/vda";  # virtio block device (QEMU/KVM default)
# fileSystems."/boot" is intentionally absent — BIOS/MBR does not use an EFI partition.
```

**After (if SATA/IDE disk):**
```nix
vexos.bootLoader.type = "grub";
vexos.bootLoader.grub.device = "/dev/sda";  # SATA/IDE disk
# fileSystems."/boot" is intentionally absent — BIOS/MBR does not use an EFI partition.
```

### Step 3 — Validate with nix flake check

```bash
cd /home/nimda/Projects/vex-nix
nix flake check
```

Expected: no errors. The `nixosConfigurations.vexos` target uses the in-repo
`hardware-configuration.nix`, which must evaluate successfully.

### Step 4 — Evaluate the configuration type

```bash
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf
```

Expected output: `"string"`

### Step 5 — Verify GRUB is selected (not systemd-boot)

```bash
nix eval .#nixosConfigurations.vexos.config.boot.loader.grub.enable
# Expected: true

nix eval .#nixosConfigurations.vexos.config.boot.loader.systemd-boot.enable
# Expected: false
```

### Step 6 — Apply rebuild (on the target VM)

```bash
cd /home/nimda/Projects/vex-nix
just rebuild
```

Or directly:
```bash
sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos
```

---

## 5. Risks and Mitigations

### Risk 1 — Wrong disk device → GRUB install fails differently

**Probability:** Medium (virtio vs SATA depends on VM config)  
**Impact:** High — boot fails; system unbootable after reboot  
**Mitigation:** Always run `lsblk` before setting `grub.device`. Use
`/dev/disk/by-id/...` paths for stability if available. Test with
`nixos-rebuild boot` (not `switch`) first to avoid breaking current running system.

### Risk 2 — Thin flake machines without GRUB settings remain broken

**Probability:** High — any machine bootstrapped via README workflow  
**Impact:** Medium — new machines can't be deployed without manual intervention  
**Mitigation:** Update `scripts/install.sh` to inject `vexos.bootLoader.type = "grub"`
into the thin flake's hardware config. This is a follow-on task.

### Risk 3 — Stale `flake.lock` at `/etc/nixos` points to old GitHub revision

**Probability:** N/A — `/etc/nixos` does not exist on this machine  
**Impact:** None currently  
**Mitigation:** If the thin flake workflow is re-established at `/etc/nixos`, run
`sudo nix flake update` before the first rebuild to pick up current repo state.

### Risk 4 — `boot.loader.grub.device` conflicts with existing NixOS hardware config options

**Probability:** Low — `vexos.bootLoader.type = "grub"` in hardware config, combined
with `modules/bootloader.nix` setting `boot.loader.grub.*`, should not conflict since
`nixos-generate-config` output is not imported here (only the in-repo template is used)  
**Impact:** Medium — NixOS module system would throw a "conflicting definitions" error  
**Mitigation:** Ensure any existing raw `boot.loader.*` assignments in hardware config
are removed when switching to the `vexos.bootLoader.*` abstraction.

---

## 6. Summary

| Item | Status | Required Action |
|------|--------|----------------|
| `modules/bootloader.nix` logic | ✅ Correct | None |
| `configuration.nix` bootloader settings | ✅ Absent (correct) | None |
| `hardware-configuration.nix` type | ✅ Set to `"grub"` | Confirm device path |
| `hardware-configuration.nix` device | ⚠️ Placeholder `/dev/sda` | Verify with `lsblk` |
| `fileSystems."/boot"` entry | ✅ Commented out | None |
| `justfile` rebuild path | ✅ Uses `.#vexos` | None |
| `deploy.sh` | ✅ Deprecated/harmless | None |
| Thin flake install workflow | ❌ Auto-generated hw config lacks `vexos.bootLoader` | Follow-on task |
| `/etc/nixos` existence | ❌ Missing | Use `just rebuild` or full path |

**Minimal fix:** Verify and finalize `vexos.bootLoader.grub.device` in
`hosts/default/hardware-configuration.nix`. The rest of the module structure
is sound. Run `nix flake check` and `just rebuild` from the repo directory.
