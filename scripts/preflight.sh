#!/usr/bin/env bash
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo "       $*"; }

ERRORS=0

# ── Step 1: nix flake check ───────────────────────────────────────────────────
echo ""
echo "==> Step 1: nix flake check"
if nix --extra-experimental-features 'nix-command flakes' flake check 2>&1; then
  pass "nix flake check"
else
  fail "nix flake check"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2: Configuration evaluation ─────────────────────────────────────────
echo ""
echo "==> Step 2: NixOS configuration evaluation"
RESULT=$(nix --extra-experimental-features 'nix-command flakes' \
  eval .#nixosConfigurations.vexos.config.system.build.toplevel \
  --apply builtins.typeOf 2>&1) || RESULT=""
if echo "$RESULT" | grep -qE '"string"|"set"'; then
  pass "Configuration evaluation (.#nixosConfigurations.vexos)"
else
  fail "Configuration evaluation failed"
  info "$RESULT"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2b: Verify lib.mkVexosSystem is exported ────────────────────────────
echo ""
echo "==> Step 2b: Verify lib.mkVexosSystem output"
LIB_RESULT=$(nix --extra-experimental-features 'nix-command flakes' \
  eval .#lib.mkVexosSystem \
  --apply builtins.typeOf 2>&1) || LIB_RESULT=""
if echo "$LIB_RESULT" | grep -q '"lambda"'; then
  pass "lib.mkVexosSystem is exported and is a function"
else
  fail "lib.mkVexosSystem is missing or not a function"
  info "$LIB_RESULT"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 3: Formatting check (alejandra or nixpkgs-fmt) ──────────────────────
echo ""
echo "==> Step 3: Nix formatting check"
if command -v alejandra &>/dev/null; then
  if alejandra --check . 2>&1; then
    pass "Formatting (alejandra)"
  else
    fail "Formatting check failed (alejandra)"
    ERRORS=$((ERRORS + 1))
  fi
elif command -v nixpkgs-fmt &>/dev/null; then
  if nixpkgs-fmt --check . 2>&1; then
    pass "Formatting (nixpkgs-fmt)"
  else
    fail "Formatting check failed (nixpkgs-fmt)"
    ERRORS=$((ERRORS + 1))
  fi
else
  warn "No Nix formatter found (alejandra/nixpkgs-fmt). Skipping."
fi

# ── Step 4: Nix lint (statix) ─────────────────────────────────────────────────
echo ""
echo "==> Step 4: Nix lint (statix)"
if command -v statix &>/dev/null; then
  if statix check . 2>&1; then
    pass "Lint (statix)"
  else
    fail "Lint check failed (statix)"
    ERRORS=$((ERRORS + 1))
  fi
else
  warn "statix not found. Skipping lint check."
fi

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}  PREFLIGHT PASSED — ready to push     ${NC}"
  echo -e "${GREEN}========================================${NC}"
  exit 0
else
  echo -e "${RED}========================================${NC}"
  echo -e "${RED}  PREFLIGHT FAILED — $ERRORS error(s)   ${NC}"
  echo -e "${RED}========================================${NC}"
  exit 1
fi
