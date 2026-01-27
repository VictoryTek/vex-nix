# Nix daemon and flake settings
{ config, pkgs, lib, ... }:

{
  # Enable flakes and new nix command
  nix = {
    settings = {
      # Enable flakes
      experimental-features = [ "nix-command" "flakes" ];
      
      # Optimize storage
      auto-optimise-store = true;
      
      # Allow unfree packages
      # Note: This is set per-evaluation, but having it here documents intent
    };
    
    # Garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
