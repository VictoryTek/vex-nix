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