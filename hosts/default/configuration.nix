{ config, pkgs, inputs, ... }:

{
  imports = [
    ../../modules/system.nix
    ../../modules/gnome.nix
    ../../modules/users.nix
    ../../modules/gpu.nix
    ../../modules/gaming.nix
    ../../modules/asus.nix
    ../../modules/flatpak.nix
    ../../modules/plymouth.nix
    ../../modules/kernel.nix
  ];

  # GPU driver selection — set to "nvidia", "amd", "intel", or "none"
  gpu.type = "none";

  # Kernel selection — see `just list-kernels` for all options
  # Valid: "stock", "cachyos-gaming", "cachyos-server", "cachyos-desktop",
  #        "cachyos-handheld", "cachyos-lts", "cachyos-hardened",
  #        "bazzite" (placeholder — requires vex-kernels flake)
  kernel.type = "stock";

  # Hostname
  networking.hostName = "vexos";

  # Timezone and Locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Networking
  networking.networkmanager.enable = true;

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages
  environment.systemPackages = with pkgs; [
    wget
    git
    curl
    htop
    firefox
    cifs-utils  # For mounting SMB shares
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "24.05";
}
