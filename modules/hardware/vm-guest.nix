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

  # VirtualBox guest services
  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;

  # VMware guest services  
  virtualisation.vmware.guest.enable = true;

  # Hyper-V guest services
  virtualisation.hypervGuest.enable = true;
}
