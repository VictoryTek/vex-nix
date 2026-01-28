# Virtual Machine Guest configuration
# Enables guest services for common hypervisors
# Each service only activates if its hypervisor is detected
{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # QEMU/KVM guest services
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;  # Clipboard sharing, dynamic resolution

  # VirtualBox guest services - conditional on VirtualBox detection
  virtualisation.virtualbox.guest.enable = lib.mkDefault true;
  virtualisation.virtualbox.guest.dragAndDrop = lib.mkDefault true;

  # VMware guest services  
  virtualisation.vmware.guest.enable = lib.mkDefault true;

  # Hyper-V guest services
  virtualisation.hypervGuest.enable = lib.mkDefault true;
}
