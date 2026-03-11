#!/usr/bin/env bash
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  scripts/deploy.sh — DEPRECATED                 ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  This script has been superseded by the thin local flake"
echo "  architecture. VexOS no longer copies the entire repo to"
echo "  /etc/nixos/. Instead, /etc/nixos/ contains a minimal"
echo "  flake that consumes the GitHub repository as an input."
echo ""
echo -e "${BLUE}  Fresh install (first time on a new machine):${NC}"
echo "    sudo bash scripts/install.sh"
echo ""
echo -e "${BLUE}  Update to latest VexOS (on the target machine):${NC}"
echo "    cd /etc/nixos"
echo "    sudo nix flake update"
echo "    sudo git add flake.lock"
echo "    sudo nixos-rebuild switch --flake /etc/nixos#vexos"
echo ""
echo -e "${BLUE}  Quick rebuild without updating the lock file:${NC}"
echo "    sudo nixos-rebuild switch --flake /etc/nixos#vexos"
echo ""
echo "  See README.md for the full updated installation guide."
echo ""
exit 0

