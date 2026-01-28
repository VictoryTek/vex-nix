# User configuration
{ config, pkgs, lib, ... }:

{
  # Mutable users allows passwords to persist in /etc/shadow
  # (this is the default, but being explicit)
  users.mutableUsers = true;

  # Primary user - password is set via `passwd` command or during install
  # No password is declared here so it won't be overwritten on rebuild
  users.users.nimda = {
    isNormalUser = true;
    extraGroups = [ 
      "wheel"           # sudo access
      "networkmanager"  # network configuration
      "video"           # GPU access
      "audio"           # audio devices
    ];
  };
}
