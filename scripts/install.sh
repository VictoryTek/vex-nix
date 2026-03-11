#!/usr/bin/env bash
# scripts/install.sh — Bootstrap a fresh NixOS machine using the thin /etc/nixos/ flake model.
# chmod +x scripts/install.sh
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo "       $*"; }
step() { echo ""; echo "==> $*"; }

# ── Error trap ────────────────────────────────────────────────────────────────
cleanup_on_error() {
    local exit_code=$?
    local line_no=$1
    echo ""
    fail "Unexpected error (exit ${exit_code}) at line ${line_no}"
    exit 1
}

trap 'cleanup_on_error $LINENO' ERR

# ── Argument parsing ──────────────────────────────────────────────────────────
OPT_YES=false
OPT_DRYRUN=false
HOSTNAME="vexos"

usage() {
    cat <<'EOF'
Usage: sudo bash scripts/install.sh [OPTIONS]

Bootstraps a fresh NixOS machine using the thin /etc/nixos/ flake model.
Requires hardware-configuration.nix to already exist at /etc/nixos/.

  The NixOS live installer generates this with:
    sudo nixos-generate-config

  This script then:
    1. Writes /etc/nixos/flake.nix (the thin VexOS consumer flake)
    2. Initialises /etc/nixos/ as a git repo (required for pure evaluation)
    3. Stages flake.nix and hardware-configuration.nix
    4. Runs `nix flake update` to generate flake.lock
    5. Stages flake.lock
    6. Prints the final nixos-rebuild switch command

Options:
  -y, --yes            Skip all interactive confirmation prompts
      --hostname NAME  Set the NixOS configuration name (default: vexos)
      --dry-run        Print what would happen; make no changes
  -h, --help           Show this help and exit

Examples:
  sudo bash scripts/install.sh
  sudo bash scripts/install.sh --yes --hostname mymachine
  bash scripts/install.sh --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)       OPT_YES=true ;;
        --hostname)     shift; HOSTNAME="$1" ;;
        --dry-run)      OPT_DRYRUN=true ;;
        -h|--help)      usage; exit 0 ;;
        *)
            fail "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# ── Dry-run helper ────────────────────────────────────────────────────────────
# Prefix all mutating commands with run() — in dry-run mode the command is
# printed but NOT executed.
run() {
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  VexOS Install — scripts/install.sh${NC}"
echo -e "${BLUE}  Target   : /etc/nixos${NC}"
echo -e "${BLUE}  Hostname : ${HOSTNAME}${NC}"
echo -e "${BLUE}  Dry-run  : ${OPT_DRYRUN}${NC}"
echo -e "${BLUE}============================================${NC}"

# ── Step 1: Root check ────────────────────────────────────────────────────────
step "Step 1: Root check"
if [[ $EUID -ne 0 ]]; then
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        warn "Not running as root. In dry-run mode — continuing anyway."
    else
        fail "This script must be run as root (use: sudo bash scripts/install.sh)"
        exit 1
    fi
else
    pass "Running as root"
fi

# ── Step 2: Dependency check ──────────────────────────────────────────────────
step "Step 2: Dependency check"

for cmd in nix git; do
    if ! command -v "$cmd" &>/dev/null; then
        fail "Required command not found: $cmd"
        exit 1
    else
        pass "$cmd found"
    fi
done

# ── Step 3: Verify hardware-configuration.nix ────────────────────────────────
step "Step 3: Verify hardware-configuration.nix"
HW_CONFIG="/etc/nixos/hardware-configuration.nix"

if [[ ! -f "$HW_CONFIG" ]]; then
    fail "hardware-configuration.nix not found at $HW_CONFIG"
    info ""
    info "Run the NixOS installer first, which generates this file:"
    info "  sudo nixos-generate-config"
    info ""
    info "Then re-run this script."
    exit 1
fi

# Abort if the file is the VexOS template sentinel rather than a real generated config
if grep -q "# This is a template hardware configuration" "$HW_CONFIG" 2>/dev/null; then
    fail "The file at $HW_CONFIG appears to be the VexOS template sentinel,"
    info "not a machine-generated hardware configuration."
    info ""
    info "Generate a real one with:"
    info "  sudo nixos-generate-config"
    exit 1
fi

pass "hardware-configuration.nix found and appears machine-generated"

# ── Step 4: Check for existing flake.nix ─────────────────────────────────────
step "Step 4: Check for existing /etc/nixos/flake.nix"
FLAKE_PATH="/etc/nixos/flake.nix"

if [[ -f "$FLAKE_PATH" ]]; then
    warn "/etc/nixos/flake.nix already exists."
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        info "Dry-run mode — would overwrite."
    elif [[ "$OPT_YES" == "true" ]]; then
        info "Auto-confirmed via --yes — will overwrite."
    else
        echo ""
        printf "  Overwrite existing /etc/nixos/flake.nix? [y/N] "
        read -r REPLY
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            warn "Aborted by user."
            exit 0
        fi
    fi
else
    pass "No existing flake.nix — proceeding."
fi

# ── Step 5: Write /etc/nixos/flake.nix ───────────────────────────────────────
step "Step 5: Write /etc/nixos/flake.nix"

# The thin consumer flake: only 3 files live in /etc/nixos/.
# All system configuration is pulled from the GitHub repo as a flake input.
FLAKE_CONTENT='{
  description = "VexOS local machine flake";

  inputs.vexos.url = "github:VictoryTek/vex-nix";

  outputs = { self, vexos, ... }: {
    nixosConfigurations.'"${HOSTNAME}"' = vexos.lib.mkVexosSystem {
      hardwareModule = ./hardware-configuration.nix;
    };
  };
}
'

if [[ "$OPT_DRYRUN" == "true" ]]; then
    echo "  [DRY-RUN] Would write /etc/nixos/flake.nix:"
    echo "$FLAKE_CONTENT" | sed 's/^/    /'
else
    echo "$FLAKE_CONTENT" > "$FLAKE_PATH"
    pass "Wrote /etc/nixos/flake.nix"
fi

# ── Step 6: Initialise git repo ───────────────────────────────────────────────
step "Step 6: Initialise git repo in /etc/nixos/"
info "(Required for pure flake evaluation — Nix uses git tracking to"
info " determine the flake's file set. No remote is set up.)"

if [[ -d /etc/nixos/.git ]]; then
    pass "/etc/nixos/ is already a git repository"
else
    run git -C /etc/nixos init -b main
    if [[ "$OPT_DRYRUN" == "false" ]]; then
        pass "Initialised git repo at /etc/nixos/"
    fi
fi

# Stage flake.nix and hardware-configuration.nix so Nix can see them
run git -C /etc/nixos add flake.nix hardware-configuration.nix
if [[ "$OPT_DRYRUN" == "false" ]]; then
    pass "Staged flake.nix and hardware-configuration.nix"
fi

# ── Step 7: Generate flake.lock ───────────────────────────────────────────────
step "Step 7: nix flake update (generates flake.lock)"
info "This fetches the latest VexOS revision from GitHub."
info "It may take a minute on first run."

run sh -c "cd /etc/nixos && nix --extra-experimental-features 'nix-command flakes' flake update"

if [[ "$OPT_DRYRUN" == "false" ]]; then
    pass "flake.lock generated"
fi

# Stage flake.lock so it is tracked by the git repo
run git -C /etc/nixos add flake.lock
if [[ "$OPT_DRYRUN" == "false" ]]; then
    pass "flake.lock staged"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  /etc/nixos/ is ready.                    ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  Files in /etc/nixos/:"
echo "    flake.nix                   (thin VexOS consumer flake)"
echo "    flake.lock                  (pinned upstream revision)"
echo "    hardware-configuration.nix  (this machine's hardware)"
echo ""
echo "  To activate the configuration, run:"
echo ""
echo -e "  ${BLUE}sudo nixos-rebuild switch --flake /etc/nixos#${HOSTNAME}${NC}"
echo ""
echo "  To update to the latest VexOS in future:"
echo ""
echo -e "  ${BLUE}cd /etc/nixos && sudo nix flake update && sudo git add flake.lock${NC}"
echo -e "  ${BLUE}sudo nixos-rebuild switch --flake /etc/nixos#${HOSTNAME}${NC}"
echo ""
