{ config, lib, pkgs, ... }:

{
  ############################################
  # Generation & rollback safety
  ############################################

  # Keep enough generations for safety
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 15;
  boot.loader.grub.configurationLimit = lib.mkDefault 15;

  # Automatically rollback if boot fails
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.services.rollback-on-failure = {
    description = "Rollback to previous generation on boot failure";
    wantedBy = [ "initrd.target" ];
    after = [ "initrd-root-device.target" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "rollback-on-failure" ''
        if [ -e /run/boot-failed ]; then
          echo "Boot failed, rolling back to previous generation"
          /run/current-system/bin/switch-to-configuration boot
        fi
      '';
    };
  };

  ############################################
  # Make rollbacks easier
  ############################################

  environment.systemPackages = with pkgs; [
    nixos-rebuild
  ];

  ############################################
  # Safer upgrades
  ############################################

  nix.settings = {
    auto-optimise-store = true;
    keep-outputs = true;
    keep-derivations = true;
  };
}
