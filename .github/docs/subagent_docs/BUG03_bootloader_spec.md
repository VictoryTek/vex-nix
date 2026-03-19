# BUG-03 Specification — GRUB Hardcoded to `/dev/sda`: UEFI and Multi-Disk Bootloader Fix

**Severity:** High  
**Status:** Ready for Implementation  
**Affected Files:**
- `hosts/default/configuration.nix`
- `modules/plymouth.nix`

---

## 1. Current Configuration Analysis

### `hosts/default/configuration.nix` — lines 43–44

```nix
# Bootloader (legacy BIOS/MBR)
boot.loader.grub.enable = true;
boot.loader.grub.device = "/dev/sda";
```

These two lines establish a **legacy BIOS/MBR GRUB** configuration. This is the root cause of BUG-03.

### `hosts/default/hardware-configuration.nix` — lines 28–31 (the template)

```nix
fileSystems."/boot" = {
  device = "/dev/disk/by-label/boot";
  fsType = "vfat";
};
```

`fsType = "vfat"` is the **EFI System Partition (ESP)** format. This directly contradicts the BIOS/MBR GRUB configuration above. A BIOS/MBR GRUB installation writes its stage 2 into the MBR or a BIOS boot partition — it does not use a vfat ESP at `/boot`. Setting `grub.device = "/dev/sda"` alongside a vfat `/boot` is structurally incoherent.

### `modules/plymouth.nix` — lines 46–47

```nix
# Hide grub menu on boot (press Shift during POST to interrupt).
boot.loader.grub.timeoutStyle = "hidden";
boot.loader.timeout = 0;
```

`boot.loader.grub.timeoutStyle = "hidden"` is a **GRUB-specific** NixOS option. It only applies when GRUB is the active bootloader. When GRUB is replaced with systemd-boot, this setting becomes dead configuration — it has no effect and misleads future readers.

`boot.loader.timeout = 0` is **bootloader-agnostic** and applies to both GRUB and systemd-boot. It is correct and must be retained.

---

## 2. Problem Definition

### 2.1 Failure Mode: UEFI Systems (All Hardware Since ~2012)

All mainstream x86-64 hardware manufactured since approximately 2012 ships with UEFI firmware. BIOS/MBR compatibility mode (CSM) is frequently disabled by default in modern UEFI firmware. When a user installs VexOS on UEFI-only hardware with CSM disabled:

- `nixos-rebuild switch` will attempt to run `grub-install /dev/sda`
- `grub-install` in MBR mode will fail or silently corrupt the boot sector
- The system will fail to boot on next restart
- The failure is not caught at `nix flake check` time (it is a runtime/install error)

### 2.2 Failure Mode: Non-Stable Block Device Enumeration

`/dev/sda` is a kernel-assigned device name derived from SCSI/SATA enumeration order. This enumeration is **not stable** across hardware changes:

- Attaching a second disk or USB drive can cause `/dev/sda` to become `/dev/sdb`
- GRUB would then be written to the wrong drive
- NVMe drives are typically `/dev/nvme0n1`, not `/dev/sda` at all
- The correct NixOS pattern for GRUB BIOS-mode is to use disk IDs, not `/dev/sda`

### 2.3 Contradiction with the Template hardware-configuration.nix

VexOS's template `hardware-configuration.nix` (used for CI/testing via the in-repo `nixosConfigurations.vexos`) declares `/boot` with `fsType = "vfat"`. This is definitional evidence that VexOS targets UEFI systems. A BIOS/MBR GRUB install does not require or use a vfat `/boot`. The configuration is internally inconsistent.

### 2.4 Thin Flake Architecture Impact

`flake.nix` exports `lib.mkVexosSystem`. Downstream machines call:

```nix
nixosConfigurations.myhostname = vexos.lib.mkVexosSystem {
  hardwareModule = ./hardware-configuration.nix;
};
```

The `bootloader` settings in `hosts/default/configuration.nix` are pulled in for **every downstream consumer**. A hardcoded `/dev/sda` MBR GRUB setting propagates to all VexOS installs and will silently fail or corrupt the boot sector on any UEFI-only machine.

### 2.5 Mutual Exclusivity Confirmation

NixOS will produce a build evaluation error if **both** of the following are set simultaneously:

```nix
boot.loader.systemd-boot.enable = true;
boot.loader.grub.enable = true;
```

The `nixpkgs` GRUB module asserts:

```
You cannot use both systemd-boot and GRUB.
```

This means if any downstream thin flake also sets `boot.loader.systemd-boot.enable = true` (the current NixOS installer default on UEFI), it would conflict with VexOS's `grub.enable = true`. This is an additional reason the current configuration is dangerous.

---

## 3. Options Analysis

### Option A — Replace GRUB with `systemd-boot`

```nix
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
```

**Pros:**
- Correct and modern UEFI bootloader; the official NixOS-recommended approach
- The template `hardware-configuration.nix` already provides a vfat `/boot` (the ESP), so no disk layout changes are needed
- No device path required — systemd-boot installs to the ESP automatically
- Simpler: only 2 options needed vs. 4+ for GRUB UEFI
- `nix flake check` will pass cleanly
- Full compatibility with Plymouth's `boot.loader.timeout = 0`
- Thin flake consumers generating their `hardware-configuration.nix` with `nixos-generate-config` on UEFI hardware will always get a vfat `/boot` — fully compatible

**Cons:**
- Breaks BIOS/MBR legacy machines (no CSM). This is an acceptable constraint given VexOS's target audience (modern ASUS hardware, AMD/NVIDIA GPUs, GNOME)
- Can be overridden per-machine via `lib.mkDefault`

### Option B — Remove bootloader config entirely from `configuration.nix`

Defer all bootloader config to each machine's `hardware-configuration.nix`.

**Pros:**
- Maximum flexibility

**Cons:**
- Creates a dangerous omission: downstream users who forget to add bootloader config will get a system that evaluates but fails to install/boot
- `nix flake check` will fail without a bootloader defined (NixOS requires one)
- Contradicts VexOS's goal of being a turn-key configuration
- **Rejected**

### Option C — Keep GRUB, switch to UEFI mode

```nix
boot.loader.efi.canTouchEfiVariables = true;
boot.loader.grub.enable = true;
boot.loader.grub.efiSupport = true;
boot.loader.grub.device = "nodev";
```

**Pros:**
- Retains GRUB (chainloading, multi-boot menus, extensive theme support)

**Cons:**
- 4 options vs. 2 for systemd-boot
- GRUB UEFI installs a GRUB EFI binary, not just PXE/BCD entries — more state in the ESP
- `efiSysMountPoint` must match where `/boot` is mounted (default is `/boot`, which matches the template — so this would not require additional config, but is a footgun for users who mount it differently)
- No compelling advantage for VexOS's use case over systemd-boot
- **Rejected**

---

## 4. Recommended Fix: Option A — systemd-boot

**Rationale:**

1. The template `hardware-configuration.nix` already defines `/boot` as `vfat` — this is the EFI System Partition. The correct bootloader for this layout is systemd-boot.
2. VexOS targets modern hardware (ASUS laptops, AMD/NVIDIA GPU, GNOME — all require UEFI-capable firmware)
3. The NixOS official installer defaults to systemd-boot on UEFI hardware since NixOS 23.05
4. Eliminates both failure modes (UEFI incompatibility and `/dev/sda` instability) with the fewest moving parts
5. Thin flake consumers will have UEFI hardware in virtually all cases; any edge-case legacy machine owner can override via `lib.mkForce` in their own hardware configuration
6. `boot.loader.timeout = 0` in `modules/plymouth.nix` is already correct for systemd-boot

**BIOS Legacy Consideration:**
VexOS does not target legacy BIOS machines. The project README, existing module set (ASUS-specific module, modern GPU support), and the template hardware-configuration.nix all confirm a UEFI baseline. No BIOS compatibility module is warranted. A README note is sufficient for edge-case users.

---

## 5. Implementation Steps

### 5.1 `hosts/default/configuration.nix`

**Remove** (lines 42–44):
```nix
  # Bootloader (legacy BIOS/MBR)
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
```

**Replace with:**
```nix
  # Bootloader — systemd-boot for UEFI systems (all modern hardware since ~2012).
  # Requires /boot to be mounted as a vfat EFI System Partition (ESP).
  # See hardware-configuration.nix for the /boot mount definition.
  # Legacy BIOS/MBR machines are not supported; override with lib.mkForce if needed.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
```

No other changes are required in `configuration.nix`.

**Key options explained (NixOS 25.11):**

| Option | Value | Effect |
|--------|-------|--------|
| `boot.loader.systemd-boot.enable` | `true` | Installs `systemd-boot` to the ESP; replaces GRUB entirely |
| `boot.loader.efi.canTouchEfiVariables` | `true` | Allows `bootctl install` to write an EFI boot entry (NVRAM) — required on most hardware. Set to `false` only on systems that do not support NVRAM writes (rare, e.g., some Chromebooks or removable-media installs) |
| `boot.loader.efi.efiSysMountPoint` | *(not set — defaults to `/boot`)* | The ESP mount point. Default is `/boot`, which matches the template `hardware-configuration.nix`. Only set this explicitly if the ESP is mounted at `/boot/efi` instead |

### 5.2 `modules/plymouth.nix`

**Remove** (lines 46–47):
```nix
  # Hide grub menu on boot (press Shift during POST to interrupt).
  boot.loader.grub.timeoutStyle = "hidden";
```

**Reason:** `boot.loader.grub.timeoutStyle` is a GRUB-specific NixOS option. It is silently ignored when GRUB is disabled (does not cause a build error, but is dead/misleading configuration). It must be removed.

**Retain** (line 48 — no change):
```nix
  boot.loader.timeout = 0;
```

**Reason:** `boot.loader.timeout` is **bootloader-agnostic** in the NixOS module system. It controls the boot menu timeout for both GRUB and systemd-boot. Setting it to `0` instructs systemd-boot to auto-boot the default entry immediately without showing the menu (pressing Space or arrow keys during POST still opens the menu). This is the correct and officially documented approach for silent Plymouth boot. Source: [NixOS Wiki — Plymouth](https://wiki.nixos.org/wiki/Plymouth).

**Update the comment** on the remaining timeout line:
```nix
  # Hide the bootloader menu on boot (press Space during POST to interrupt).
  # Works for both systemd-boot and GRUB.
  boot.loader.timeout = 0;
```

#### Full diff for `modules/plymouth.nix` (lines 44–49 region):

Before:
```nix
  # Hide grub menu on boot (press Shift during POST to interrupt).
  boot.loader.grub.timeoutStyle = "hidden";
  boot.loader.timeout = 0;
```

After:
```nix
  # Hide the bootloader menu on boot (press Space during POST to interrupt).
  # Works for both systemd-boot and GRUB.
  boot.loader.timeout = 0;
```

---

## 6. Plymouth Impact

Plymouth does **not** depend on which bootloader is used. It runs in the initrd stage (via `boot.initrd.systemd.enable = true`, already set in the module). The only Plymouth-related change needed is:

1. Remove `boot.loader.grub.timeoutStyle = "hidden"` (GRUB-specific, unused with systemd-boot)
2. Retain `boot.loader.timeout = 0` (bootloader-agnostic, controls systemd-boot auto-boot behavior)
3. All kernel parameters (`quiet`, `splash`, etc.) are unaffected — they are passed to the kernel independent of the bootloader
4. `boot.initrd.kernelModules` entries are unaffected
5. `boot.initrd.systemd.enable = true` is unaffected (required for Plymouth's systemd initrd stage; works with systemd-boot)

The Plymouth splash screen experience will be **identical** after the fix.

---

## 7. Ripple Effects — All Affected Files

| File | Change Type | Change Summary |
|------|-------------|----------------|
| `hosts/default/configuration.nix` | Modify | Replace GRUB BIOS lines with systemd-boot lines |
| `modules/plymouth.nix` | Modify | Remove `grub.timeoutStyle` line, update comment on `timeout` |

No other files require changes:
- `flake.nix` — no change; `mkVexosSystem` is bootloader-agnostic
- `hosts/default/hardware-configuration.nix` — no change; vfat `/boot` is already correct for systemd-boot
- `scripts/install.sh` — no change; the script generates `hardware-configuration.nix` via `nixos-generate-config` which will correctly include the UEFI /boot mount; the bootloader is written by `nixos-rebuild switch`
- `README.md` — **optional enhancement**: add a note that VexOS requires UEFI (not strictly required for the fix, but recommended for user clarity)

---

## 8. Verification Steps

### 8.1 Flake Check (Required)

```bash
nix flake check
```

Expected: must pass with no errors. Previously, `nix flake check` would evaluate with GRUB enabled against the template hardware-configuration.nix — this only worked because GRUB evaluation doesn't require the disk to exist at eval time. After the fix, systemd-boot evaluation must also pass.

### 8.2 Configuration Evaluation (Required)

```bash
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf
```

Expected: `"derivation"` — confirms the full NixOS configuration evaluates to a valid derivation.

### 8.3 Build Test (Required)

```bash
sudo nixos-rebuild build --flake .#vexos
```

Expected: build succeeds. The boot closure will contain `systemd-boot` instead of GRUB packages.

### 8.4 Dead Configuration Check (Recommended)

Confirm that `boot.loader.grub.timeoutStyle` no longer appears in any VexOS module:

```bash
grep -r "grub.timeoutStyle" .
```

Expected: no output.

### 8.5 On Real Hardware / VM (Integration Verification)

After `nixos-rebuild switch --flake /etc/nixos#vexos`:

```bash
bootctl status
```

Expected output includes:
```
Current Boot Loader:
      Product: systemd-boot x.y
```

And:
```bash
ls /boot/EFI/systemd/
# systemd-bootx64.efi  (or equivalent)
```

Confirms systemd-boot was installed to the ESP.

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| **Existing users with BIOS machines break** | Medium | VexOS targets modern hardware; document UEFI as a requirement in README. Affected users can override with `boot.loader.grub.enable = lib.mkForce true` and set appropriate `grub.device` in their hardware config. |
| **`canTouchEfiVariables = true` fails on some hardware** | Low | Some hardware (Chromebooks, some embedded boards) does not support EFI NVRAM writes. These users should set `canTouchEfiVariables = false` and use `efiInstallAsRemovable` instead. This is out of scope for the default config. |
| **ESP not mounted at `/boot`** | Low | The template `hardware-configuration.nix` mounts the ESP at `/boot` (the systemd-boot default). Users with non-standard setups (e.g., ESP at `/boot/efi`) must set `boot.loader.efi.efiSysMountPoint = "/boot/efi"` in their hardware config. A README note is sufficient. |
| **Downstream thin flake consumers had GRUB working** | Low | Users with working BIOS GRUB installs will break on next rebuild if their hardware truly uses MBR/BIOS. However, any such user producing a `hardware-configuration.nix` via `nixos-generate-config` on UEFI hardware already has a vfat `/boot`, meaning GRUB was already misconfigured for them. The fix corrects their situation. |
| **`nix flake check` mutual exclusivity error** | None | No downstream thin flakes set `boot.loader.systemd-boot.enable` in VexOS itself — this is handled by VexOS's `configuration.nix`. No conflict. |

---

## 10. NixOS 25.11 API Reference (Context7 Verified)

Sources consulted:
- [NixOS Manual (unstable)](https://nixos.org/manual/nixos/unstable/) — `/websites/nixos_manual_nixos_unstable`
- [NixOS Wiki — Bootloader](https://wiki.nixos.org/wiki/Bootloader) — `/websites/wiki_nixos_wiki`
- [NixOS Wiki — Plymouth](https://wiki.nixos.org/wiki/Plymouth)
- [NixOS Wiki — systemd-boot](https://wiki.nixos.org/wiki/Systemd/boot)

**Confirmed current options for systemd-boot in NixOS 25.11:**

```nix
boot.loader.systemd-boot.enable = true;     # stable, widely documented
boot.loader.efi.canTouchEfiVariables = true; # stable, required for NVRAM boot entry
# boot.loader.efi.efiSysMountPoint = "/boot"; # optional, /boot is the default
```

**Confirmed GRUB UEFI mode (Option C — not chosen but documented):**

```nix
boot.loader.efi.canTouchEfiVariables = true;
boot.loader.grub.enable = true;
boot.loader.grub.efiSupport = true;
boot.loader.grub.device = "nodev";  # "nodev" for EFI-only, no MBR write
```

**Confirmed `boot.loader.timeout` is bootloader-agnostic:**

From NixOS Wiki (Plymouth article):
> `boot.loader.timeout = 0;` — "Hide the OS choice for bootloaders. It's still possible to open the bootloader list by pressing any key. It will just not appear on screen unless a key is pressed."

This applies to all NixOS-managed bootloaders including systemd-boot.
