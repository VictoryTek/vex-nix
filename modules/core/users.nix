# User configuration
{ config, pkgs, lib, ... }:

{
  # Allow users created during install to persist
  # NixOS won't manage users declaratively - keeps existing users from fresh install
  users.mutableUsers = true;

  # Default shell for new users
  programs.bash.enable = true;

  # Ensure wheel group can use sudo
  security.sudo.enable = true;
}
