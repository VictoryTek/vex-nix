# vex-nix


cd /etc/nixos

sudo git clone https://github.com/VictoryTek/vex-nix

sudo cp -r vex-nix/* .

sudo cp -r nix-test/.git .

sudo rm -rf vex-nix

sudo nixos-rebuild switch --flake /etc/nixos#vex-nix