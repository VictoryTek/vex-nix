{ config, pkgs, ... }:

{
  # Define user accounts
  users.users.vex = {
    isNormalUser = true;
    description = "Vex";
    extraGroups = [ 
      "networkmanager" 
      "wheel"          # Enable sudo
      "audio"
      "video"
    ];
    
    # Set shell (optional)
    shell = pkgs.bash;
    
    # Initial password - CHANGE THIS AFTER FIRST LOGIN
    # Use: passwd
    # Or set hashedPassword instead of initialPassword
    initialPassword = "changeme";
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = true;
}
