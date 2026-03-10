#!/usr/bin/env bash
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

ERRORS=0
BACKUP_DIR=""

# ── Error trap ────────────────────────────────────────────────────────────────
cleanup_on_error() {
    local exit_code=$?
    local line_no=$1
    echo ""
    fail "Unexpected error (exit ${exit_code}) at line ${line_no}"
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        warn "Previous /etc/nixos/ is preserved at: $BACKUP_DIR"
        warn "To restore: sudo rm -rf /etc/nixos && sudo cp -a $BACKUP_DIR /etc/nixos"
    fi
    exit 1
}

trap 'cleanup_on_error $LINENO' ERR

# ── Step 0: Argument parsing ──────────────────────────────────────────────────
OPT_YES=false
OPT_REGEN=false
OPT_KEEP=false
OPT_DRYRUN=false

usage() {
    cat <<'EOF'
Usage: sudo bash scripts/deploy.sh [OPTIONS]

Copies the VexOS NixOS config to /etc/nixos/ and runs nixos-rebuild switch.

Options:
  -y, --yes            Skip all interactive confirmation prompts
      --regen-hardware Force regenerate hardware-configuration.nix
      --keep-hardware  Force keep existing hardware-configuration.nix
      --dry-run        Print what would happen; make no changes
  -h, --help           Show this help and exit

Examples:
  sudo bash scripts/deploy.sh
  sudo bash scripts/deploy.sh --yes --keep-hardware
  sudo bash scripts/deploy.sh --yes --regen-hardware
  bash scripts/deploy.sh --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)          OPT_YES=true ;;
        --regen-hardware)  OPT_REGEN=true ;;
        --keep-hardware)   OPT_KEEP=true ;;
        --dry-run)         OPT_DRYRUN=true ;;
        -h|--help)         usage; exit 0 ;;
        *)
            fail "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ "$OPT_REGEN" == "true" && "$OPT_KEEP" == "true" ]]; then
    fail "--regen-hardware and --keep-hardware are mutually exclusive."
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# ── Step 1: Banner ────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  VexOS Deploy — scripts/deploy.sh${NC}"
echo -e "${BLUE}  Repo   : ${REPO_DIR}${NC}"
echo -e "${BLUE}  Target : /etc/nixos${NC}"
echo -e "${BLUE}  Flake  : /etc/nixos#vexos${NC}"
echo -e "${BLUE}  Dry-run: ${OPT_DRYRUN}${NC}"
echo -e "${BLUE}=========================================${NC}"

# ── Step 2: Root check ────────────────────────────────────────────────────────
step "Step 2: Root check"
if [[ $EUID -ne 0 ]]; then
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        warn "Not running as root. In dry-run mode — continuing anyway."
    else
        fail "This script must be run as root (use: sudo bash scripts/deploy.sh)"
        exit 1
    fi
else
    pass "Running as root"
fi

# ── Step 3: Confirmation ──────────────────────────────────────────────────────
step "Step 3: Confirmation"
if [[ "$OPT_DRYRUN" == "true" ]]; then
    info "Dry-run mode — skipping confirmation prompt."
elif [[ "$OPT_YES" == "true" ]]; then
    info "Auto-confirmed via --yes."
else
    echo ""
    echo "  About to deploy ${REPO_DIR} → /etc/nixos and run nixos-rebuild switch."
    printf "  Continue? [y/N] "
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        warn "Aborted by user."
        exit 0
    fi
fi

# ── Step 4: Dependency check ──────────────────────────────────────────────────
step "Step 4: Dependency check"

USE_RSYNC=true
if ! command -v rsync &>/dev/null; then
    warn "rsync not found — will fall back to cp."
    USE_RSYNC=false
else
    pass "rsync found"
fi

if ! command -v nixos-generate-config &>/dev/null; then
    warn "nixos-generate-config not found — hardware config regeneration unavailable."
else
    pass "nixos-generate-config found"
fi

if ! command -v nixos-rebuild &>/dev/null; then
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        warn "nixos-rebuild not found (expected on non-NixOS host in dry-run)."
    else
        fail "nixos-rebuild not found. Is this a NixOS system?"
        exit 1
    fi
else
    pass "nixos-rebuild found"
fi

# ── Step 5: Writability check ─────────────────────────────────────────────────
step "Step 5: Writability check"
if [[ "$OPT_DRYRUN" == "false" && ! -w /etc ]]; then
    fail "/etc is not writable. Are you running as root?"
    exit 1
fi
pass "/etc is writable (or dry-run)"

# ── Step 6: Backup existing /etc/nixos/ ──────────────────────────────────────
step "Step 6: Backup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/etc/nixos.bak-${TIMESTAMP}"
FRESH_INSTALL=false

if [[ -d /etc/nixos ]]; then
    run cp -a /etc/nixos "$BACKUP_DIR"
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        info "Would back up /etc/nixos/ → $BACKUP_DIR"
    else
        pass "Backed up /etc/nixos/ → $BACKUP_DIR"
    fi
else
    FRESH_INSTALL=true
    info "Fresh install — no existing /etc/nixos/ to back up."
fi

# ── Step 7: Copy repository to /etc/nixos/ ───────────────────────────────────
step "Step 7: Copy repository"
if [[ "$USE_RSYNC" == "true" ]]; then
    run rsync -a --delete \
        --exclude='.git/' \
        --exclude='.github/' \
        "${REPO_DIR}/" /etc/nixos/
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        info "Would copy ${REPO_DIR}/ → /etc/nixos/ via rsync (excluding .git/ .github/)"
    else
        pass "Copied ${REPO_DIR}/ → /etc/nixos/ (rsync)"
    fi
else
    run cp -r "${REPO_DIR}/." /etc/nixos/
    run rm -rf /etc/nixos/.git /etc/nixos/.github
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        info "Would copy ${REPO_DIR}/ → /etc/nixos/ via cp (then remove .git/ .github/)"
    else
        pass "Copied ${REPO_DIR}/ → /etc/nixos/ (cp)"
    fi
fi

# ── Hardware config helpers ───────────────────────────────────────────────────

# Returns 0 (true) if the given file contains the repo template sentinel comment.
is_template_hardware_config() {
    local file="$1"
    grep -q "# This is a template hardware configuration" "$file" 2>/dev/null
}

# Locates hardware-configuration.nix inside a directory.
# Handles both repo layout (hosts/default/) and traditional NixOS root layout.
find_hw_config_in_dir() {
    local dir="$1"
    if [[ -f "${dir}/hosts/default/hardware-configuration.nix" ]]; then
        echo "${dir}/hosts/default/hardware-configuration.nix"
    elif [[ -f "${dir}/hardware-configuration.nix" ]]; then
        echo "${dir}/hardware-configuration.nix"
    fi
}

# Regenerates hardware-configuration.nix using nixos-generate-config.
do_regen_hardware() {
    if ! command -v nixos-generate-config &>/dev/null; then
        fail "nixos-generate-config not found — cannot regenerate hardware config."
        return 1  # triggers ERR trap → cleanup_on_error prints backup path
    fi
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        echo "  [DRY-RUN] nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix"
        echo "  [DRY-RUN] cp /tmp/hardware-configuration.nix /etc/nixos/hosts/default/hardware-configuration.nix"
    else
        nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix
        cp /tmp/hardware-configuration.nix /etc/nixos/hosts/default/hardware-configuration.nix
        pass "Generated fresh hardware-configuration.nix"
    fi
}

# Restores hardware-configuration.nix from the backup taken in Step 6.
do_keep_hardware() {
    local hw_config=""
    if [[ "$FRESH_INSTALL" == "false" && -n "$BACKUP_DIR" ]]; then
        hw_config="$(find_hw_config_in_dir "$BACKUP_DIR")"
    fi

    if [[ -z "$hw_config" ]]; then
        fail "--keep-hardware specified but no existing hardware-configuration.nix found in backup."
        return 1  # triggers ERR trap → cleanup_on_error prints backup path
    fi

    if [[ "$OPT_DRYRUN" == "true" ]]; then
        echo "  [DRY-RUN] cp ${hw_config} /etc/nixos/hosts/default/hardware-configuration.nix"
    else
        cp "$hw_config" /etc/nixos/hosts/default/hardware-configuration.nix
        pass "Restored hardware-configuration.nix from backup (${hw_config})"
    fi
}

# ── Step 8: Hardware configuration handling ───────────────────────────────────
step "Step 8: Hardware configuration"

# Locate the existing hardware config to evaluate.
# In real mode: inspect the backup (pre-copy state).
# In dry-run mode: inspect current /etc/nixos/ (backup was not created).
EXISTING_HW=""
if [[ "$OPT_DRYRUN" == "false" && "$FRESH_INSTALL" == "false" && -n "$BACKUP_DIR" ]]; then
    EXISTING_HW="$(find_hw_config_in_dir "$BACKUP_DIR")"
elif [[ "$OPT_DRYRUN" == "true" ]]; then
    EXISTING_HW="$(find_hw_config_in_dir "/etc/nixos")"
fi

if [[ "$OPT_REGEN" == "true" ]]; then
    info "Flag --regen-hardware set — will regenerate hardware config."
    do_regen_hardware
elif [[ "$OPT_KEEP" == "true" ]]; then
    info "Flag --keep-hardware set — will keep existing hardware config."
    do_keep_hardware
elif [[ -z "$EXISTING_HW" ]]; then
    # No existing hardware config found (fresh install or none in backup).
    info "No existing hardware-configuration.nix found — regenerating."
    do_regen_hardware
elif is_template_hardware_config "$EXISTING_HW"; then
    # The backed-up file is still the repo template — never safe to deploy as-is.
    warn "Existing hardware-configuration.nix appears to be the repo template."
    info "Generating fresh hardware config with nixos-generate-config..."
    do_regen_hardware
else
    # Backed-up file looks like a real machine-generated config.
    if [[ "$OPT_YES" == "true" || "$OPT_DRYRUN" == "true" ]]; then
        info "hardware-configuration.nix appears real — keeping existing (safe default)."
        do_keep_hardware
    else
        echo ""
        info "Existing hardware-configuration.nix appears to be real (machine-generated)."
        echo "    [k] Keep existing (default, safest)"
        echo "    [r] Regenerate with nixos-generate-config"
        printf "  Choice [K/r]: "
        read -r HW_REPLY
        if [[ "$HW_REPLY" =~ ^[Rr]$ ]]; then
            do_regen_hardware
        else
            do_keep_hardware
        fi
    fi
fi

# ── Step 9: Ownership and permissions ─────────────────────────────────────────
step "Step 9: Ownership and permissions"
run chown -R root:root /etc/nixos
run find /etc/nixos -type d -exec chmod 755 {} \;
run find /etc/nixos -type f -exec chmod 644 {} \;
run find /etc/nixos/scripts -type f -name "*.sh" -exec chmod 755 {} \;
if [[ "$OPT_DRYRUN" == "true" ]]; then
    info "Would set ownership root:root and permissions (755/644) on /etc/nixos/"
else
    pass "Ownership and permissions set"
fi

# ── Step 10: nixos-rebuild switch ─────────────────────────────────────────────
step "Step 10: nixos-rebuild switch"
if [[ "$OPT_DRYRUN" == "true" ]]; then
    echo "  [DRY-RUN] nixos-rebuild switch --flake /etc/nixos#vexos"
elif ! nixos-rebuild switch --flake /etc/nixos#vexos; then
    fail "nixos-rebuild switch failed."
    warn "Your previous /etc/nixos/ configuration is backed up at: $BACKUP_DIR"
    ERRORS=$((ERRORS + 1))
    exit 1
else
    pass "nixos-rebuild switch completed successfully."
fi

# ── Step 11: Final result ─────────────────────────────────────────────────────
echo ""
if [[ "$ERRORS" -eq 0 ]]; then
    echo -e "${GREEN}=========================================${NC}"
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        echo -e "${GREEN}  DEPLOY DRY-RUN COMPLETE               ${NC}"
        echo -e "${GREEN}  Review the output above for details   ${NC}"
    else
        echo -e "${GREEN}  DEPLOY PASSED — system is up to date  ${NC}"
    fi
    echo -e "${GREEN}=========================================${NC}"
    exit 0
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}  DEPLOY FAILED — ${ERRORS} error(s)      ${NC}"
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        echo -e "${RED}  Backup: ${BACKUP_DIR}/               ${NC}"
    fi
    echo -e "${RED}=========================================${NC}"
    exit 1
fi
