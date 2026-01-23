# Emergency Boot Fix for VexHTPC

## If the system won't boot after the rebuild:

### Option 1: Boot into Previous Generation
1. At the bootloader (GRUB), select "NixOS - All configurations"
2. Select the previous generation (one before the latest)
3. System will boot with the old configuration

### Option 2: Rollback from Recovery
If you can access a root shell or recovery mode:
```bash
# List available generations
nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo /nix/var/nix/profiles/system-*-link/bin/switch-to-configuration boot

# Or rollback and activate immediately
sudo nixos-rebuild switch --rollback
```

### Option 3: Boot with systemd.unit=rescue.target
1. At GRUB, press 'e' to edit the boot entry
2. Add `systemd.unit=rescue.target` to the kernel command line
3. Press Ctrl+X or F10 to boot
4. Once in rescue mode, rollback the configuration

### Option 4: Remove Recent Changes
From a working boot (previous generation or rescue mode):
```bash
cd /etc/nixos
sudo git log  # Find the commit before the logo changes
sudo git revert HEAD  # Or git reset --hard <previous-commit>
sudo nixos-rebuild switch --flake /etc/nixos#vex-htpc --impure
```

## What might have caused the boot failure:

The logo changes themselves shouldn't prevent boot. Possible issues:
1. File path permissions issue
2. Concurrent changes to other system files
3. Plymouth configuration conflict
4. Boot service dependency issue

## To diagnose:
From a previous generation boot or rescue mode:
```bash
# Check system journal for errors
sudo journalctl -xb -p err

# Check the last rebuild
sudo journalctl -u nixos-rebuild.service

# Validate the current configuration
sudo nixos-rebuild dry-build --flake /etc/nixos#vex-htpc --impure
```
