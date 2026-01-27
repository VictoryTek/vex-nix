# Graphics configuration
# GPU-specific drivers should be enabled in host configurations
{ config, pkgs, lib, ... }:

{
  # Enable graphics support
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
