# VexOS

A modular NixOS configuration with GNOME, flakes, SSH, Samba, and Tailscale.

## Installation

From a fresh NixOS install:

1. **Clone this repository**
   ```bash
   git clone https://github.com/VictoryTek/vex-nix.git
   cd vex-nix
   ```

2. **Generate hardware configuration**
   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/default/hardware-configuration.nix
   ```

3. **Customize for your system**
   
   Edit these files:
   - `modules/users.nix` - Change username from "nimda"
   - `hosts/default/configuration.nix` - Update timezone and locale
   - `home/default.nix` - Update username and git config
   - `flake.nix` - Change hostname if not "vexos"

4. **Build and switch**
   ```bash
   sudo nixos-rebuild switch --flake .#vexos
   ```

5. **Reboot and log in**

## Automated Deployment

`scripts/deploy.sh` automates the full deployment cycle: it copies the repository
to `/etc/nixos/`, handles hardware configuration intelligently, and activates the
system via `nixos-rebuild switch`.

**Basic usage:**
```bash
sudo bash scripts/deploy.sh
```

**Available flags:**

| Flag | Description |
|------|-------------|
| `-y`, `--yes` | Skip all interactive confirmation prompts |
| `--regen-hardware` | Force regenerate `hardware-configuration.nix` via `nixos-generate-config` |
| `--keep-hardware` | Force keep existing `hardware-configuration.nix` from the current `/etc/nixos/` |
| `--dry-run` | Print what would happen — make no changes (does not require root) |
| `-h`, `--help` | Show usage and exit |

**Common examples:**
```bash
# Interactive deploy (prompts for confirmation and hardware config choice)
sudo bash scripts/deploy.sh

# Non-interactive deploy keeping existing hardware config (ideal for re-deploys)
sudo bash scripts/deploy.sh --yes --keep-hardware

# Force fresh hardware detection (use after adding new hardware)
sudo bash scripts/deploy.sh --yes --regen-hardware

# Preview all actions without making any changes
bash scripts/deploy.sh --dry-run
```

> **GPU note:** Before deploying, set `gpu.type` in `modules/gpu.nix` to match
> your hardware (`"nvidia"`, `"amd"`, or `"intel"`). Deploying with the wrong
> GPU driver can cause a broken graphical environment.

The script automatically backs up any existing `/etc/nixos/` to
`/etc/nixos.bak-<timestamp>/` before making changes, so rollback is always
possible.

## What's Included

- GNOME desktop with extensions
- SSH server
- Samba file sharing
- Tailscale VPN
- Home Manager for user configuration

## Post-Install

```bash
# Set Samba password
sudo smbpasswd -a nimda

# Connect to Tailscale
sudo tailscale up
```