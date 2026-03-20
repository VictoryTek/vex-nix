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
      AllowUsers = [ "nimda" ];  # restrict SSH to the sole human account
      MaxAuthTries = 3;        # reduce per-connection key probing window (sshd default: 6)
      LoginGraceTime = 30;     # close unauthenticated connections after 30 s (sshd default: 120)
    };
  };

  # Enable Tailscale VPN
  services.tailscale.enable = true;

  # Enable Samba for file sharing
  services.samba = {
    enable = true;
    openFirewall = false; # ports opened explicitly in networking.firewall below
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
    # Tailscale interface
    trustedInterfaces = [ "tailscale0" ];
    # Samba — open on all interfaces (hosts allow/deny provides the smbd-level guard).
    # To scope to a specific NIC, replace these with:
    #   networking.firewall.interfaces.<iface>.allowedTCPPorts = [ 139 445 ];
    #   networking.firewall.interfaces.<iface>.allowedUDPPorts = [ 137 138 ];
    allowedTCPPorts = [ 139 445 ];
    allowedUDPPorts = [ 137 138 ];
  };

  # ── Kernel / network hardening ────────────────────────────────────────────────
  # These settings apply regardless of kernel variant (stock, CachyOS, etc.).
  # All values have been verified safe for Steam / Proton / Wine / GameMode.
  # Override any entry in hardware-configuration.nix with lib.mkForce if a
  # specific game or tool requires a different value.
  boot.kernel.sysctl = {
    # Prevent non-root processes from reading kernel ring buffer and pointers.
    # Useful addresses for exploit development (KASLR bypass) are hidden.
    "kernel.dmesg_restrict"  = 1;
    "kernel.kptr_restrict"   = 2;

    # Restrict ptrace to parent-child relationships only (scope 1).
    # Steam, Proton/Wine wineserver, and GameMode are all safe at scope 1.
    # If a legacy launcher breaks, override in hardware-configuration.nix:
    #   boot.kernel.sysctl."kernel.yama.ptrace_scope" = lib.mkForce 0;
    "kernel.yama.ptrace_scope" = 1;

    # Disable unprivileged eBPF and harden the JIT compiler.
    # Games and game launchers do not use eBPF.
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden"          = 2;

    # Ignore ICMP redirects — not needed on a single-NIC workstation/laptop.
    "net.ipv4.conf.all.accept_redirects"     = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects"       = 0;

    # Log and drop packets with impossible source addresses.
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.all.rp_filter"   = 1;

    # Disable core dumps from setuid binaries.
    "fs.suid_dumpable" = 0;

    # Restrict access to kernel log via /proc/sys/kernel/printk.
    "kernel.printk" = "3 3 3 3";
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
