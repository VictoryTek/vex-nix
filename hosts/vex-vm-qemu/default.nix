# VexVM QEMU - Virtual Machine configuration for QEMU/KVM (GNOME Boxes, virt-manager, etc.)
{ config, pkgs, lib, inputs, modulesPath, ... }:

{
  imports = [
    # Hardware configuration - imported from system's /etc/nixos/
    /etc/nixos/hardware-configuration.nix
    
    # Core modules
    ../../modules/core
    
    # Desktop environment
    ../../modules/desktop
    
    # Hardware support
    ../../modules/hardware
    
    # QEMU guest profile
    (modulesPath + "/profiles/qemu-guest.nix")
    
    # Common packages
    ../../modules/packages
    
    # Flatpak support
    ../../modules/packages/flatpak.nix
    
    # System branding and customization
    ../../modules/system/system.nix
  ];

  # QEMU VM settings
  networking.hostName = "vex-vm-qemu";
  
  # QEMU/KVM guest services
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;  # Clipboard, dynamic resolution
  
  # VM packages
  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
  ];
  
  # Enable SSH for remote management
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };
}
