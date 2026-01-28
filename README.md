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

# Build and switch (choose your variant below)
sudo nixos-rebuild switch --flake .#vex-htpc --impure
```

> **Note:** The `--impure` flag is required because configurations import your machine's auto-generated hardware config from `/etc/nixos/hardware-configuration.nix`. This allows you to deploy the same configuration on different hardware without editing any files.

## Available Configurations

### Desktop Variants
- **`vex-os`** - Main desktop workstation with GNOME
  ```bash
  sudo nixos-rebuild switch --flake .#vex-os --impure
  ```

### HTPC Variants
- **`vex-htpc`** - Home Theater PC with GNOME
  ```bash
  sudo nixos-rebuild switch --flake .#vex-htpc --impure
  ```

### Server Variants
- **`vex-svr`** - Headless server
  ```bash
  sudo nixos-rebuild switch --flake .#vex-svr --impure
  ```

### Virtual Machine Variants
- **`vex-vm-qemu`** - Virtual Machine for QEMU/KVM (GNOME Boxes, virt-manager)
  ```bash
  sudo nixos-rebuild switch --flake .#vex-vm-qemu --impure
  ```

- **`vex-vm-vbox`** - Virtual Machine for VirtualBox
  ```bash
  sudo nixos-rebuild switch --flake .#vex-vm-vbox --impure
  ```