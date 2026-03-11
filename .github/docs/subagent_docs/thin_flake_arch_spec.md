# Thin Local Flake Architecture — Specification

**Feature:** `thin_flake_arch`
**Date:** 2026-03-11
**Status:** DRAFT — Ready for Implementation

---

## Table of Contents

1. [Current Architecture Analysis](#1-current-architecture-analysis)
2. [Problem Statement](#2-problem-statement)
3. [Goals and Constraints](#3-goals-and-constraints)
4. [Proposed Architecture](#4-proposed-architecture)
5. [Research Findings](#5-research-findings)
6. [Exact Nix Code — `lib.mkVexosSystem`](#6-exact-nix-code--libmkvexossystem)
7. [Exact Content — Thin `/etc/nixos/flake.nix`](#7-exact-content--thin-etcnixosflakenix)
8. [Implementation Plan](#8-implementation-plan)
9. [Risks and Mitigations](#9-risks-and-mitigations)
10. [Checklist for Implementer](#10-checklist-for-implementer)

---

## 1. Current Architecture Analysis

### 1.1 File Tree

```
vex-nix/
├── flake.nix                          # Flake entry point
├── hosts/
│   └── default/
│       ├── configuration.nix          # System settings, imports all modules
│       └── hardware-configuration.nix # Template (placeholder, checked in)
├── modules/
│   ├── asus.nix
│   ├── gaming.nix
│   ├── gnome.nix
│   ├── gpu.nix
│   └── system.nix
│   └── users.nix
├── home/
│   └── default.nix                   # Home Manager config for user "nimda"
└── scripts/
    ├── deploy.sh                     # Copies repo → /etc/nixos/, runs nixos-rebuild
    └── preflight.sh                  # CI validation: flake check, eval, fmt, lint
```

### 1.2 Current `flake.nix` Structure

The flake declares three inputs:

| Input | URL | Pin Strategy |
|-------|-----|--------------|
| `nixpkgs` | `github:nixos/nixpkgs/nixos-25.11` | Branch-pinned |
| `home-manager` | `github:nix-community/home-manager/release-25.11` | Branch-pinned, follows nixpkgs |
| `nix-gaming` | `github:fufexan/nix-gaming` | Tracks main, follows nixpkgs |

The `outputs` function produces a single `nixosConfigurations.vexos` that:
- Calls `nixpkgs.lib.nixosSystem { system = "x86_64-linux"; ... }`
- Directly imports **both** `./hosts/default/configuration.nix` AND `./hosts/default/hardware-configuration.nix`
- Imports two nix-gaming NixOS modules (`pipewireLowLatency`, `platformOptimizations`)
- Integrates Home Manager via `home-manager.nixosModules.home-manager`
- Passes `inputs` via `specialArgs` so modules can reference upstream flake inputs

### 1.3 Current `hosts/default/configuration.nix` Structure

Imports all six modules via repo-relative paths:
```
../../modules/system.nix
../../modules/gnome.nix
../../modules/users.nix
../../modules/gpu.nix
../../modules/gaming.nix
../../modules/asus.nix
```

Sets hostname (`vexos`), timezone (`America/New_York`), locale, bootloader (GRUB on `/dev/sda`), networking, PipeWire audio, and `system.stateVersion = "24.05"`.

**Important:** Hardware-configuration is NOT imported here — it is a separate module in `flake.nix`.

### 1.4 Current `hardware-configuration.nix`

The checked-in version is a **template** sentinel file, identifiable by the comment:
```
# This is a template hardware configuration.
```
It sets `nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"` — the modern NixOS way to declare system architecture without the deprecated `system =` argument to `nixosSystem`.

### 1.5 Current Deploy Workflow

```
Developer Machine:
  git clone github:VictoryTek/vex-nix
  sudo nixos-generate-config --show-hardware-config > hosts/default/hardware-configuration.nix
  sudo bash scripts/deploy.sh
    → rsync repo to /etc/nixos/
    → handle hardware-configuration.nix (regen or keep)
    → sudo nixos-rebuild switch --flake /etc/nixos#vexos
```

### 1.6 Current `home/default.nix` Shell Aliases

The `update` and `rebuild` aliases currently point to the repo clone location:
```nix
update = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
rebuild = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
```
These will become stale under the new architecture.

### 1.7 Current `preflight.sh` Checks

| Step | Check | Command |
|------|-------|---------|
| 1 | Flake validity | `nix flake check` |
| 2 | Config evaluation | `nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf` |
| 3 | Nix formatting | `alejandra --check .` or `nixpkgs-fmt --check .` |
| 4 | Lint | `statix check .` |

---

## 2. Problem Statement

The current deploy model has three structural weaknesses:

1. **Hardware config is in the repo.** The `hardware-configuration.nix` template must be replaced per-machine, making the repo not cleanly hardware-agnostic. It is also fragile: accidentally committing machine-specific hardware configs pollutes the shared repo.

2. **Installation requires cloning the full repo.** A fresh NixOS install requires the user to install git, clone the repo, manually overwrite `hardware-configuration.nix`, then run a deploy script. This is a multi-step process with mutation risk.

3. **`/etc/nixos/` holds the entire repo.** Any upstream change requires re-running `deploy.sh` to copy/sync the repo. There is no automatic pull from GitHub — the two can silently diverge.

---

## 3. Goals and Constraints

| # | Requirement | Status |
|---|-------------|--------|
| G1 | Hardware-agnostic: `hardware-configuration.nix` lives only on the target machine | Required |
| G2 | No `--impure` flag — pure flake build | Required |
| G3 | No `git clone` of vex-nix needed on fresh install | Required |
| G4 | `/etc/nixos/` contains only 3 files: `flake.nix`, `flake.lock`, `hardware-configuration.nix` | Required |
| G5 | GitHub repo exposes `lib.mkVexosSystem` for thin flake consumption | Required |
| G6 | GitHub repo's `nixosConfigurations.vexos` is preserved for CI / `nix flake check` | Required |
| G7 | Same code quality and consistency as existing scripts | Required |

---

## 4. Proposed Architecture

### 4.1 ASCII Diagram

```
═══════════════════════════════════════════════════════════════════════
  CURRENT (deploy script copies full repo to /etc/nixos/)
═══════════════════════════════════════════════════════════════════════

  GitHub Repo: VictoryTek/vex-nix
  ┌───────────────────────────────────┐
  │ flake.nix                         │
  │   nixosConfigurations.vexos ──────┼─── nixpkgs.lib.nixosSystem
  │     modules = [                   │         system = "x86_64-linux"
  │       configuration.nix,          │         modules = [all]
  │       hardware-configuration.nix, │
  │       nix-gaming modules,         │
  │       home-manager module         │   ← hardware-conf LIVES IN REPO
  │     ]                             │     (template placeholder)
  └───────────────────────────────────┘
           │ deploy.sh rsync
           ▼
  Target Machine /etc/nixos/
  ┌───────────────────────────────────┐
  │ (full repo copy)                  │
  │ flake.nix                         │   ← entire repo
  │ hosts/default/                    │
  │   configuration.nix               │
  │   hardware-configuration.nix      │   ← machine-specific (replaced)
  │ modules/...                       │
  │ home/...                          │
  └───────────────────────────────────┘
     nixos-rebuild switch --flake /etc/nixos#vexos


═══════════════════════════════════════════════════════════════════════
  PROPOSED (thin local flake at /etc/nixos/, GitHub as input)
═══════════════════════════════════════════════════════════════════════

  GitHub Repo: VictoryTek/vex-nix
  ┌──────────────────────────────────────────────┐
  │ flake.nix                                    │
  │                                              │
  │   lib.mkVexosSystem { hardwareModule }  ─────┼──┐ (exported lib fn)
  │     → nixpkgs.lib.nixosSystem {              │  │
  │         inherit system;                      │  │
  │         modules = [                          │  │
  │           hardwareModule,          ◄─────────┼──┼── injected by caller
  │           ./hosts/default/config.nix,        │  │
  │           nix-gaming modules,                │  │
  │           home-manager module                │  │
  │         ]                                    │  │
  │       }                                      │  │
  │                                              │  │
  │   nixosConfigurations.vexos ─────────────────┼──┘
  │     = self.lib.mkVexosSystem {               │    (CI: uses template
  │         hardwareModule =                     │     hardware-conf)
  │           ./hosts/default/hardware-conf.nix  │
  │       }                                      │
  └──────────────────────────────────────────────┘
               ▲
               │ inputs.vexos.url = "github:VictoryTek/vex-nix"
               │ (pinned via flake.lock)
               │
  Target Machine /etc/nixos/
  ┌──────────────────────────────────────────────┐
  │ flake.nix         (3 files only)             │
  │   inputs.vexos.url = github:VictoryTek/...   │
  │   nixosConfigurations.vexos =                │
  │     vexos.lib.mkVexosSystem {                │
  │       hardwareModule =                       │
  │         ./hardware-configuration.nix         │ ← machine-specific
  │     }                                        │   NEVER in GitHub repo
  │                                              │
  │ flake.lock        (pinned upstream)          │
  │ hardware-configuration.nix (generated)       │
  └──────────────────────────────────────────────┘
     nixos-rebuild switch --flake /etc/nixos#vexos


═══════════════════════════════════════════════════════════════════════
  DATA FLOW — how ./hardware-configuration.nix stays pure
═══════════════════════════════════════════════════════════════════════

  1. /etc/nixos/ is initialized as a git repo (git init + git add)
  2. Nix evaluates /etc/nixos/flake.nix — copies all tracked files
     into the Nix store:
       /nix/store/HASH-source/flake.nix
       /nix/store/HASH-source/hardware-configuration.nix
  3. `self` in the thin flake outputs = /nix/store/HASH-source/
  4. `./hardware-configuration.nix` = ${self}/hardware-configuration.nix
     → a store path → fully pure, no --impure required
  5. This store path is passed as `hardwareModule` to mkVexosSystem
  6. The GitHub repo evaluates it as a normal NixOS module
```

### 4.2 File Change Summary

| File | Action | Scope |
|------|--------|-------|
| `flake.nix` | Modify | Add `lib.mkVexosSystem`; update `nixosConfigurations.vexos` to use it |
| `hosts/default/configuration.nix` | No change | Hardware is threaded via the lib function, not here |
| `hosts/default/hardware-configuration.nix` | No change | Stays as CI template sentinel |
| `home/default.nix` | Modify | Update `update`/`rebuild` aliases to `/etc/nixos#vexos` |
| `scripts/install.sh` | Create | New bootstrap script |
| `scripts/deploy.sh` | Modify | Graceful deprecation notice |
| `scripts/preflight.sh` | Modify | Add `lib.mkVexosSystem` existence check |
| `README.md` | Modify | Rewrite Installation section |

---

## 5. Research Findings

### 5.1 Sources Consulted

1. **NixOS Wiki — Flakes output schema** (`wiki.nixos.org/wiki/Flakes`)
   - Confirmed: `lib` is a valid, unscoped flake output attribute
   - Any arbitrary attribute in the outputs attrset is legal; Nix only acts on known ones (`nixosConfigurations`, `packages`, etc.)
   - Custom library functions go under `lib.<name>`

2. **NixOS & Flakes Book** (`nixos-and-flakes.thiscute.world`)
   - Confirmed: `specialArgs` / `_module.args` pattern for threading inputs into modules
   - Confirmed: modules receive injected arguments by name matching — no positional passing required

3. **nixpkgs `lib/eval-config.nix`** (NixOS 25.11 source)
   - `nixpkgs.lib.nixosSystem` signature: `{ system?, modules, specialArgs?, ... }`
   - The `system` parameter has `default = null` in NixOS 22.05+ (not `builtins.currentSystem`)
   - When `nixpkgs.hostPlatform` is set in a module, it takes precedence over `system`
   - The template `hardware-configuration.nix` already sets `nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"` — this is sufficient

4. **NixOS module system path resolution**
   - Paths in module `imports` lists are resolved relative to the `.nix` file containing them
   - Paths passed as module arguments (e.g., a path value passed to `nixosSystem modules`) are resolved at the call site
   - Therefore: `hardwareModule = ./hardware-configuration.nix` in the thin flake resolves to `${self}/hardware-configuration.nix` (a store path) — correct

5. **nixos-anywhere documentation** (`nix-community/nixos-anywhere`)
   - Recommended pattern: `nixos-generate-config --no-filesystems --dir /tmp/config` then commit to a flake
   - Confirms: `hardware-configuration.nix` should be generated per-machine and consumed as a flake module
   - Confirms: `nix run github:nix-community/nixos-anywhere -- --generate-hardware-config ...` as alternative bootstrap

6. **NixOS Wiki — `/etc/nixos/` as a flake** (community experience)
   - `/etc/nixos/` must be a `git` repository for pure flake evaluation without `--impure`
   - `git init && git add .` is the minimal setup; no remotes required
   - `nix flake update` generates `flake.lock` into the git-tracked directory
   - After `nix flake update`, run `git add flake.lock` to track the lock file
   - `nixos-rebuild switch --flake /etc/nixos#hostname` then works in pure mode

7. **NixOS community flake conventions** (multiple community repos including `flake-utils`, nix-community orgs)
   - `lib.mkSystem` (or similar) is the established pattern used by many multi-host configurations (e.g., nix-darwin, nixpkgs itself uses `lib.nixosSystem`)
   - The function should accept a attrset argument, not positional args, for forward compatibility
   - Keeping a `nixosConfigurations.vexos` in the GitHub repo for CI is standard practice — it validates the configuration evaluates correctly even when hardware specifics are templated

### 5.2 Pure Flake Evaluation — How It Works Without `--impure`

The key mechanism making this pure:

```
/etc/nixos/ initialized as git repo
         │
         │ git add flake.nix hardware-configuration.nix flake.lock
         ▼
Nix reads git index to determine "what's in the flake"
         │
         │ copies tracked files to Nix store
         ▼
self = /nix/store/XXXXXXXXXXXXXXXXXXXXXXXXXX-source
         │
./hardware-configuration.nix
= ${self}/hardware-configuration.nix
= /nix/store/XXXXXXXXXXXXXXXXXXXXXXXXXX-source/hardware-configuration.nix
         │
         ▼ passed to lib.mkVexosSystem { hardwareModule = <store-path>; }
         │
GitHub repo evaluates store path as a NixOS module
         │
         ▼ PURE — no filesystem access outside Nix store
```

No `--impure` is needed because:
- The thin flake's directory is a git repo → Nix can determine a reproducible file set
- `./hardware-configuration.nix` resolves to a deterministic store path
- `flake.lock` pins the GitHub repo revision

---

## 6. Exact Nix Code — `lib.mkVexosSystem`

### 6.1 New `flake.nix`

```nix
{
  description = "VexOS - Personal NixOS Configuration with GNOME";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
  let
    # ── lib.mkVexosSystem ──────────────────────────────────────────────
    # Builds a complete VexOS NixOS system configuration.
    #
    # Arguments:
    #   hardwareModule — a NixOS module (path or inline attrset) that
    #                    provides hardware-specific configuration.
    #                    MUST set nixpkgs.hostPlatform or the system
    #                    defaults to "x86_64-linux".
    #   system         — override the default platform string.
    #                    Ignored if hardwareModule sets nixpkgs.hostPlatform.
    #
    # Usage from a thin local flake:
    #   nixosConfigurations.myhostname = vexos.lib.mkVexosSystem {
    #     hardwareModule = ./hardware-configuration.nix;
    #   };
    mkVexosSystem = { hardwareModule, system ? "x86_64-linux" }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          hardwareModule
          ./hosts/default/configuration.nix

          # nix-gaming NixOS modules
          inputs.nix-gaming.nixosModules.pipewireLowLatency
          inputs.nix-gaming.nixosModules.platformOptimizations

          # Home Manager integration
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.nimda = import ./home/default.nix;
          }
        ];
      };
  in
  {
    # ── Library output ────────────────────────────────────────────────
    # Exposed for consumption by thin local flakes on target machines.
    lib.mkVexosSystem = mkVexosSystem;

    # ── CI / nix flake check configuration ───────────────────────────
    # Uses the in-repo template hardware-configuration.nix.
    # This is NOT the configuration deployed to real machines.
    nixosConfigurations = {
      vexos = mkVexosSystem {
        hardwareModule = ./hosts/default/hardware-configuration.nix;
      };
    };
  };
}
```

### 6.2 Design Notes

**Why `system ? "x86_64-linux"` rather than omitting `system`?**

`nixpkgs.lib.nixosSystem` requires a platform. In NixOS 22.05+, setting `nixpkgs.hostPlatform` inside a module takes precedence over the `system` argument. The function provides a safe default so callers don't have to specify it if they include a modern `nixos-generate-config`-produced hardware config (which always sets `nixpkgs.hostPlatform`). Callers on non-x86_64 hardware that produce unusual hardware configs can override via `system = "aarch64-linux"`.

**Why `self.lib.mkVexosSystem` is NOT used for `nixosConfigurations.vexos`?**

We use the locally defined `mkVexosSystem` (from the `let` binding) rather than `self.lib.mkVexosSystem` for the CI config to avoid a self-referential dependency cycle during `nix flake check`. Referencing `self` in `outputs` for things that feed back into `nixosConfigurations` can cause evaluation issues. The `let` binding provides the same function without self-reference.

**Why pass `inputs` via `specialArgs`?**

`configuration.nix` (and by extension `modules/gaming.nix`, which comments that nix-gaming modules are imported in `flake.nix`) relies on `inputs` being available in modules for potential future use. The existing pattern is preserved from the current `flake.nix`.

---

## 7. Exact Content — Thin `/etc/nixos/flake.nix`

This is the file written by `scripts/install.sh` to `/etc/nixos/flake.nix`:

```nix
{
  description = "VexOS local machine configuration";

  inputs.vexos.url = "github:VictoryTek/vex-nix";

  outputs = { self, vexos, ... }: {
    nixosConfigurations.vexos = vexos.lib.mkVexosSystem {
      hardwareModule = ./hardware-configuration.nix;
    };
  };
}
```

**Line count:** 10 lines (excluding blank line at end).

### 7.1 User Customization Points

| Customization | Where to change |
|---------------|----------------|
| Hostname (for `nixos-rebuild switch --flake /etc/nixos#NAME`) | Replace `vexos` in `nixosConfigurations.vexos` (thin flake) AND `networking.hostName` in `hosts/default/configuration.nix` |
| Pin to a specific git commit/tag | `inputs.vexos.url = "github:VictoryTek/vex-nix/REF"` |
| Use a local development checkout | `inputs.vexos.url = "path:/home/nimda/Projects/vex-nix"` |

### 7.2 Update Workflow After Thin Flake Is Installed

```bash
# On the target machine — update to latest GitHub main:
cd /etc/nixos
sudo nix flake update
sudo git add flake.lock
sudo nixos-rebuild switch --flake /etc/nixos#vexos

# To make updates automatic via the rebuild alias:
# The home.nix alias handles this:
#   update = "cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake /etc/nixos#vexos"
# (see home/default.nix changes in section 8)
```

---

## 8. Implementation Plan

### Phase 1: Modify `flake.nix`

**File:** `flake.nix`
**Change:** Add `lib.mkVexosSystem` output; refactor `nixosConfigurations.vexos` to use it.

See exact code in [Section 6.1](#61-new-flakenix).

Key structural change:
- Extract the `nixosSystem` call into a `let`-bound `mkVexosSystem` function
- Add `lib.mkVexosSystem = mkVexosSystem;` to the outputs attrset
- Rewrite `nixosConfigurations.vexos` to call `mkVexosSystem { hardwareModule = ...; }`

---

### Phase 2: Modify `home/default.nix`

**File:** `home/default.nix`
**Change:** Update `update` and `rebuild` shell aliases.

Current:
```nix
update = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
rebuild = "sudo nixos-rebuild switch --flake /home/nimda/Projects/vex-nix#vexos";
```

New:
```nix
update  = "cd /etc/nixos && sudo nix flake update && sudo git add flake.lock && sudo nixos-rebuild switch --flake /etc/nixos#vexos";
rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#vexos";
```

The `update` alias now also runs `nix flake update` to pick up the latest GitHub commit before rebuilding. `rebuild` is kept as a quick rebuild without updating the lock file.

---

### Phase 3: Create `scripts/install.sh`

**File:** `scripts/install.sh` (new file)
**Purpose:** Bootstrap a fresh NixOS installation — writes the thin flake and prepares `/etc/nixos/` for pure flake builds.

The script must follow the exact same coding style as `deploy.sh`:
- Bash strict mode: `set -euo pipefail`
- Colour helpers: `pass()`, `fail()`, `warn()`, `info()`, `step()`
- Error trap with `cleanup_on_error`
- Dry-run support via `run()` helper and `OPT_DRYRUN` flag
- Root check
- Named steps with progress output

#### Full Script Content

```bash
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
  -y, --yes          Skip all interactive confirmation prompts
      --hostname     Set the NixOS configuration name (default: vexos)
      --dry-run      Print what would happen; make no changes
  -h, --help         Show this help and exit

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
run() {
    if [[ "$OPT_DRYRUN" == "true" ]]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

# ── Step 1: Banner ────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  VexOS Install — scripts/install.sh${NC}"
echo -e "${BLUE}  Target   : /etc/nixos${NC}"
echo -e "${BLUE}  Hostname : ${HOSTNAME}${NC}"
echo -e "${BLUE}  Dry-run  : ${OPT_DRYRUN}${NC}"
echo -e "${BLUE}============================================${NC}"

# ── Step 2: Root check ────────────────────────────────────────────────────────
step "Step 2: Root check"
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

# ── Step 3: Dependency check ──────────────────────────────────────────────────
step "Step 3: Dependency check"

for cmd in nix git; do
    if ! command -v "$cmd" &>/dev/null; then
        fail "Required command not found: $cmd"
        exit 1
    else
        pass "$cmd found"
    fi
done

# ── Step 4: Verify hardware-configuration.nix ────────────────────────────────
step "Step 4: Verify hardware-configuration.nix"
HW_CONFIG="/etc/nixos/hardware-configuration.nix"

if [[ ! -f "$HW_CONFIG" ]]; then
    fail "hardware-configuration.nix not found at $HW_CONFIG"
    info ""
    info "Generate it first with the NixOS live installer:"
    info "  sudo nixos-generate-config"
    info ""
    info "Then re-run this script."
    exit 1
fi

# Warn if it looks like a VexOS template rather than a real generated config
if grep -q "# This is a template hardware configuration" "$HW_CONFIG" 2>/dev/null; then
    fail "The file at $HW_CONFIG appears to be the VexOS template sentinel,"
    info "not a machine-generated hardware configuration."
    info ""
    info "Generate a real one with:"
    info "  sudo nixos-generate-config"
    exit 1
fi

pass "hardware-configuration.nix found and appears machine-generated"

# ── Step 5: Confirmation ──────────────────────────────────────────────────────
step "Step 5: Confirmation"
if [[ "$OPT_DRYRUN" == "true" ]]; then
    info "Dry-run mode — skipping confirmation prompt."
elif [[ "$OPT_YES" == "true" ]]; then
    info "Auto-confirmed via --yes."
else
    echo ""
    echo "  About to write /etc/nixos/flake.nix and initialise /etc/nixos/ as a git repo."
    echo "  Existing /etc/nixos/ contents will be preserved."
    printf "  Continue? [y/N] "
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        warn "Aborted by user."
        exit 0
    fi
fi

# ── Step 6: Write /etc/nixos/flake.nix ───────────────────────────────────────
step "Step 6: Write /etc/nixos/flake.nix"

FLAKE_CONTENT='{
  description = "VexOS local machine configuration";

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
    echo "$FLAKE_CONTENT" > /etc/nixos/flake.nix
    pass "Wrote /etc/nixos/flake.nix"
fi

# ── Step 7: Initialise git repo ───────────────────────────────────────────────
step "Step 7: Initialise git repo in /etc/nixos/"
info "(Required for pure flake evaluation — no remote is set up)"

if [[ -d /etc/nixos/.git ]]; then
    pass "/etc/nixos/ is already a git repository"
else
    run git -C /etc/nixos init -b main
    if [[ "$OPT_DRYRUN" == "false" ]]; then
        pass "Initialised git repo at /etc/nixos/"
    fi
fi

# ── Step 8: Stage files ───────────────────────────────────────────────────────
step "Step 8: Stage flake.nix and hardware-configuration.nix"
run git -C /etc/nixos add flake.nix hardware-configuration.nix
if [[ "$OPT_DRYRUN" == "false" ]]; then
    pass "Staged files"
fi

# ── Step 9: Generate flake.lock ───────────────────────────────────────────────
step "Step 9: nix flake update (generates flake.lock)"
info "This fetches the latest VexOS revision from GitHub."
info "It may take a minute on first run."

run nix \
    --extra-experimental-features 'nix-command flakes' \
    flake update \
    /etc/nixos

if [[ "$OPT_DRYRUN" == "false" ]]; then
    pass "flake.lock generated"
fi

# ── Step 10: Stage flake.lock ─────────────────────────────────────────────────
step "Step 10: Stage flake.lock"
run git -C /etc/nixos add flake.lock
if [[ "$OPT_DRYRUN" == "false" ]]; then
    pass "flake.lock staged"
fi

# ── Step 11: Summary ──────────────────────────────────────────────────────────
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
```

---

### Phase 4: Deprecate `scripts/deploy.sh`

**File:** `scripts/deploy.sh`
**Change:** Replace the banner and main body with a deprecation notice that immediately exits with a helpful message. The script should NOT be deleted (git history is valuable; a graceful notice is better UX).

The new `deploy.sh` should:
- Keep the same colour helper setup and `set -euo pipefail`
- Print a clearly formatted deprecation box
- Point to `install.sh` for fresh installs
- Point to the `nixos-rebuild switch --flake /etc/nixos#vexos` workflow for updates
- Exit 0 (it's a notice, not an error)

**Exact replacement content for `scripts/deploy.sh`:**

```bash
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
```

---

### Phase 5: Update `scripts/preflight.sh`

**File:** `scripts/preflight.sh`
**Change:** Add a new Step 2b that verifies `lib.mkVexosSystem` is exported by the flake. All existing steps remain unchanged.

Insert between current Step 2 (configuration evaluation) and Step 3 (formatting check):

```bash
# ── Step 2b: Verify lib.mkVexosSystem is exported ─────────────────────────
echo ""
echo "==> Step 2b: Verify lib.mkVexosSystem output"
LIB_CMD="nix --extra-experimental-features 'nix-command flakes' eval .#lib.mkVexosSystem --apply builtins.typeOf"
LIB_RESULT=$(eval "$LIB_CMD" 2>&1) || true
if echo "$LIB_RESULT" | grep -q '"lambda"'; then
  pass "lib.mkVexosSystem is exported and is a function"
else
  fail "lib.mkVexosSystem is missing or not a function"
  info "$LIB_RESULT"
  ERRORS=$((ERRORS + 1))
fi
```

---

### Phase 6: Update `README.md`

**File:** `README.md`
**Change:** Replace the entire `## Installation` and `## Automated Deployment` sections with the new workflow. The `## What's Included` and `## Post-Install` sections remain unchanged.

**New Installation section:**

```markdown
## Installation

### Fresh Install (New Machine)

From the NixOS live installer environment:

1. **Partition and mount your disks** (use the NixOS manual or `nixos-generate-config`)

2. **Generate hardware configuration**
   ```bash
   sudo nixos-generate-config
   ```
   This writes `/etc/nixos/hardware-configuration.nix` for your machine.

3. **Bootstrap the VexOS thin flake**

   From within the cloned repo (if available), or directly from the live environment:
   ```bash
   # Option A: from a clone of vex-nix (if you have it):
   sudo bash scripts/install.sh

   # Option B: manually (no clone required):
   sudo tee /etc/nixos/flake.nix > /dev/null <<'EOF'
   {
     description = "VexOS local machine configuration";

     inputs.vexos.url = "github:VictoryTek/vex-nix";

     outputs = { self, vexos, ... }: {
       nixosConfigurations.vexos = vexos.lib.mkVexosSystem {
         hardwareModule = ./hardware-configuration.nix;
       };
     };
   }
   EOF

   cd /etc/nixos
   git init -b main
   git add flake.nix hardware-configuration.nix
   nix --extra-experimental-features 'nix-command flakes' flake update
   git add flake.lock
   ```

4. **Customise for your machine**

   The VexOS configuration lives in the GitHub repo, not on your machine.
   Fork or edit the repo to change:
   - `modules/users.nix` — username, shell, groups
   - `hosts/default/configuration.nix` — hostname, timezone, bootloader, packages
   - `home/default.nix` — user packages, shell aliases, GTK theme
   - `modules/gpu.nix` — set `gpu.type` to `"nvidia"`, `"amd"`, or `"intel"`

5. **Activate**
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#vexos
   ```

6. **Reboot**

---

### Updating

After the initial install, `/etc/nixos/` has only three files and pulls
all configuration from GitHub:

```bash
# Update to latest VexOS from GitHub:
cd /etc/nixos
sudo nix flake update
sudo git add flake.lock
sudo nixos-rebuild switch --flake /etc/nixos#vexos

# Quick rebuild (no upstream update):
sudo nixos-rebuild switch --flake /etc/nixos#vexos
```

The `update` shell alias in your user environment does this automatically:
```bash
update   # runs: nix flake update + nixos-rebuild switch
rebuild  # runs: nixos-rebuild switch (skip update)
```

---

### What Lives Where

| Location | Contents |
|----------|----------|
| `/etc/nixos/flake.nix` | Thin consumer flake — points to GitHub repo |
| `/etc/nixos/flake.lock` | Pinned revision of all upstream flake inputs |
| `/etc/nixos/hardware-configuration.nix` | This machine only — never in the GitHub repo |
| `github:VictoryTek/vex-nix` | All system config, modules, home config |
```

---

## 9. Risks and Mitigations

### Risk 1: Git repo not initialized in `/etc/nixos/` — impure eval error

**Likelihood:** High (easy to miss step)
**Impact:** `nixos-rebuild switch` fails with "path is not allowed in pure eval mode"

**Mitigation:**
- `install.sh` performs `git init` + `git add` unconditionally
- The script also idempotently skips `git init` if `.git` already exists
- README manual steps include `git init` explicitly

---

### Risk 2: `flake.lock` not staged after `nix flake update`

**Likelihood:** Medium (easy to forget `git add flake.lock`)
**Impact:** Nix sees unstaged changes; rebuild may fail or use wrong pinned revision

**Mitigation:**
- `install.sh` automatically runs `git -C /etc/nixos add flake.lock` after `nix flake update`
- The `update` alias in `home/default.nix` includes `sudo git add flake.lock`
- Documented in README

---

### Risk 3: User's hardware-configuration.nix does NOT set `nixpkgs.hostPlatform`

**Likelihood:** Low (modern NixOS installer always sets it)
**Impact:** If `nixpkgs.hostPlatform` is not set, the `system = "x86_64-linux"` default in `mkVexosSystem` is used — which is correct for most users but silently wrong for aarch64 machines

**Mitigation:**
- `mkVexosSystem` accepts an explicit `system` override parameter
- Document in README that aarch64 users must pass `system = "aarch64-linux"`
- NixOS 22.05+ installer-generated hardware configs always set `nixpkgs.hostPlatform`

---

### Risk 4: `configuration.nix` has machine-specific bootloader config

**Likelihood:** High for non-x86_64 / non-BIOS machines
**Impact:** `boot.loader.grub.device = "/dev/sda"` is wrong for UEFI machines or machines with NVMe drives

**Mitigation:**
- This is a pre-existing issue, not introduced by this refactor
- Document in README / configuration.nix comments that users must update bootloader config
- Consider: future work could add a `bootloaderModule` parameter to `mkVexosSystem` — out of scope for this refactor

---

### Risk 5: `nix flake check` in CI fails if `lib.mkVexosSystem` is not a proper lambda

**Likelihood:** Low (syntactically valid Nix won't fail here)
**Impact:** preflight.sh step 2b incorrectly reports failure

**Mitigation:**
- Step 2b uses `builtins.typeOf` and checks for `"lambda"` — the string returned for all Nix function values
- If the attribute doesn't exist, `nix eval` produces an error message, captured and reported as FAIL

---

### Risk 6: `home/default.nix` `update` alias is very long — may be clipped in terminals

**Likelihood:** Low
**Impact:** Visual annoyance only; the alias functions correctly

**Mitigation:**
- Split the one-liner into a proper shell function in a future iteration, or use a wrapper script
- For now, the single long alias is the minimal change

---

### Risk 7: Users on GitHub forks need to update `inputs.vexos.url`

**Likelihood:** Medium (power users who fork)
**Impact:** Fork users pull from upstream, not their fork

**Mitigation:**
- `install.sh` uses the hardcoded URL `github:VictoryTek/vex-nix`; fork users would edit this
- Document the URL customization in README
- The `install.sh` could accept a `--url` argument in future

---

## 10. Checklist for Implementer

- [ ] Read and understand this spec completely before making any changes
- [ ] Modify `flake.nix` per [Section 6.1](#61-new-flakenix)
  - [ ] Add `let ... mkVexosSystem = ...` block
  - [ ] Add `lib.mkVexosSystem = mkVexosSystem;` to outputs
  - [ ] Rewrite `nixosConfigurations.vexos` to call `mkVexosSystem { hardwareModule = ...; }`
  - [ ] Run `nix flake check` — must pass
  - [ ] Run `nix eval .#lib.mkVexosSystem --apply builtins.typeOf` — must output `"lambda"`
- [ ] Modify `home/default.nix` per [Section 8 Phase 2](#phase-2-modify-homedefaultnix)
  - [ ] Update `update` alias
  - [ ] Update `rebuild` alias
- [ ] Create `scripts/install.sh` per [Section 8 Phase 3](#phase-3-create-scriptsinstallsh)
  - [ ] File is executable: `chmod +x scripts/install.sh`
  - [ ] Dry-run mode works: `bash scripts/install.sh --dry-run`
  - [ ] Detects template hardware config and exits with helpful error
- [ ] Modify `scripts/deploy.sh` per [Section 8 Phase 4](#phase-4-deprecate-scriptsdeploysh)
  - [ ] Script exits 0 (notice, not error)
  - [ ] Points to `install.sh` and the new workflow
- [ ] Modify `scripts/preflight.sh` per [Section 8 Phase 5](#phase-5-update-scriptspreflightsh)
  - [ ] New step 2b inserted between existing steps 2 and 3
  - [ ] All existing steps preserved and renumbered if needed
- [ ] Modify `README.md` per [Section 8 Phase 6](#phase-6-update-readmemd)
  - [ ] Old `## Installation` section replaced
  - [ ] Old `## Automated Deployment` section replaced
  - [ ] `## What's Included` and `## Post-Install` sections preserved
- [ ] Run `scripts/preflight.sh` — all checks must pass (including new step 2b)
- [ ] Verify `nix flake show` shows `lib` output and `nixosConfigurations.vexos`

---

*End of specification. Spec path: `.github/docs/subagent_docs/thin_flake_arch_spec.md`*
