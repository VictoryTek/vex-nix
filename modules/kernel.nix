# modules/kernel.nix
#
# Declarative Linux kernel selection module.
# Set `kernel.type` in your host configuration to select the kernel.
# Supported values: "stock", "cachyos-gaming", "cachyos-server",
#   "cachyos-desktop", "cachyos-handheld", "cachyos-lts", "cachyos-hardened",
#   "bazzite" (placeholder — requires vex-kernels flake).
#
# CachyOS kernels are provided by the nix-cachyos-kernel flake
# (github:xddxdd/nix-cachyos-kernel) via overlay.
#
# Usage example in hosts/default/configuration.nix:
#   kernel.type = "cachyos-gaming";

{ config, lib, pkgs, ... }:

let
  cfg = config.kernel;
  isCachyos = builtins.substring 0 7 cfg.type == "cachyos";
in {

  # ── Option Declaration ──────────────────────────────────────────────────
  options.kernel = {
    type = lib.mkOption {
      type    = lib.types.enum [
        "stock"
        "cachyos-gaming"
        "cachyos-server"
        "cachyos-desktop"
        "cachyos-handheld"
        "cachyos-lts"
        "cachyos-hardened"
        "bazzite"
      ];
      default = "stock";
      description = ''
        Select the Linux kernel to use.
          "stock"             — NixOS Zen kernel (linux_zen). Good desktop performance,
                                well-tested in nixpkgs. Default fallback.
          "cachyos-gaming"    — CachyOS kernel with BORE scheduler. Optimized for
                                gaming and interactive workloads with low-latency
                                patches, 1000Hz timer, and performance enhancements.
          "cachyos-server"    — CachyOS kernel with EEVDF scheduler. Optimized for
                                server workloads with throughput-focused configuration.
          "cachyos-desktop"   — CachyOS Latest kernel with EEVDF scheduler.
                                General-purpose desktop, balanced performance.
          "cachyos-handheld"  — CachyOS Deckify kernel. Handheld/Steam Deck
                                optimized with ACPI call and handheld patches.
                                NixOS-native Bazzite kernel alternative.
          "cachyos-lts"       — CachyOS LTS kernel. Long-term support for
                                maximum stability on production workloads.
          "cachyos-hardened"  — CachyOS Hardened kernel. Security-focused with
                                hardening patches and attack surface reduction.
          "bazzite"           — Bazzite Gaming Kernel (PENDING). Requires the
                                vex-kernels flake input. Selection will throw an
                                error until wired up. See flake.nix and
                                kernel_bazzite_placeholder_spec.md.
      '';
    };
  };

  # ── Configuration ───────────────────────────────────────────────────────
  config = lib.mkMerge [

    # ── Stock: NixOS Zen kernel ────────────────────────────────────────────
    (lib.mkIf (cfg.type == "stock") {
      boot.kernelPackages = pkgs.linuxPackages_zen;
    })

    # ── CachyOS Gaming (BORE scheduler) ───────────────────────────────────
    (lib.mkIf (cfg.type == "cachyos-gaming") {
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;
    })

    # ── CachyOS Server (EEVDF scheduler) ──────────────────────────────────
    (lib.mkIf (cfg.type == "cachyos-server") {
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-server;
    })

    # ── CachyOS Desktop (EEVDF, general-purpose) ─────────────────────────
    (lib.mkIf (cfg.type == "cachyos-desktop") {
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    })

    # ── CachyOS Handheld / Deckify (handheld patches) ────────────────────
    (lib.mkIf (cfg.type == "cachyos-handheld") {
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-deckify;
    })

    # ── CachyOS LTS (long-term support) ──────────────────────────────────
    (lib.mkIf (cfg.type == "cachyos-lts") {
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-lts;
    })

    # ── CachyOS Hardened (security-focused) ──────────────────────────────
    (lib.mkIf (cfg.type == "cachyos-hardened") {
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-hardened;
    })

    # ── Bazzite Gaming Kernel (placeholder) ───────────────────────────────
    # Requires vex-kernels flake input — see flake.nix for wiring instructions.
    # Once vex-kernels is available, replace the throw with:
    #   boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;
    (lib.mkIf (cfg.type == "bazzite") {
      boot.kernelPackages = throw ''

        kernel.type = "bazzite" is not yet available.

        The Bazzite kernel requires the vex-kernels flake input, which has
        not been created yet. To enable this:
          1. Create the vex-kernels flake at github:<owner>/vex-kernels
          2. Uncomment the vex-kernels input block in flake.nix
          3. Uncomment the vex-kernels overlay in flake.nix (mkVexosSystem)
          4. Replace this throw with:
               boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;

        See: .github/docs/subagent_docs/kernel_bazzite_placeholder_spec.md
      '';
    })

    # ── Binary cache for CachyOS kernels ──────────────────────────────────
    (lib.mkIf isCachyos {
      nix.settings = {
        extra-substituters = [
          "https://attic.xuyh0120.win/lantian"
          "https://cache.garnix.io"
        ];
        extra-trusted-public-keys = [
          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        ];
      };
    })
  ];
}
