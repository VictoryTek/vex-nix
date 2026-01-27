# NVIDIA GPU configuration
# Import this module in hosts with NVIDIA graphics cards
{ config, pkgs, lib, ... }:

{
  # Load NVIDIA driver
  services.xserver.videoDrivers = [ "nvidia" ];
  
  hardware.nvidia = {
    # Modesetting is required for Wayland
    modesetting.enable = true;
    
    # Power management (useful for laptops)
    powerManagement.enable = true;
    
    # Use proprietary driver (better codec support)
    open = false;
    
    # Enable nvidia-settings utility
    nvidiaSettings = true;
    
    # Use the stable driver by default
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  
  # NVIDIA-specific packages for hardware acceleration
  environment.systemPackages = with pkgs; [
    nvidia-vaapi-driver
    libva-utils
    vdpauinfo
  ];
  
  # Environment variables for NVIDIA on Wayland
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
  };
}
