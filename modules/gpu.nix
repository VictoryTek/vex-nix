# modules/gpu.nix
#
# Declarative GPU driver selection module.
# Set `gpu.type` in your host configuration to configure the appropriate
# driver stack. Supported values: "none", "intel", "amd", "nvidia".
#
# Usage example in hosts/default/configuration.nix:
#   gpu.type = "nvidia";

{ config, lib, pkgs, ... }:

let
  cfg = config.gpu;
in {

  # ── Option Declaration ──────────────────────────────────────────────────
  options.gpu = {
    type = lib.mkOption {
      type    = lib.types.enum [ "none" "intel" "amd" "nvidia" ];
      default = "none";
      description = ''
        Select the GPU driver stack to configure.
          "none"   — No GPU-specific configuration (VM/headless safe default).
          "intel"  — Intel integrated graphics (modesetting + VA-API media driver).
          "amd"    — AMD discrete/integrated GPU (amdgpu + RADV Vulkan).
          "nvidia" — NVIDIA proprietary driver (requires Turing architecture or newer
                     for the open kernel module; set open = false for older cards).
      '';
    };

    nvidia = {
      open = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = ''
          Use the open-source NVIDIA kernel module (nvidia-open).
          Supported on Turing (RTX 20xx) and newer architectures.
          Set to false for older cards (Pascal GTX 10xx and below).
        '';
      };
    };
  };

  # ── Configuration ───────────────────────────────────────────────────────
  config = lib.mkMerge [

    # ── Shared: enable hardware graphics for all non-none GPU types ────────
    (lib.mkIf (cfg.type != "none") {
      hardware.graphics = {
        enable      = true;
        enable32Bit = true;   # needed for Steam, Wine, 32-bit games
      };
    })

    # ── Intel ──────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "intel") {
      services.xserver.videoDrivers = [ "modesetting" ];

      hardware.graphics.extraPackages = with pkgs; [
        # Modern Intel iGPU VA-API (Broadwell / Gen 8 and newer)
        intel-media-driver
        # Older Intel iGPU VA-API fallback (Gen 4–9)
        intel-vaapi-driver
        # Intel compute runtime for OpenCL
        intel-compute-runtime
      ];
    })

    # ── AMD ────────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "amd") {
      # The amdgpu kernel module loads automatically for supported cards.
      # Setting videoDrivers to "amdgpu" makes the xorg intent explicit.
      services.xserver.videoDrivers = [ "amdgpu" ];

      hardware.graphics.extraPackages = with pkgs; [
        # AMDVLK: AMD's official open-source Vulkan driver (alternative to RADV)
        amdvlk
        # ROCm OpenCL runtime (for compute workloads)
        rocmPackages.clr.icd
      ];

      hardware.graphics.extraPackages32 = with pkgs; [
        driversi686Linux.amdvlk
      ];
    })

    # ── NVIDIA ─────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "nvidia") {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        # Kernel mode-setting: required for Wayland/GDM, prevents tearing
        modesetting.enable = true;

        # Open-source kernel module (nvidia-open, recommended for Turing+)
        # Set gpu.nvidia.open = false in host config for older GPUs
        open = cfg.nvidia.open;

        # NVIDIA power management (suspend/resume stability)
        powerManagement.enable = false;

        # Use the stable driver package (latest tested/stable)
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    })

  ]; # end mkMerge

}
