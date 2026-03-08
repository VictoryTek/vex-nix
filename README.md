# VexOS (NixOS)

A modular, flake-based NixOS configuration with GNOME desktop environment.

## 🏗️ Structure

```
vex-nix/
├── flake.nix                    # Main flake configuration
├── flake.lock                   # Locked dependencies
├── hosts/
│   └── default/
│       ├── configuration.nix    # Host-specific configuration
│       └── hardware-configuration.nix  # Hardware settings
├── modules/
│   ├── gnome.nix               # GNOME desktop configuration
│   ├── system.nix              # System-wide settings
│   └── users.nix               # User account definitions
├── home/
│   └── default.nix             # Home Manager configuration
└── README.md
```

## 🚀 Quick Start

### First Time Installation

1. **Update Hardware Configuration**
   
   Generate your hardware configuration:
   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/default/hardware-configuration.nix
   ```

2. **Customize Settings**
   
   Edit the following files to match your preferences:
   - `flake.nix` - Change hostname "vexos" to your desired name
   - `hosts/default/configuration.nix` - Adjust timezone, locale, etc.
   - `modules/users.nix` - Change username and initial password
   - `home/default.nix` - Update username, git config, and packages

3. **Initialize Flake**
   
   ```bash
   nix flake update
   ```

4. **Build and Switch**
   
   ```bash
   sudo nixos-rebuild switch --flake .#vexos
   ```

### Updating the System

```bash
# Update flake inputs
nix flake update

# Rebuild and switch
sudo nixos-rebuild switch --flake .#vexos
```

Or use the convenient alias (after first build):
```bash
rebuild
```

## 📦 What's Included

### System Features
- ✅ Flakes enabled by default
- ✅ GNOME desktop environment with GDM
- ✅ PipeWire audio system
- ✅ NetworkManager for networking
- ✅ Bluetooth support
- ✅ Printing support (CUPS)
- ✅ Automatic garbage collection
- ✅ Store optimization
- ✅ SSH server enabled
- ✅ Samba file sharing
- ✅ Tailscale VPN

### Desktop Environment
- GNOME with essential extensions:
  - GNOME Tweaks
  - dconf Editor
  - AppIndicator
  - Dash to Dock

### User Packages
- Firefox web browser
- VS Code editor
- Development tools (git, vim, curl, wget)
- Modern CLI utilities (ripgrep, fd, bat, eza, fzf)
- System monitoring (htop, btop, neofetch)

## 🌐 Network Services

### SSH

SSH is enabled by default. To connect:
```bash
ssh vex@your-hostname
```

For better security, disable password authentication and use SSH keys:
1. Generate a key: `ssh-keygen -t ed25519`
2. Copy to server: `ssh-copy-id vex@your-hostname`
3. Edit `modules/system.nix` and set `PasswordAuthentication = false`

### Tailscale

To set up Tailscale:
```bash
# Start and authenticate
sudo tailscale up

# Check status
tailscale status

# Get your Tailscale IP
tailscale ip
```

### Samba (SMB)

A public share is configured at `/home/vex/Public`. To set a Samba password:
```bash
# Create the shared directory
mkdir -p ~/Public

# Set your Samba password
sudo smbpasswd -a vex
```

Access the share from other devices:
- **Windows**: `\\vexos\public`
- **Linux/Mac**: `smb://vexos/public`

To add more shares, edit the `shares` section in `modules/system.nix`.

## 🔧 Customization

### Adding a New Host

1. Create a new directory under `hosts/`:
   ```bash
   mkdir -p hosts/laptop
   ```

2. Copy configuration files:
   ```bash
   cp hosts/default/* hosts/laptop/
   ```

3. Add the host to `flake.nix`:
   ```nix
   laptop = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     specialArgs = { inherit inputs; };
     modules = [
       ./hosts/laptop/configuration.nix
       ./hosts/laptop/hardware-configuration.nix
       # ... rest of modules
     ];
   };
   ```

### Adding New Modules

Create new module files in `modules/` directory for different concerns:
- Graphics drivers
- Development environments
- Gaming setup
- Virtualization
- etc.

Then import them in your host's `configuration.nix`.

### Managing Packages

- **System packages**: Add to `hosts/default/configuration.nix`
- **User packages**: Add to `home/default.nix`

## 📝 Common Commands

```bash
# Check for errors without building
nix flake check

# Build without switching
sudo nixos-rebuild build --flake .#vexos

# Test configuration (temporary, next boot reverts)
sudo nixos-rebuild test --flake .#vexos

# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Clean old generations
sudo nix-collect-garbage --delete-older-than 30d
```

## 🎯 Next Steps

- [ ] Update hardware configuration with your actual hardware
- [ ] Change default username and password
- [ ] Configure git with your name and email
- [ ] Adjust timezone and locale settings
- [ ] Add your preferred applications
- [ ] Customize GNOME settings and extensions
- [ ] Set up backup strategy

## 📚 Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [GNOME on NixOS](https://nixos.wiki/wiki/GNOME)

## 📄 License

See LICENSE file for details.