# VexOS System Management
# Run `just --list` to see available recipes.

# Show kernel selection menu and apply choice
kernel:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "VexOS Kernel Selector"
    echo "====================="
    echo ""

    # Define kernel options (key|description)
    KERNELS=(
        "stock|NixOS Zen Kernel — Standard desktop kernel (default)"
        "cachyos-gaming|CachyOS Gaming (BORE) — Gaming-optimized, low-latency"
        "cachyos-desktop|CachyOS Desktop (EEVDF) — General-purpose desktop"
        "cachyos-handheld|CachyOS Handheld (Deckify) — Steam Deck & handhelds"
        "cachyos-server|CachyOS Server (EEVDF 300Hz) — Server-optimized, high-throughput"
        "cachyos-lts|CachyOS LTS — Long-term support, stability-focused"
        "cachyos-hardened|CachyOS Hardened — Security-focused with hardening patches"
        "bazzite|Bazzite Gaming Kernel  (pending: requires vex-kernels)"
    )

    # Build fzf input from descriptions
    OPTIONS=""
    for k in "${KERNELS[@]}"; do
        label="${k#*|}"
        OPTIONS+="$label"$'\n'
    done

    # Show fzf menu (remove trailing blank line)
    SELECTED=$(echo "$OPTIONS" | head -n -1 | fzf --height=12 --prompt="Select kernel: " --header="Choose a kernel (Esc to cancel)") || {
        echo "No kernel selected. Aborting."
        exit 1
    }

    # Map selection back to kernel.type value
    KERNEL_TYPE=""
    for k in "${KERNELS[@]}"; do
        key="${k%%|*}"
        label="${k#*|}"
        if [[ "$label" == "$SELECTED" ]]; then
            KERNEL_TYPE="$key"
            break
        fi
    done

    if [[ -z "$KERNEL_TYPE" ]]; then
        echo "No kernel selected. Aborting."
        exit 1
    fi

    echo ""
    echo "Selected: $KERNEL_TYPE"
    echo ""

    # Update configuration.nix
    CONFIG="hosts/default/configuration.nix"
    sed -i "s/kernel\.type = \"[^\"]*\"/kernel.type = \"$KERNEL_TYPE\"/" "$CONFIG"

    echo "Updated $CONFIG with kernel.type = \"$KERNEL_TYPE\""
    echo ""
    echo "Rebuilding NixOS (boot)..."
    sudo nixos-rebuild boot --flake .#vexos
    echo ""
    echo "Done! Reboot to use the new kernel."

# Show current kernel info
kernel-info:
    @echo "Running kernel: $(uname -r)"
    @grep 'kernel.type' hosts/default/configuration.nix

# List available kernel options
list-kernels:
    @echo "Available kernels:"
    @echo "  stock             — NixOS Zen Kernel (linux_zen)"
    @echo "  cachyos-gaming    — CachyOS Gaming (BORE scheduler, low-latency)"
    @echo "  cachyos-desktop   — CachyOS Desktop (EEVDF scheduler, general-purpose)"
    @echo "  cachyos-handheld  — CachyOS Handheld / Deckify (Steam Deck & handhelds)"
    @echo "  cachyos-server    — CachyOS Server (EEVDF 300Hz, high-throughput)"
    @echo "  cachyos-lts       — CachyOS LTS (long-term support, stability)"
    @echo "  cachyos-hardened  — CachyOS Hardened (security-focused)"
    @echo "  bazzite           — Bazzite Gaming Kernel (pending: requires vex-kernels)"
    @echo ""
    @echo "Current setting:"
    @grep 'kernel.type' hosts/default/configuration.nix

# Rebuild NixOS (switch immediately)
rebuild:
    sudo nixos-rebuild switch --flake .#vexos

# Rebuild NixOS (apply on next boot)
rebuild-boot:
    sudo nixos-rebuild boot --flake .#vexos

# Run preflight checks
preflight:
    bash scripts/preflight.sh
