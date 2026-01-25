{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "nixos-update" ''
      set -e

      echo "→ Updating NixOS configuration..."
      cd /etc/nixos

      git pull --rebase

      echo "→ Building and switching system..."
      sudo nixos-rebuild switch --flake .#vex-htpc

      echo "→ Cleaning old generations..."
      sudo nix-collect-garbage -d

      echo "✔ Update complete. Rollback available at boot."
    '')
  ];
}
