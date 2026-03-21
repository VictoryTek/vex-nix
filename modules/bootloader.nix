# modules/bootloader.nix
#
# Declarative bootloader selection module.
# Defaults to systemd-boot (UEFI). Override explicitly for BIOS/MBR systems.
#
# On BIOS/MBR systems, set these in your hardware-configuration.nix:
#   vexos.bootLoader.type = "grub";
#   vexos.bootLoader.grub.device = "/dev/sda";  # replace with your actual disk

{ config, lib, ... }:

let
  cfg = config.vexos.bootLoader;
in {

  # ── Option Declaration ──────────────────────────────────────────────────
  options.vexos.bootLoader = {

    type = lib.mkOption {
      type    = lib.types.enum [ "systemd-boot" "grub" ];
      default = "systemd-boot";
      description = ''
        Bootloader to configure. Defaults to "systemd-boot" for UEFI systems.
        Set to "grub" for legacy BIOS/MBR systems (and set grub.device).
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
