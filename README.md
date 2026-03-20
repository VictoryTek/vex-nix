# VexOS

A modular NixOS configuration with GNOME, flakes, SSH, Samba, and Tailscale.

## Installation

### Fresh Install (New Machine)

From a freshly installed NixOS system (your `/etc/nixos/hardware-configuration.nix` already exists):

1. **Install git**
   ```bash
   nix-shell -p git
   ```

2. **Write the thin flake**
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
   cd /etc/nixos && sudo git init -b main && sudo git add flake.nix hardware-configuration.nix
   ```

3. **Rebuild and reboot**
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#vexos && reboot
   ```

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

### ⚠️ Automated Option: Using the Install Script (Existing Systems Only)

> **Note:** `scripts/install.sh` targets an **already-running NixOS system** in `/etc/nixos/`. It is **not suitable** for use from the NixOS live ISO installer.

> ⚠️ **Warning:** The `curl | sudo bash` pattern downloads and executes arbitrary code
> as root without any integrity verification. It is vulnerable to MITM attacks, DNS
> hijacking, compromised CDN caches, and supply-chain attacks — even over HTTPS, because
> TLS only protects the transport layer, not the origin. The `flake.lock` hash-pinning
> that protects your system starts *after* a successful bootstrap; it offers no protection
> for the bootstrap script itself. The manual steps above are the **recommended path**.
> Use this option only if you understand the risks and have reviewed the script first.

If you still want to use the install script, **download and inspect it before running**:

```bash
# 1. Download the script
curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh \
    -o /tmp/vexos-install.sh

# 2. Review the script contents before executing
less /tmp/vexos-install.sh

# 3. Run it only after inspection
sudo bash /tmp/vexos-install.sh
```

Never pipe `curl` output directly to `bash` or `sudo bash`. Always download first, inspect, then execute.

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