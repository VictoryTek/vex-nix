# Base networking configuration
{ config, pkgs, lib, ... }:

{
  # Enable NetworkManager for desktop/laptop use
  networking.networkmanager.enable = lib.mkDefault true;
  
  # Enable firewall with sane defaults
  networking.firewall = {
    enable = true;
    # Common ports can be opened per-variant
  };
}
