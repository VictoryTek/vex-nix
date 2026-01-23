{ config, pkgs, lib, ... }:

{
  # Hardware graphics acceleration for AMD GPUs
  # Supports modern AMD Radeon cards with AMDGPU driver
  # For older cards, kernel parameters force amdgpu driver usage
  
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # For 32-bit applications and compatibility
    
    extraPackages = with pkgs; [
      amdvlk              # Vulkan driver
      rocm-opencl-icd     # OpenCL support
      rocm-opencl-runtime # OpenCL runtime
      libva               # VA-API support
    ];
    
    # 32-bit Vulkan support
    extraPackages32 = with pkgs.pkgsi686Linux; [
      driversi686Linux.amdvlk
    ];
  };
  
  # Force amdgpu driver for older AMD cards (Southern Islands/Sea Islands)
  # Comment out if you have a modern AMD GPU
  boot.kernelParams = [ 
    "radeon.si_support=0"   # Disable radeon driver for SI cards
    "amdgpu.si_support=1"   # Enable amdgpu for SI cards
    "radeon.cik_support=0"  # Disable radeon driver for CIK cards
    "amdgpu.cik_support=1"  # Enable amdgpu for CIK cards
  ];

  # Add utilities to test hardware acceleration
  environment.systemPackages = with pkgs; [
    libva-utils   # Provides 'vainfo' command to check VA-API
    vdpauinfo     # Provides 'vdpauinfo' to check VDPAU
    vulkan-tools  # Provides 'vulkaninfo' for Vulkan support
    clinfo        # Check OpenCL support
    radeontop     # AMD GPU monitoring tool
  ];
}
