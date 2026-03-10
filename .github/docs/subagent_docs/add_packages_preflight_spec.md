# Preflight Script Specification — VexOS NixOS Project

**Feature:** `scripts/preflight.sh`
**Date:** 2026-03-10
**Status:** DRAFT

---

## 1. Project Analysis

### Flake Configuration (`flake.nix`)
- **Flake inputs:** `nixpkgs` (nixos-unstable), `home-manager` (follows nixpkgs)
- **Output:** Single `nixosConfigurations.vexos` target
- **System:** `x86_64-linux`
- **Modules:** `hosts/default/configuration.nix`, `hosts/default/hardware-configuration.nix`, Home Manager integration

### System Module (`modules/system.nix`)
- Services: OpenSSH, Tailscale, Samba, GVFS, CUPS, Blueman, Docker
- Nix store: auto-GC (weekly, 30d), store optimisation enabled
- Firewall: enabled, Tailscale trusted interface

### Key Identifiers
| Item | Value |
|------|-------|
| Flake output | `.#nixosConfigurations.vexos` |
| Build target | `.#nixosConfigurations.vexos.config.system.build.toplevel` |
| Architecture | `x86_64-linux` |

---

## 2. Problem Definition

The project currently has no CI/CD pipeline and no preflight validation script. Before pushing changes to GitHub or performing system rebuilds, there is no automated check to ensure:

- The flake evaluates without errors
- NixOS configuration is structurally valid
- Nix code formatting is consistent
- Nix expressions are free of common anti-patterns

---

## 3. Script Design

### File
```
scripts/preflight.sh
```

### Required Checks (Fatal — exit non-zero on failure)

| Step | Command | Description |
|------|---------|-------------|
| 1 | `nix flake check` | Validates flake inputs, outputs, and overall schema integrity |
| 2 | `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf` | Confirms the full NixOS configuration evaluates to a derivation without errors |

### Optional Checks (Non-Fatal — warn only if tool absent)

| Step | Tool | Command | Description |
|------|------|---------|-------------|
| 3a | `alejandra` (preferred) | `alejandra --check .` | Opinionated Nix formatter — check mode |
| 3b | `nixpkgs-fmt` (fallback) | `nixpkgs-fmt --check .` | Standard Nix formatter — check mode |
| 4 | `statix` | `statix check .` | Nix anti-pattern linter |

**Tool detection logic:**
- For formatting (step 3): check `alejandra` first; if absent, try `nixpkgs-fmt`; if neither present, print a warning and skip
- For linting (step 4): check `statix`; if absent, print a warning and skip
- If a tool IS present and its check FAILS, treat as **fatal** (exit non-zero)

### Exit Behaviour

| Outcome | Exit Code |
|---------|-----------|
| All checks pass | `0` |
| `nix flake check` fails | `1` |
| `nix eval` fails | `1` |
| Formatter check fails (tool present) | `1` |
| Linter check fails (tool present) | `1` |

---

## 4. Implementation Steps

1. Create directory `scripts/` in repository root
2. Create `scripts/preflight.sh` with the following structure:

```bash
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
if nix flake check 2>&1; then
  pass "nix flake check"
else
  fail "nix flake check"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2: Configuration evaluation ─────────────────────────────────────────
echo ""
echo "==> Step 2: NixOS configuration evaluation"
EVAL_CMD='nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf'
RESULT=$(eval "$EVAL_CMD" 2>&1) || true
if echo "$RESULT" | grep -q '"string"'; then
  pass "Configuration evaluation (.#nixosConfigurations.vexos)"
else
  fail "Configuration evaluation failed"
  info "$RESULT"
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
```

3. Make the script executable:
   ```bash
   chmod +x scripts/preflight.sh
   ```

---

## 5. Packages and Tools Referenced

| Tool | NixOS Package | Purpose | Fatal if Missing? |
|------|--------------|---------|-------------------|
| `nix` | built-in (NixOS) | Flake check & eval | N/A — always present |
| `alejandra` | `pkgs.alejandra` | Opinionated Nix formatter | No — skip with warning |
| `nixpkgs-fmt` | `pkgs.nixpkgs-fmt` | Standard Nix formatter | No — skip with warning |
| `statix` | `pkgs.statix` | Nix anti-pattern linter | No — skip with warning |

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `nix eval` on x86_64-linux may be slow on first run | Expected; IFD is minimal in this config |
| `alejandra` check may flag existing formatting | Formatting failures are fatal only if the tool is present; run `alejandra .` to auto-fix before re-running preflight |
| `statix` may flag intentional patterns | Review statix output; suppress false positives with `# statix: skip` inline comment |
| Script run on Windows host (no bash) | Script targets NixOS/Linux; on Windows, run inside WSL2 or NixOS VM |

---

## 7. Files to Create

| Path | Action |
|------|--------|
| `scripts/preflight.sh` | CREATE — full script as specified above |

No existing files need modification.

---

## 8. Acceptance Criteria

- [ ] `scripts/preflight.sh` exists and is executable
- [ ] Running the script in the repository root exits `0` when `nix flake check` passes
- [ ] Running the script exits non-zero when the flake has errors
- [ ] Missing optional tools produce warnings, not failures
- [ ] Output clearly distinguishes PASS / FAIL / WARN per step
