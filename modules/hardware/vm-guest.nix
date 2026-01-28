# Virtual Machine Guest configuration
# Auto-detects hypervisor and enables appropriate guest services
{ config, pkgs, lib, modulesPath, ... }:

let
  # Read hypervisor info from DMI/SMBIOS (available at eval time via /sys)
  # This works because --impure allows reading system files
  hypervisorFile = "/sys/class/dmi/id/sys_vendor";
  productFile = "/sys/class/dmi/id/product_name";
  
  # Safely read file contents
  readFileOrEmpty = file: 
    if builtins.pathExists file then lib.strings.trim (builtins.readFile file) else "";
  
  sysVendor = readFileOrEmpty hypervisorFile;
  productName = readFileOrEmpty productFile;
  
  # Detect hypervisor type
  isQemu = lib.strings.hasInfix "QEMU" sysVendor || lib.strings.hasInfix "QEMU" productName;
  isVirtualBox = lib.strings.hasInfix "VirtualBox" productName || sysVendor == "innotek GmbH";
  isVMware = lib.strings.hasInfix "VMware" sysVendor || lib.strings.hasInfix "VMware" productName;
  isHyperV = sysVendor == "Microsoft Corporation" && lib.strings.hasInfix "Virtual" productName;
  
  isVM = isQemu || isVirtualBox || isVMware || isHyperV;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  config = lib.mkMerge [
    # Common VM settings
    (lib.mkIf isVM {
      # Helpful for debugging
      environment.etc."vex-hypervisor".text = ''
        Vendor: ${sysVendor}
        Product: ${productName}
        Detected: ${if isQemu then "QEMU/KVM" else if isVirtualBox then "VirtualBox" else if isVMware then "VMware" else if isHyperV then "Hyper-V" else "Unknown"}
      '';
    })

    # QEMU/KVM guest services
    (lib.mkIf isQemu {
      services.qemuGuest.enable = true;
      services.spice-vdagentd.enable = true;  # Clipboard sharing, dynamic resolution
    })

    # VirtualBox guest services
    (lib.mkIf isVirtualBox {
      virtualisation.virtualbox.guest.enable = true;
      virtualisation.virtualbox.guest.dragAndDrop = true;
    })

    # VMware guest services
    (lib.mkIf isVMware {
      virtualisation.vmware.guest.enable = true;
      services.xserver.videoDrivers = lib.mkDefault [ "vmware" ];
    })

    # Hyper-V guest services
    (lib.mkIf isHyperV {
      virtualisation.hypervGuest.enable = true;
    })
  ];
}
