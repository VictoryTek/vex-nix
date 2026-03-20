# Spec: README Fresh Install Workflow Fix

**Feature:** `readme_install_fix`  
**Date:** 2026-03-20  
**Status:** Ready for Implementation

---

## 1. Root Cause Analysis

### The Bug

The README's **"Fresh Install (New Machine)"** section is titled "From the NixOS live installer environment" but contains commands that are only valid on a **booted, installed system**:

| Step | Current (Broken) | Correct (Live ISO) |
|------|-------------------|--------------------|
| Flake target dir | `/etc/nixos/flake.nix` | `/mnt/etc/nixos/flake.nix` |
| Activate command | `sudo nixos-rebuild switch --flake /etc/nixos#vexos` | `sudo nixos-install --flake /mnt/etc/nixos#vexos` |
| Hardware config generation | Missing | `nixos-generate-config --root /mnt` |
| Partition/mount step | Missing | Mount root at `/mnt`, EFI at `/mnt/boot` |

### Why It Fails

`nixos-rebuild switch` requires that:
- The **target system is already booted** into NixOS
- `/boot` is a real mounted EFI partition

From a NixOS live ISO, `/boot` is not mounted because no disk has been set up. The error:

```
efiSysMountPoint = '/boot' is not a mounted partition. Is the path configured correctly?
```

…is the direct consequence. `nixos-rebuild switch` attempts to install a bootloader to `/boot`, which does not exist on the live ISO.

The correct tool for an initial system install is `nixos-install`, which:
- Reads the flake from a specified path (typically `/mnt/etc/nixos/`)
- Installs NixOS into the mounted target tree at `/mnt`
- Manages the bootloader installation to `/mnt/boot`

### Two Distinct Scenarios

The README currently conflates two separate workflows:

| Scenario | Context | Working Dir | Activate Command |
|----------|---------|-------------|-----------------|
| **A: Fresh install from live ISO** | NixOS live installer booted from USB | `/mnt/etc/nixos/` | `nixos-install --flake /mnt/etc/nixos#vexos` |
| **B: Converting an existing NixOS install** | Already running NixOS, switching to VexOS flake | `/etc/nixos/` | `nixos-rebuild switch --flake /etc/nixos#vexos` |

The README only has Scenario A steps but uses Scenario B commands.

---

## 2. Analysis of Existing Files

### `README.md` — Live ISO Section

**Problems:**
1. Claims to be "From the NixOS live installer environment" (Scenario A context)
2. Writes flake to `/etc/nixos/flake.nix` — this is the **live system's** config dir, not the target disk
3. Runs `nixos-rebuild switch` — fails because `/boot` is not mounted on the live ISO
4. Missing: partition/format disk step
5. Missing: mount root to `/mnt` and EFI to `/mnt/boot`
6. Missing: `nixos-generate-config --root /mnt` (generates `hardware-configuration.nix` on the target)
7. `nix-shell -p git` is unnecessary for the corrected workflow (see §4e below)

**The `install.sh` Warning Section:**  
The README's "Alternative (Not Recommended)" section positions `install.sh` as an alternative to the fresh install steps. This is misleading — `install.sh` is designed for **Scenario B only** and should be described as such.

### `scripts/install.sh` — Converting Existing Install Tool

**Assessment: Script logic is CORRECT for Scenario B.**

The script:
- Writes to `/etc/nixos/flake.nix` — correct for a booted system
- Ends by printing `sudo nixos-rebuild switch --flake /etc/nixos#${HOSTNAME}` — correct for a booted system
- Step 3 checks for `/etc/nixos/hardware-configuration.nix` — correct for a booted system

**However, the script's `usage()` text contains a misleading statement:**

```bash
Requires hardware-configuration.nix to already exist at /etc/nixos/.

  The NixOS live installer generates this with:
    sudo nixos-generate-config
```

The command `sudo nixos-generate-config` (without `--root /mnt`) writes to the **live system's** `/etc/nixos/`, not the target disk. If someone follows this hint from the live ISO and then runs `install.sh`, they end up with:
- `hardware-configuration.nix` in the live system's `/etc/nixos/` (valid for the live system, not the target)
- `install.sh` then writes `flake.nix` to the same `/etc/nixos/`
- `nixos-rebuild switch` in the final hint would still fail from the live ISO

**Fix needed in `install.sh`:** Update `usage()` to clarify this is for **converting an existing NixOS system**, not for fresh installs from the live ISO. The example command should say `sudo nixos-generate-config` is run **after** first booting into a freshly installed NixOS.

### `hosts/default/hardware-configuration.nix`

This is correctly a **template/sentinel** file (marked with `# This is a template hardware configuration`), which `install.sh` detects and rejects. No changes needed here.

### `flake.nix`

Exports `lib.mkVexosSystem { hardwareModule }`, which is what the thin consumer flake calls. No changes needed here.

---

## 3. Proposed Fix

### 3a. Does the flake write target change to `/mnt/etc/nixos/`?

**Yes.** For a live ISO fresh install, all operations target `/mnt/etc/nixos/`. The live system's `/etc/nixos/` is irrelevant.

### 3b. Does the activate command change to `nixos-install`?

**Yes.** Exact command:
```bash
sudo nixos-install --flake /mnt/etc/nixos#vexos
```

`nixos-install` reads the flake from `/mnt/etc/nixos/`, builds the NixOS closure, populates `/mnt`, and installs the bootloader to `/mnt/boot`.

### 3c. Does `nixos-generate-config --root /mnt` need to be an explicit step?

**Yes.** This is the central step that must be added. It must occur **before** writing the thin flake, because it creates `/mnt/etc/nixos/hardware-configuration.nix` and `/mnt/etc/nixos/configuration.nix` (the latter will be overwritten by the thin flake).

The full flag `--root /mnt` is essential — without it, `nixos-generate-config` writes into the live system's `/etc/nixos/`.

### 3d. What partition/mount steps are needed?

A minimal working example must precede the flake-writing steps. The README should include a concrete (but clearly hardware-specific) disk setup example. Best practice is to include:
1. Partition disk (GPT, EFI partition, root partition)
2. Format EFI as FAT32 with label `BOOT`, root as ext4 with label `nixos`
3. Mount root to `/mnt`
4. Create and mount `/mnt/boot`

A note should clarify that the partition layout is hardware-specific and the example uses common labels matching the template `hardware-configuration.nix`.

### 3e. Does the `nix-shell -p git` step need to stay?

**No — remove it from the live ISO workflow.**

Git is NOT required for `nixos-install --flake`. Nix evaluates the flake from the filesystem path directly. The git repo initialization was required under the old (incorrect) workflow because `nixos-rebuild switch` with pure evaluation demanded git-tracked files. `nixos-install` does not have this requirement.

After first boot, git will be available via the installed NixOS system when running `nixos-rebuild switch` for updates (the `update` alias in `home/default.nix` handles this). The git init for the update workflow happens post-reboot.

However, if the author prefers to keep the git init as documentation of future update workflow, it can optionally be kept with a clear comment. This spec recommends removing it to reduce steps and eliminate a potential failure point on minimal live ISOs.

### 3f. Should there be a separate "Converting an existing NixOS install" section?

**Yes.** The current README only has one installation section. The `install.sh` script is designed for Scenario B but is buried in an "Alternative (Not Recommended)" warning. The README should restructure into:

1. **Fresh Install (New Machine / Live ISO)** — the corrected Scenario A workflow
2. **Converting an Existing NixOS Install** — Scenario B, which is where `install.sh` belongs and where `nixos-rebuild switch` is the correct command

---

## 4. Exact Proposed README Content

### Section: Fresh Install (New Machine)

Replace the current "Fresh Install (New Machine)" section with:

```markdown
### Fresh Install (New Machine)

From the **NixOS live installer environment** (booted from the NixOS ISO):

#### Step 0 — Set up disks and mount

> These commands are hardware-specific. Adjust device names and sizes for your system.
> The labels used here (`nixos`, `BOOT`) match the template `hardware-configuration.nix`.

```bash
# Example: partition a single disk (GPT, EFI + ext4 root)
sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/sda -- set 1 esp on
sudo parted /dev/sda -- mkpart primary ext4 512MiB 100%

# Format
sudo mkfs.fat -F 32 -n BOOT /dev/sda1
sudo mkfs.ext4 -L nixos /dev/sda2

# Mount
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/BOOT /mnt/boot
```

#### Step 1 — Generate hardware configuration

```bash
sudo nixos-generate-config --root /mnt
```

This writes `/mnt/etc/nixos/hardware-configuration.nix` (and a stub `configuration.nix`)
based on the detected hardware.

#### Step 2 — Write the thin flake

```bash
sudo tee /mnt/etc/nixos/flake.nix > /dev/null <<'EOF'
{
  description = "VexOS local machine flake";

  inputs.vexos.url = "github:VictoryTek/vex-nix";

  outputs = { self, vexos }: {
    nixosConfigurations.vexos = vexos.lib.mkVexosSystem {
      hardwareModule = ./hardware-configuration.nix;
    };
  };
}
EOF
```

#### Step 3 — Generate `flake.lock`

```bash
cd /mnt/etc/nixos
nix --extra-experimental-features 'nix-command flakes' flake update
```

#### Step 4 — Install

```bash
sudo nixos-install --flake /mnt/etc/nixos#vexos
```

#### Step 5 — Reboot

```bash
sudo reboot
```

After rebooting into the installed system, `/etc/nixos/` will contain your three files
(`flake.nix`, `flake.lock`, `hardware-configuration.nix`). See **Keeping Your System Updated**
for the ongoing update workflow.
```

### Section: Converting an Existing NixOS Install

Add a new subsection after the Fresh Install section:

```markdown
### Converting an Existing NixOS Install

If you already have a running NixOS system and want to adopt VexOS:

1. **Generate (or verify) `hardware-configuration.nix`** at `/etc/nixos/`:
   ```bash
   sudo nixos-generate-config
   ```

2. **Write the thin flake**:
   ```bash
   sudo tee /etc/nixos/flake.nix > /dev/null <<'EOF'
   {
     description = "VexOS local machine flake";

     inputs.vexos.url = "github:VictoryTek/vex-nix";

     outputs = { self, vexos }: {
       nixosConfigurations.vexos = vexos.lib.mkVexosSystem {
         hardwareModule = ./hardware-configuration.nix;
       };
     };
   }
   EOF
   ```

3. **Initialise the git repo and generate `flake.lock`**:
   ```bash
   cd /etc/nixos
   git init -b main
   git add flake.nix hardware-configuration.nix
   nix --extra-experimental-features 'nix-command flakes' flake update
   git add flake.lock
   ```

4. **Activate**:
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#vexos
   ```

Or use `scripts/install.sh` which automates steps 2–3 above.
```

### Section: Alternative (install.sh)

Update the existing warning block to say "Converting an Existing Install" instead of framing it as an alternative to the fresh install:

```markdown
### ⚠️ Automated Option: `scripts/install.sh` (Existing Systems Only)
```

The warning text content stays unchanged. Add a single clarifying sentence at the start:

```markdown
> **Scope:** `install.sh` automates the **Converting an Existing NixOS Install** steps above.
> It is not suitable for fresh installs from the live ISO.
```

---

## 5. Changes to `scripts/install.sh`

### Required Change: `usage()` text

The `usage()` function contains misleading guidance:

```bash
# Current (misleading):
  The NixOS live installer generates this with:
    sudo nixos-generate-config
```

This implies you run the script from the live ISO after `nixos-generate-config` (no `--root`). Change to:

```bash
# Proposed:
  On a freshly installed system, generate this with:
    sudo nixos-generate-config
  (NOT for use from the live installer — see README for live ISO fresh install steps)
```

### No Logic Changes Required

The script's actual logic is correct for Scenario B:
- Targets `/etc/nixos/` (correct for a booted system)
- Final hint uses `nixos-rebuild switch` (correct for a booted system)
- Hardware config detection and sentinel check are correct

---

## 6. Step-by-Step Summary: What Changes, What Stays

| Item | Status | Change |
|------|--------|--------|
| README Fresh Install — context label | CHANGE | "From the NixOS live installer environment" (stays) |
| README Fresh Install — disk setup step | ADD | New Step 0: `parted`, `mkfs`, `mount /mnt` |
| README Fresh Install — `nixos-generate-config` | ADD | New Step 1: `nixos-generate-config --root /mnt` |
| README Fresh Install — flake target path | CHANGE | `/etc/nixos/` → `/mnt/etc/nixos/` |
| README Fresh Install — git init step | REMOVE | Not required for `nixos-install` |
| README Fresh Install — `nix-shell -p git` | REMOVE | Not required without git step |
| README Fresh Install — activate command | CHANGE | `nixos-rebuild switch` → `nixos-install --flake /mnt/etc/nixos#vexos` |
| README — New "Converting an Existing Install" section | ADD | Scenario B with `/etc/nixos/` + `nixos-rebuild switch` |
| README — `install.sh` warning section | CHANGE | Retitle + add scope note (existing-systems-only) |
| README — "Keeping Your System Updated" | KEEP | Unchanged (correct for booted system) |
| `scripts/install.sh` — logic | KEEP | Correct for Scenario B |
| `scripts/install.sh` — `usage()` text | CHANGE | Clarify: not for live ISO |
| `hosts/default/hardware-configuration.nix` | KEEP | No change |
| `flake.nix` | KEEP | No change |

---

## 7. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Partition example uses `/dev/sda` which may not match user's hardware | Wrap in comment box "hardware-specific, adjust device names" |
| User may attempt `nixos-install` without `flake.lock` | Step 3 (flake update) is explicit and must precede Step 4 |
| `nixos-install` may need network (to fetch flake inputs) | NixOS live ISO has networking by default; no special step needed |
| `nix --extra-experimental-features` is verbose | Keep as-is for explicitness; users can set in nix.conf after install |
| Removing git step may confuse users about the update workflow post-install | Mention in Step 5 note that git will be available after reboot |
| `install.sh` incorrectly used from live ISO after this change | `usage()` text change + README restructure makes scenarios unambiguous |

---

## 8. Verification Checklist

Before marking implementation complete, verify:

- [ ] README Fresh Install section no longer references `/etc/nixos/` for the live ISO path
- [ ] README Fresh Install section uses `nixos-install --flake /mnt/etc/nixos#vexos`
- [ ] README has a separate "Converting an Existing NixOS Install" section
- [ ] `scripts/install.sh` usage text clarifies "existing systems only"
- [ ] The flake.nix content itself is unchanged (same thin consumer flake)
- [ ] "Keeping Your System Updated" section is unchanged
- [ ] Post-Install section is unchanged

---

## 9. Files to Modify

1. `README.md`
2. `scripts/install.sh` (usage text only)
