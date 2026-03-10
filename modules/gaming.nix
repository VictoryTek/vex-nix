# modules/gaming.nix
#
# Gaming support module: Steam, GameMode, and kernel tweaks.
# Note: Requires gpu.type to be set (nvidia/amd/intel) in configuration.nix
# for Steam and games to function properly.

{ config, pkgs, ... }:

{
  # ── Steam ────────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = true;
  };

  # ── GameMode (Feral Interactive) ──────────────────────────────────────
  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = 0;
      };
    };
  };

  # ── Gaming Kernel Tweaks (Bazzite-inspired) ──────────────────────────
  # Increase vm.max_map_count for games that need many memory mappings
  # (required by many modern games, Star Citizen, etc.)
  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642;
    # Split lock performance (avoid performance penalty from split locks)
    "kernel.split_lock_mitigate" = 0;
  };
}
