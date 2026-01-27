# Common packages module
{ config, pkgs, lib, ... }:

{
  imports = [
    ./cli-tools.nix
  ];
}
