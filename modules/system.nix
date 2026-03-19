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

  # Nix build parallelism — auto-detected by default (uses all available cores).
  # On machines with ≤8 GB RAM, add the following in hardware-configuration.nix
  # to prevent OOM kills during large builds:
  #   nix.settings.max-jobs = 2;
  #   nix.settings.cores    = 2;
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
      # Secure production settings: password-based SSH login is disabled.
      # Authenticate using an SSH public key only. Keys must be provisioned
      # before enabling this service on a network-facing machine.
      # Add your public key to modules/users.nix:
      #   users.users.nimda.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
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
        "map to guest" = "never";  # Fail explicitly on bad credentials; no silent guest fallback
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

  # Docker (rootless) — daemon runs as 'nimda', socket at $XDG_RUNTIME_DIR/docker.sock.
  # This eliminates the /run/docker.sock group-membership privilege escalation path.
  # setSocketVariable = true injects DOCKER_HOST for all login sessions via PAM.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
}
