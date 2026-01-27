# Font configuration
{ config, pkgs, lib, ... }:

{
  fonts = {
    packages = with pkgs; [
      # Essential fonts
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      liberation_ttf
      
      # Nerd fonts for terminal/coding
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
    ];
    
    # Font configuration
    fontconfig = {
      defaultFonts = {
        serif = [ "Noto Serif" ];
        sansSerif = [ "Noto Sans" ];
        monospace = [ "JetBrainsMono Nerd Font" ];
      };
    };
  };
}
