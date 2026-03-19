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
  # Temporarily disabled: Steam blocked on work network
  /* nix.settings = {
    extra-substituters = [ "https://nix-gaming.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  }; */

  # Temporarily disabled: Steam blocked on work network
  /* programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = true;

    # GE-Proton: custom Proton fork with extra patches for better
    # game compatibility (codecs, anti-cheat, FSR, DLSS, Wayland, etc.)
    # Replaces the deprecated proton-ge package from nix-gaming.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  }; */

  # ── GameMode (Feral Interactive) ──────────────────────────────────────
  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
      };
      # GPU optimisations are disabled by default — gpu_device = 0 targets the
      # wrong GPU on hybrid (ASUS Optimus / supergfxd) systems.
      # To enable, add the following to programs.gamemode.settings in
      # hardware-configuration.nix, substituting the correct device index
      # (verify with: cat /sys/class/drm/card*/device/vendor):
      #   gpu = {
      #     apply_gpu_optimisations = "accept-responsibility";
      #     gpu_device = 1;  # 0 = iGPU, 1 = dGPU on most Optimus laptops
      #   };
    };
  };

  # ── PipeWire Low Latency ─────────────────────────────────────────────
  # Extends the PipeWire configuration in configuration.nix.
  # Theoretical latency: quantum/rate = 256/48000 ≈ 5.33ms
  # If audio cuts out, increase quantum to 512.
  # For pro-audio workloads, reduce to 64 (requires RT kernel + dedicated hardware).
  services.pipewire.lowLatency = {
    enable = true;
    quantum = 256;  # ~5.33 ms at 48000 Hz — gaming balance; reduce to 64 for pro-audio
    rate = 48000;
  };
}
