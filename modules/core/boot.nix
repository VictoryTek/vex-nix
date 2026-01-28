# Boot configuration
{ config, pkgs, lib, ... }:

let
  # Detect if system has an EFI partition (vfat at /boot or /boot/efi)
  hasEfiBootPartition = config.fileSystems ? "/boot" && 
    config.fileSystems."/boot".fsType == "vfat";
  hasEfiBootEfiPartition = config.fileSystems ? "/boot/efi" && 
    config.fileSystems."/boot/efi".fsType == "vfat";
  isEfi = hasEfiBootPartition || hasEfiBootEfiPartition;
  
  # Determine EFI mount point
  efiMountPoint = if hasEfiBootEfiPartition then "/boot/efi" else "/boot";
in
{
  # Use systemd-boot for UEFI, GRUB for legacy BIOS
  boot.loader = if isEfi then {
    # UEFI configuration
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = efiMountPoint;
    };
  } else {
    # Legacy BIOS configuration
    grub = {
      enable = true;
      device = "/dev/sda";  # Will be overridden by hardware-config if needed
      configurationLimit = 10;
    };
  };

  # Use CachyOS kernel (optimized for performance)
  boot.kernelPackages = pkgs.linuxPackages_cachyos;
}
