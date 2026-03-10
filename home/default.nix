{ config, pkgs, ... }:

{
  # Home Manager configuration for user-specific settings
  # This is managed by Home Manager and controls user environment

  home.username = "nimda";
  home.homeDirectory = "/home/nimda";

  # This value determines the Home Manager release which the
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # User-specific packages
  home.packages = with pkgs; [
    # Development tools
    vscode

    # Browsers
    brave

    # Terminal emulators
    ghostty

    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    tmux

    # System utilities
    fastfetch
    btop
    inxi
    pavucontrol
    blivet-gui
  ];

  # Git configuration
  #programs.git = {
  #  enable = true;
  #  settings = {
  #    user.name = "Nimda";
  #    user.email = "vex@example.com";  # Change this
  #    init.defaultBranch = "main";
  #    pull.rebase = false;
  #  };
  #};

  # Bash configuration
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      ".." = "cd ..";
      update = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
      rebuild = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
      
      # Tailscale shortcuts
      ts = "tailscale";
      tss = "tailscale status";
      tsip = "tailscale ip";
      
      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };

  # Starship cross-shell prompt
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}
