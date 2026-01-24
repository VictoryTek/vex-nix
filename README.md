# vex-nix


cd /etc/nixos

sudo git clone https://github.com/VictoryTek/vex-nix

sudo cp -r vex-nix/* .

sudo cp -r vex-nix/.git .

sudo rm -rf vex-nix

# Choose GPU option
sudo nixos-rebuild switch --flake /etc/nixos#vex-htpc-intel

sudo nixos-rebuild switch --flake /etc/nixos#vex-htpc-amd

sudo nixos-rebuild switch --flake /etc/nixos#vex-htpc-nvidia