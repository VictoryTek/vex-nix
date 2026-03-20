# modules/bootloader.nix
#
# Declarative bootloader selection module.
# Auto-detects UEFI vs BIOS at evaluation time via /sys/firmware/efi.
#
# On BIOS/MBR systems, set the install disk in hardware-configuration.nix:
#   vexos.bootLoader.grub.device = "/dev/sda";  # replace with your actual disk
#
# To override auto-detection:
#   vexos.bootLoader.type = "systemd-boot";  # force UEFI
#   vexos.bootLoader.type = "grub";          # force BIOS

{ config, lib, ... }:

let
  cfg      = config.vexos.bootLoader;
  isUefi   = builtins.pathExists /sys/firmware/efi;
in {

  # ── Option Declaration ──────────────────────────────────────────────────
  options.vexos.bootLoader = {

    type = lib.mkOption {
      type    = lib.types.enum [ "systemd-boot" "grub" ];
      default = if isUefi then "systemd-boot" else "grub";
      description = ''
        Bootloader to configure. Auto-detected from /sys/firmware/efi at
        evaluation time: UEFI systems get systemd-boot, BIOS/MBR systems
        get grub. Override explicitly if auto-detection is incorrect.
          "systemd-boot" — UEFI systems with an EFI System Partition at /boot.
          "grub"         — Legacy BIOS/MBR systems (requires grub.device to be set).
      '';
    };

    grub = {
      device = lib.mkOption {
        type    = lib.types.str;
        default = "nodev";
        description = ''
          The disk device to install GRUB to (e.g. "/dev/sda").
          Required when type = "grub". Set this in hardware-configuration.nix.
        '';
      };
    };

  };

  # ── Configuration ───────────────────────────────────────────────────────
  config = lib.mkMerge [

    # ── Assertion: grub needs a real device ─────────────────────────────
    {
      assertions = [{
        assertion = cfg.type == "systemd-boot" || cfg.grub.device != "nodev";
        message   = "vexos.bootLoader.grub.device must be set for BIOS/MBR systems "
                  + "(e.g. vexos.bootLoader.grub.device = \"/dev/sda\"; in hardware-configuration.nix).";
      }];
    }

    # ── systemd-boot (UEFI) ─────────────────────────────────────────────
    (lib.mkIf (cfg.type == "systemd-boot") {
      boot.loader.systemd-boot.enable      = true;
      boot.loader.efi.canTouchEfiVariables = true;
    })

    # ── GRUB (legacy BIOS/MBR) ──────────────────────────────────────────
    (lib.mkIf (cfg.type == "grub") {
      boot.loader.systemd-boot.enable = false;
      boot.loader.grub = {
        enable = true;
        device = cfg.grub.device;
      };
    })

  ];

}
