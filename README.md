# VexOS (NixOS)

Modular NixOS configurations for desktop, HTPC, and server systems.

## Installation

On a fresh NixOS install:

```bash
cd /etc/nixos

sudo git clone https://github.com/VictoryTek/vex-nix

sudo cp -r vex-nix/* .

sudo cp -r vex-nix/.git .

sudo rm -rf vex-nix

# Build and switch
sudo nixos-rebuild switch --flake .#vex-htpc
```

## Available Configurations

- `vex-os` - Desktop workstation (GNOME)
- `vex-htpc` - Home Theater PC (GNOME)
- `vex-svr` - Headless server