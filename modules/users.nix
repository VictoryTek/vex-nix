{ config, pkgs, ... }:

{
  # Define user accounts
  users.users.nimda = {
    isNormalUser = true;
    description = "Nimda";
    extraGroups = [ 
      "networkmanager" 
      "wheel"          # Enable sudo
      "audio"
      "video"
      "docker"
      "libvirtd"
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
