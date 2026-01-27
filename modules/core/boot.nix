# Boot configuration
{ config, pkgs, lib, ... }:

{
  # Use systemd-boot (EFI)
  boot.loader = {
    systemd-boot = {
      enable = true;
      # Limit boot entries to prevent /boot from filling up
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = true;
  };

  # Use latest kernel by default (can be overridden per-host)
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
}
