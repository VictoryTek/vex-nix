# Plymouth boot splash screen configuration
{ config, pkgs, lib, ... }:

{
  # Enable Plymouth boot splash
  boot.plymouth = {
    enable = true;
    # Use the spinner theme (supports logo/watermark customization)
    theme = "spinner";
    # Logo will be set via system.nix at /usr/share/plymouth/themes/spinner/watermark.png
  };
  
  # Enable systemd in initrd for Plymouth support
  boot.initrd.systemd.enable = true;
  
  # Silence kernel messages for cleaner boot
  boot.kernelParams = [
    "quiet"
    "splash"
    "vt.global_cursor_default=0"
  ];
  
  # Hide systemd messages during boot
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
}
