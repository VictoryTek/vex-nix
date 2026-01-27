# Intel GPU configuration
# Import this module in hosts with Intel integrated graphics
{ config, pkgs, lib, ... }:

{
  # Intel-specific packages for hardware acceleration
  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    libva-utils
    vdpauinfo
  ];
  
  # Hardware video acceleration
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver    # VAAPI driver for newer Intel GPUs (Broadwell+)
    intel-vaapi-driver    # VAAPI driver for older Intel GPUs
    libvdpau-va-gl        # VDPAU via VAAPI
  ];
}
