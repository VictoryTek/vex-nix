# modules/asus.nix
#
# ASUS TUF / ROG laptop support module.
# Provides: asusd (fan control, LED, profiles), supergfxd (GPU switching),
#           rog-control-center (GUI), and Bazzite-inspired power tweaks.
#
# This module should only be imported on ASUS TUF / ROG hardware.
# On non-ASUS systems, remove or comment out this import from configuration.nix.

{ config, pkgs, ... }:

{
  # ── asusd — ASUS system daemon ──────────────────────────────────────
  # Controls: fan profiles, keyboard LED/RGB, charge limit, performance profiles
  services.asusd = {
    enable = true;
  };

  # ── supergfxd — GPU switching daemon ────────────────────────────────
  # Modes: Integrated, Hybrid, Dedicated, Compute, VFIO
  # Enabled by default when services.asusd is enabled, but explicit is better
  services.supergfxd.enable = true;

  # ── ROG Control Center — GUI ────────────────────────────────────────
  programs.rog-control-center = {
    enable = true;
    autoStart = true;
  };

  # ── Power management tweaks ─────────────────────────────────────────
  # power-profiles-daemon is already enabled in modules/system.nix
  # These are additional laptop-friendly tweaks

  # Ensure firmware updates work on ASUS hardware
  services.fwupd.enable = true;
}
