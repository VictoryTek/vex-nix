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

  # Limit parallel build jobs to reduce peak RAM usage during nixos-rebuild.
  # Each Nix build job can consume several hundred MB; capping at 2 prevents
  # the evaluator + linker from exhausting memory on machines with ≤8 GB RAM.
  nix.settings.max-jobs = 2;
  nix.settings.cores = 2;
  # Increase download buffer to avoid "buffer is full" warnings when
  # downloads outpace store writes (common in VMs with slow virtual disks).
  nix.settings.download-buffer-size = 268435456; # 256 MiB

  # zram swap — creates a compressed in-RAM swap device (default: half of RAM).
  # This gives the kernel headroom to swap build artefacts out of physical RAM
  # under pressure, preventing OOM kills during large rebuilds.
  zramSwap.enable = true;

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
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "VexOS Samba Server";
        "netbios name" = "vexos";
        security = "user";
        "hosts allow" = "192.168. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      public = {
        path = "/home/nimda/Public";
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

  # Docker
  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;
}
