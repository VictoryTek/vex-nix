# modules/gaming.nix
#
# Gaming support module: Steam, GameMode, nix-gaming enhancements.
# nix-gaming modules (pipewireLowLatency, platformOptimizations) are
# imported in flake.nix and configured below.
# Provides: proton-ge-bin (GE-Proton as Steam compat tool),
#           nix-gaming Cachix binary cache.
#
# Note: Requires gpu.type to be set (nvidia/amd/intel) in configuration.nix
# for Steam and games to function properly.
# Note: pipewireLowLatency requires services.pipewire.enable = true
#       (set in hosts/default/configuration.nix).

{ pkgs, ... }:

{
  # ── Cachix binary cache (avoids building wine-ge from source) ─────────
  nix.settings = {
    extra-substituters = [ "https://nix-gaming.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  };

  # ── Steam ────────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = true;

    # GE-Proton: custom Proton fork with extra patches for better
    # game compatibility (codecs, anti-cheat, FSR, DLSS, Wayland, etc.)
    # Replaces the deprecated proton-ge package from nix-gaming.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
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

  # ── PipeWire Low Latency ─────────────────────────────────────────────
  # Extends the PipeWire configuration in configuration.nix.
  # Theoretical latency: quantum/rate = 64/48000 ≈ 1.33ms
  # If audio cuts out, increase quantum to 128 or 256.
  services.pipewire.lowLatency = {
    enable = true;
    quantum = 64;
    rate = 48000;
  };
}
