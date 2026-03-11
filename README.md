# VexOS

A modular NixOS configuration with GNOME, flakes, SSH, Samba, and Tailscale.

## Installation

### Fresh Install (New Machine)

From the NixOS live installer environment:

1. **Install git** (required by the bootstrap script)
   ```bash
   nix-shell -p git
   ```

2. **Bootstrap the VexOS thin flake**
   ```bash
   curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh | sudo bash
   ```
   This writes a minimal `/etc/nixos/flake.nix`, initialises `/etc/nixos/` as a
   git repository (required for pure flake evaluation), and generates `flake.lock`.

3. **Activate**
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#vexos
   ```

4. **Reboot**

---

### Keeping Your System Updated

After the initial install, `/etc/nixos/` contains only three files and pulls
all configuration from GitHub on demand:

```bash
# Update to latest VexOS from GitHub and rebuild:
cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake /etc/nixos#vexos

# Quick rebuild without updating the lock file:
sudo nixos-rebuild switch --flake /etc/nixos#vexos
```

The shell aliases in your user environment (`home/default.nix`) do this automatically:
```bash
update   # runs: nix flake update + git add flake.lock + nixos-rebuild switch
rebuild  # runs: nixos-rebuild switch (no upstream update)
```

---

### What Lives Where

| Location | Contents |
|----------|----------|
| `/etc/nixos/flake.nix` | Thin consumer flake — points to GitHub repo |
| `/etc/nixos/flake.lock` | Pinned revision of all upstream flake inputs |
| `/etc/nixos/hardware-configuration.nix` | This machine only — never in the GitHub repo |
| `github:VictoryTek/vex-nix` | All system config, modules, and home config |

---

### Manual Bootstrap (no curl)

If you prefer not to pipe curl to bash, write the thin flake manually:

```bash
sudo tee /etc/nixos/flake.nix > /dev/null <<'EOF'
{
  description = "VexOS local machine flake";

  inputs.vexos.url = "github:VictoryTek/vex-nix";

  outputs = { self, vexos }: {
    nixosConfigurations.vexos = vexos.lib.mkVexosSystem {
      hardwareModule = ./hardware-configuration.nix;
    };
  };
}
EOF

cd /etc/nixos
git init -b main
git add flake.nix hardware-configuration.nix
nix --extra-experimental-features 'nix-command flakes' flake update
git add flake.lock
sudo nixos-rebuild switch --flake /etc/nixos#vexos
```

> **Note:** `scripts/deploy.sh` is deprecated and will print a migration guide
> if invoked. Use `scripts/install.sh` for first-time setup instead.

## What's Included

- GNOME desktop with extensions
- SSH server
- Samba file sharing
- Tailscale VPN
- Home Manager for user configuration

## Post-Install

```bash
# Set Samba password
sudo smbpasswd -a nimda

# Connect to Tailscale
sudo tailscale up
```