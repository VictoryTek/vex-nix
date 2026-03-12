{ config, lib, ... }:

{
  # Plymouth boot splash screen
  boot.plymouth = {
    enable = true;
    theme = "spinner";
  };

  # Silent boot kernel parameters for a clean Plymouth experience
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "udev.log_priority=3"
    "rd.systemd.show_status=auto"
  ];

  # Reduce kernel console log noise during boot
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;

  # KMS (Kernel Mode Setting) modules for early Plymouth display.
  # These must be loaded in initrd so Plymouth can show the splash
  # before the full kernel drivers are loaded.
  boot.initrd.kernelModules = lib.optionals (config.gpu.type == "intel") [ "i915" ]
    ++ lib.optionals (config.gpu.type == "amd") [ "amdgpu" ]
    ++ lib.optionals (config.gpu.type == "nvidia") [
      "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"
    ]
    # Fallback framebuffer drivers so Plymouth renders on BIOS/UEFI
    # framebuffer when no discrete GPU driver is active.
    ++ lib.optionals (config.gpu.type == "none") [ "simpledrm" "bochs_drm" ];

  # Ensure Plymouth starts before the display is lost during boot.
  boot.initrd.systemd.enable = true;

  # Hide grub menu on boot (press Shift during POST to interrupt).
  boot.loader.grub.timeoutStyle = "hidden";
  boot.loader.timeout = 0;
}
