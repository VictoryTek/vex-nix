{ config, lib, pkgs, ... }:

let
  hasNvidia = lib.any (d: d.vendor == "NVIDIA Corporation")
    (config.hardware.pci.devices or []);

  hasAMD = lib.any (d: d.vendor == "Advanced Micro Devices, Inc. [AMD/ATI]")
    (config.hardware.pci.devices or []);

  hasIntel = lib.any (d: d.vendor == "Intel Corporation")
    (config.hardware.pci.devices or []);
in
{
  imports =
    lib.optional hasNvidia ./nvidia-acceleration.nix
    ++ lib.optional hasAMD ./amd-acceleration.nix
    ++ lib.optional (hasIntel && !hasNvidia && !hasAMD)
         ./intel-acceleration.nix;
}
