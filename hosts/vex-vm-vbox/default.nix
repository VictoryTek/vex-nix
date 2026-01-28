# VexVM VirtualBox - Virtual Machine configuration for VirtualBox
{ config, pkgs, lib, inputs, ... }:

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
    
    # Common packages
    ../../modules/packages
    
    # Flatpak support
    ../../modules/packages/flatpak.nix
  ];

  # VirtualBox VM settings
  networking.hostName = "vex-vm-vbox";
  
  # Use LTS kernel for better VirtualBox compatibility
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;
  
  # VirtualBox guest services
  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;
  virtualisation.virtualbox.guest.clipboard = true;
  
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
