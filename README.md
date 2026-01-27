# VexOS (NixOS)

Modular NixOS configurations for desktop, HTPC, and server systems.

## Installation

On a fresh NixOS install:

```bash
# Clone to /etc/nixos
cd /etc/nixos
sudo git clone https://github.com/VictoryTek/vex-nix .

# Generate hardware config for this machine
sudo nixos-generate-config --show-hardware-config > /tmp/hardware.nix

# Copy to your host (replace vex-htpc with your variant)
sudo cp /tmp/hardware.nix hosts/vex-htpc/hardware-configuration.nix

# Edit host config to enable your GPU driver
sudo nano hosts/vex-htpc/default.nix
# Uncomment: ../../modules/hardware/nvidia.nix (or amd.nix / intel.nix)

# Build and switch
sudo nixos-rebuild switch --flake .#vex-htpc
```

## Available Configurations

- `vex-os` - Desktop workstation (GNOME)
- `vex-htpc` - Home Theater PC (GNOME)
- `vex-svr` - Headless server