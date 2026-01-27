# AMD GPU configuration
# Import this module in hosts with AMD graphics cards
{ config, pkgs, lib, ... }:

{
  # Load AMDGPU driver (usually automatic, but explicit is clearer)
  services.xserver.videoDrivers = [ "amdgpu" ];
  
  # AMD-specific packages for hardware acceleration
  environment.systemPackages = with pkgs; [
    libva-utils
    vdpauinfo
    radeontop
  ];
  
  # ROCm support (optional - for compute workloads)
  # hardware.amdgpu.opencl.enable = true;
}
