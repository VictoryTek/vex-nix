# Audio configuration using PipeWire
{ config, pkgs, lib, ... }:

{
  # Disable PulseAudio (PipeWire replaces it)
  hardware.pulseaudio.enable = lib.mkForce false;
  
  # Enable PipeWire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # Uncomment for JACK support
    # jack.enable = true;
  };
}
