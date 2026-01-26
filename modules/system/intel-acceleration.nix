{ config, pkgs, lib, ... }:

let
  # Detect Intel GPU from lspci output
  hasIntelGpu = builtins.any (line: 
    (builtins.match ".*(VGA|3D|Display).*Intel.*" line != null)
  ) (lib.splitString "\n" (builtins.readFile "/proc/bus/pci/devices" or ""));
in
{
  # Hardware graphics acceleration for Intel GPUs
  # Suitable for 8th gen Intel and newer (including 12th gen Core i7-1265U)
  # Also works in VirtualBox with 3D acceleration enabled
  
  hardware.graphics = lib.mkIf hasIntelGpu {
    enable = true;
    enable32Bit = true;  # For 32-bit applications and compatibility
    
    extraPackages = with pkgs; [
      intel-media-driver   # iHD driver for Gen 8+ (VAAPI)
      intel-vaapi-driver   # i965 driver for Gen 5-7 (fallback)
      libvdpau-va-gl       # VDPAU support via VA-API
      intel-compute-runtime # OpenCL support for Intel
    ];
    
    # 32-bit support for hardware acceleration
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
      intel-vaapi-driver
    ];
  };
  
  # Set environment variables for VA-API
  # Use iHD driver for modern Intel GPUs (Gen 8+)
  environment.sessionVariables = lib.mkIf hasIntelGpu {
    LIBVA_DRIVER_NAME = "iHD";  # Use "i965" if you have Gen 5-7
  };

  # Add utilities to test hardware acceleration
  environment.systemPackages = lib.mkIf hasIntelGpu (with pkgs; [
    libva-utils   # Provides 'vainfo' command to check VA-API
    vdpauinfo     # Provides 'vdpauinfo' to check VDPAU
    vulkan-tools  # Provides 'vulkaninfo' for Vulkan support
    intel-gpu-tools # Intel-specific GPU utilities
  ]);
}
