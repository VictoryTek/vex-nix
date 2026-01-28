# User configuration
{ config, pkgs, lib, ... }:

{
  # Allow password changes to persist between rebuilds
  users.mutableUsers = true;

  # Default user - change password after first login with `passwd`
  users.users.nimda = {
    isNormalUser = true;
    description = "Admin User";
    extraGroups = [ 
      "wheel"           # sudo access
      "networkmanager"  # network configuration
      "video"           # GPU access
      "audio"           # audio devices
    ];
    # Initial password for first login (change it immediately!)
    initialPassword = "changeme";
  };

  # Ensure wheel group can use sudo
  security.sudo.enable = true;
}
