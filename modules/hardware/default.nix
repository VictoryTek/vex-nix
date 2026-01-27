# Hardware module - common hardware configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./graphics.nix
  ];
  
  # Enable firmware updates
  services.fwupd.enable = true;
  
  # Enable all firmware including non-free
  hardware.enableAllFirmware = true;
}
