# User configuration
{ config, pkgs, lib, ... }:

{
  # Define the main user - override username per-host if needed
  users.users.vex = {
    isNormalUser = true;
    description = "VexOS User";
    extraGroups = [ 
      "wheel"           # sudo access
      "networkmanager"  # network configuration
      "video"           # GPU access
      "audio"           # audio devices
    ];
    # Default shell
    shell = pkgs.bash;
  };

  # Enable sudo without password for wheel group (optional, can be disabled)
  # security.sudo.wheelNeedsPassword = false;
}
