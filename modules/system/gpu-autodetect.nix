{ config, lib, pkgs, ... }:

{
  # Import all GPU acceleration modules unconditionally
  # They will be conditionally enabled based on detected hardware
  imports = [
    ./nvidia-acceleration.nix
    ./amd-acceleration.nix
    ./intel-acceleration.nix
  ];
}
