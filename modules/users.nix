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
      "libvirtd"
      "gamemode"
    ];
    
    # Set shell (optional)
    shell = pkgs.bash;
    # Start rootless Docker daemon at boot, before first interactive login.
    linger = true;

    # ── Authentication ─────────────────────────────────────────────────────
    # No default password is set (credential hygiene — avoids a known plaintext
    # secret being compiled into the world-readable Nix store).
    #
    # Set a password on first login via console:
    #   sudo passwd nimda
    #
    # For SSH access, add your public key to openssh.authorizedKeys.keys
    # and rebuild. Example:
    #   openssh.authorizedKeys.keys = [
    #     "ssh-ed25519 AAAA... your-key-here"
    #   ];
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = true;
}
