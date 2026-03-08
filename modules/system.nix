{ config, pkgs, ... }:

{
  # System-wide configuration

  # Auto upgrade (optional, commented out by default)
  # system.autoUpgrade = {
  #   enable = true;
  #   allowReboot = false;
  # };

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Optimize Nix store
  nix.settings.auto-optimise-store = true;

  # Enable OpenSSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;  # Set to false and use keys for better security
    };
  };

  # Enable Tailscale VPN
  services.tailscale.enable = true;

  # Enable Samba for file sharing
  services.samba = {
    enable = true;
    securityType = "user";
    openFirewall = true;
    extraConfig = ''
      workgroup = WORKGROUP
      server string = VexOS Samba Server
      netbios name = vexos
      security = user
      hosts allow = 192.168. 127.0.0.1 localhost
      hosts deny = 0.0.0.0/0
      guest account = nobody
      map to guest = bad user
    '';
    shares = {
      public = {
        path = "/home/vex/Public";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

  # Samba client support (for mounting shares)
  services.gvfs.enable = true;  # GNOME Virtual File System for SMB support

  # Firewall configuration
  networking.firewall = {
    enable = true;
    # SSH is allowed by default when openssh is enabled
    # Tailscale manages its own firewall rules
    # Samba ports are opened by openFirewall = true above
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    # Tailscale interface
    trustedInterfaces = [ "tailscale0" ];
  };

  # Enable CUPS for printing
  services.printing.enable = true;

  # Enable bluetooth (optional)
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Power management
  services.power-profiles-daemon.enable = true;
}
