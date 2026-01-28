# Core module - imports all core system modules
# These are shared across all VexOS variants
{ config, pkgs, lib, ... }:

{
  imports = [
    ./nix-settings.nix
    ./boot.nix
    ./plymouth.nix
    ./networking.nix
    ./locale.nix
    ./users.nix
  ];
}
