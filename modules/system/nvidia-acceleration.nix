{ config, pkgs, lib, ... }:

let
  # Detect NVIDIA GPU from lspci output
  pciDevicesPath = "/proc/bus/pci/devices";
  pciDevicesContent = if builtins.pathExists pciDevicesPath 
    then builtins.readFile pciDevicesPath 
    else "";
  hasNvidiaGpu = builtins.any (line: 
    (builtins.match ".*(VGA|3D|Display).*NVIDIA.*" line != null) ||
    (builtins.match ".*(VGA|3D|Display).*GeForce.*" line != null)
  ) (lib.splitString "\n" pciDevicesContent);
in
{
  # Hardware graphics acceleration for NVIDIA GPUs
  # Uses proprietary NVIDIA drivers for best performance and codec support
  # Includes NVENC/NVDEC hardware encoding/decoding
  
  # Enable NVIDIA drivers only if NVIDIA GPU detected
  services.xserver.videoDrivers = lib.mkIf hasNvidiaGpu [ "nvidia" ];
  
  hardware = lib.mkIf hasNvidiaGpu {
    nvidia = {
      # Enable modesetting (required for Wayland)
      modesetting.enable = true;
      
      # Enable power management (helps with laptops)
      powerManagement.enable = true;
      
      # Use proprietary driver (better codec support than open)
      open = false;
      
      # Enable nvidia-settings utility
      nvidiaSettings = true;
      
      # Use production/stable driver branch
      package = config.boot.kernelPackages.nvidiaPackages.production;
    };
    
    graphics = {
      enable = true;
      enable32Bit = true;  # For 32-bit applications and compatibility
    };
  };
  
  # Set environment variables for NVIDIA hardware acceleration
  environment.sessionVariables = lib.mkIf hasNvidiaGpu {
    LIBVA_DRIVER_NAME = "nvidia";  # VA-API via nvidia-vaapi-driver
    NVD_BACKEND = "direct";        # Use direct backend for better performance
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";  # Explicit GLX vendor
  };

  # Add utilities to test hardware acceleration
  environment.systemPackages = lib.mkIf hasNvidiaGpu (with pkgs; [
    libva-utils      # Provides 'vainfo' command to check VA-API
    vdpauinfo        # Provides 'vdpauinfo' to check VDPAU
    vulkan-tools     # Provides 'vulkaninfo' for Vulkan support
    nvidia-vaapi-driver  # VA-API support for NVIDIA
    nvtopPackages.full   # NVIDIA GPU monitoring tool
  ]);
}
