{ config, pkgs, lib, ... }:

{
  # Hardware graphics acceleration for NVIDIA GPUs
  # Uses proprietary NVIDIA drivers for best performance and codec support
  # Includes NVENC/NVDEC hardware encoding/decoding
  
  # Enable NVIDIA drivers
  services.xserver.videoDrivers = [ "nvidia" ];
  
  hardware = {
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
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";  # VA-API via nvidia-vaapi-driver
    NVD_BACKEND = "direct";        # Use direct backend for better performance
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";  # Explicit GLX vendor
  };

  # Add utilities to test hardware acceleration
  environment.systemPackages = with pkgs; [
    libva-utils      # Provides 'vainfo' command to check VA-API
    vdpauinfo        # Provides 'vdpauinfo' to check VDPAU
    vulkan-tools     # Provides 'vulkaninfo' for Vulkan support
    nvidia-vaapi-driver  # VA-API support for NVIDIA
    nvtopPackages.full   # NVIDIA GPU monitoring tool
  ];
}
