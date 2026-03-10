# Deploy Script Specification — `scripts/deploy.sh`

**Project:** VexOS NixOS Configuration  
**Spec Date:** 2026-03-10  
**Author:** Research & Specification Subagent  
**Target Path:** `scripts/deploy.sh`  
**Flake Target:** `/etc/nixos#vexos`

---

## 1. Purpose

`scripts/deploy.sh` is a one-shot deployment script that copies the vex-nix repository
to `/etc/nixos/`, resolves the hardware configuration intelligently, and activates
the system with `nixos-rebuild switch`.

---

## 2. Source Analysis

### 2.1 Repository Structure

```
flake.nix                                  ← defines outputs.nixosConfigurations.vexos
hosts/default/configuration.nix            ← imports modules, sets hostname "vexos"
hosts/default/hardware-configuration.nix   ← TEMPLATE only — must never be copied as-is
modules/{gnome,gpu,system,users}.nix
home/default.nix
scripts/preflight.sh                        ← style reference
```

### 2.2 Flake Target Name

The NixOS configuration is exposed at:

```
.#nixosConfigurations.vexos
```

Therefore the rebuild command is:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos
```

### 2.3 Hardware Config Is a Template

`hosts/default/hardware-configuration.nix` begins with:

```nix
# This is a template hardware configuration.
```

This sentinel comment is used by the script to detect whether a file is the
repo template (unsafe to deploy) or a real machine-generated config (safe to keep).

### 2.4 Style Reference — `scripts/preflight.sh`

The existing preflight script establishes these conventions (all must be followed):

| Convention | Value |
|---|---|
| Shebang | `#!/usr/bin/env bash` |
| Safety flags | `set -euo pipefail` |
| Colour variables | `RED`, `GREEN`, `YELLOW`, `NC` |
| Output functions | `pass()`, `fail()`, `warn()`, `info()` |
| Prefix format | `[PASS]`, `[FAIL]`, `[WARN]`; info uses leading spaces |
| Step headers | `echo "==> Step N: <description>"` |
| Error counting | `ERRORS=0` accumulator, `ERRORS=$((ERRORS + 1))` |
| Final result | Colour-boxed `=====` banner block |

---

## 3. Script Flags

| Flag | Short | Behaviour |
|---|---|---|
| `--yes` | `-y` | Skip all interactive confirmations; assume "yes" |
| `--regen-hardware` | | Force regeneration of hardware-configuration.nix via `nixos-generate-config` regardless of what exists |
| `--keep-hardware` | | Always preserve existing `/etc/nixos/hardware-configuration.nix`; error if none exists and this flag is set |
| `--dry-run` | | Print all actions that *would* be taken, but make no changes |
| `--help` | `-h` | Print usage and exit 0 |

**Mutual exclusivity:** `--regen-hardware` and `--keep-hardware` are mutually exclusive.
If both are supplied the script must print a `[FAIL]` message and exit 1.

---

## 4. Script Flow (Ordered Steps)

### Step 0 — Argument Parsing

- Parse all flags into boolean shell variables:
  - `OPT_YES=false`, `OPT_REGEN=false`, `OPT_KEEP=false`, `OPT_DRYRUN=false`
- Detect mutual exclusion (`--regen-hardware` + `--keep-hardware`) and abort early.
- If `--help`, print usage block and `exit 0`.
- Resolve `REPO_DIR` as the canonical directory containing the script:
  ```bash
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  ```

### Step 1 — Banner

Print a coloured ASCII banner identifying the script, version, and dry-run status:

```
=========================================
  VexOS Deploy — scripts/deploy.sh
  Repo : /path/to/vex-nix
  Target : /etc/nixos
  Flake  : /etc/nixos#vexos
  Dry-run: false
=========================================
```

### Step 2 — Root Check

Verify the effective user ID is 0:

```bash
if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root (use: sudo bash scripts/deploy.sh)"
    exit 1
fi
```

In dry-run mode, emit a `[WARN]` instead of failing, so the script can be previewed
without sudo.

### Step 3 — Interactive Confirmation (unless `--yes`)

Prompt the user:

```
About to deploy vex-nix → /etc/nixos and run nixos-rebuild switch.
Continue? [y/N]
```

- If the answer is not `y` / `Y`, print `[WARN] Aborted by user.` and `exit 0`.
- In dry-run mode, skip the prompt (output would be no-op).

### Step 4 — Pre-flight Dependency Check

Verify required tools are available on `$PATH`:

| Binary | Purpose |
|---|---|
| `rsync` | Preferred copy tool |
| `nixos-generate-config` | Hardware config generation |
| `nixos-rebuild` | System activation |

If `rsync` is missing, fall back to `cp` with explicit excludes (log a `[WARN]`).
If `nixos-rebuild` is missing, this is a `[FAIL]` — script cannot continue.

### Step 5 — Writability Check

```bash
if [[ ! -w /etc ]]; then
    fail "/etc is not writable. Are you running as root?"
    exit 1
fi
```

### Step 6 — Backup Existing `/etc/nixos/`

```bash
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/etc/nixos.bak-${TIMESTAMP}"
```

- If `/etc/nixos/` exists: copy (not move) it to `$BACKUP_DIR`.
  - This ensures the original is preserved even if the copy fails mid-way.
  - In dry-run mode: print `[INFO] Would backup /etc/nixos/ → $BACKUP_DIR`.
- If `/etc/nixos/` does not exist: note this is a fresh install; no backup needed.

Backup command:

```bash
cp -a /etc/nixos "$BACKUP_DIR"
pass "Backed up /etc/nixos/ → $BACKUP_DIR"
```

### Step 7 — Copy Repository to `/etc/nixos/`

**Preferred (rsync available):**

```bash
rsync -a --delete \
    --exclude='.git/' \
    --exclude='.github/' \
    "${REPO_DIR}/" /etc/nixos/
```

**Fallback (no rsync):**

```bash
cp -r "${REPO_DIR}/." /etc/nixos/
# Then remove excluded directories manually
rm -rf /etc/nixos/.git /etc/nixos/.github
```

**Dry-run:** Print the rsync command that would be run without executing it.

### Step 8 — Hardware Configuration Handling

This is the most complex step. Decision tree:

```
     ┌─ --regen-hardware set? ──────────────────────────────────────────────────┐
     │                                                                          │
    YES                                                                        NO
     │                                                                          │
     ▼                                                                          │
  Regenerate                                        ┌─ --keep-hardware set? ───┤
  (go to §8.C)                                      │                          │
                                                   YES                        NO
                                                    │                          │
                                                    ▼                          │
                                             Backup h/w config exists?  ──── NO → §8.D
                                                yes: §8.B                  YES
                                                no : FAIL                    │
                                                                      Is backup h/w config
                                                                      the repo template?
                                                                      (check sentinel comment)
                                                                        YES → §8.D
                                                                        NO  → §8.E (prompt)
```

#### §8.A — Detect Template Sentinel

```bash
is_template_hardware_config() {
    local file="$1"
    grep -q "# This is a template hardware configuration" "$file" 2>/dev/null
}
```

Returns true (exit 0) if the file is the repo template.

#### §8.B — Keep Existing (--keep-hardware)

Check that `$BACKUP_DIR/hardware-configuration.nix` exists:
- If yes: `cp "$BACKUP_DIR/hardware-configuration.nix" /etc/nixos/hosts/default/hardware-configuration.nix`
- If `$BACKUP_DIR` doesn't exist (was a fresh install): `[FAIL] --keep-hardware specified but no existing hardware-configuration.nix found.`

#### §8.C — Regenerate (--regen-hardware or fresh install)

```bash
nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix
cp /tmp/hardware-configuration.nix /etc/nixos/hosts/default/hardware-configuration.nix
pass "Generated fresh hardware-configuration.nix"
```

#### §8.D — Existing is Template (auto-regenerate)

The backed-up `/etc/nixos.bak-*/hardware-configuration.nix` contains the template sentinel.
Log a `[WARN]`:

```
[WARN] Existing hardware-configuration.nix appears to be the repo template.
       Generating fresh hardware config with nixos-generate-config...
```

Then proceed as §8.C.

#### §8.E — Existing Looks Real (interactive prompt, unless --yes)

The backed-up hardware config does NOT contain the template sentinel — it appears
to be a real machine-generated config.

If `--yes` is set: default to **keep** (safest non-destructive default).

Otherwise, prompt:

```
[INFO] Existing hardware-configuration.nix appears to be real (machine-generated).
  [k] Keep existing (default, safest)
  [r] Regenerate with nixos-generate-config
Choice [K/r]:
```

- `k` / `K` / Enter → §8.B (restore from backup)
- `r` / `R` → §8.C (regenerate)

### Step 9 — Set Ownership and Permissions

```bash
chown -R root:root /etc/nixos
find /etc/nixos -type d -exec chmod 755 {} \;
find /etc/nixos -type f -exec chmod 644 {} \;
# Restore execute bit on scripts
find /etc/nixos/scripts -type f -name "*.sh" -exec chmod 755 {} \;
```

### Step 10 — Run `nixos-rebuild switch`

```bash
nixos-rebuild switch --flake /etc/nixos#vexos
```

On failure:
- Print `[FAIL] nixos-rebuild switch failed.`
- Print `[WARN] Your previous /etc/nixos/ configuration is backed up at: $BACKUP_DIR`
- `exit 1`

On success:
- Print `[PASS] nixos-rebuild switch completed successfully.`

**Dry-run:** Print the command without running it; note the current config is unchanged.

### Step 11 — Final Result

Mirror preflight.sh's coloured banner pattern:

**On success:**
```
=========================================
  DEPLOY PASSED — system is up to date
=========================================
```

**On failure:**
```
=========================================
  DEPLOY FAILED — X error(s)
  Backup: /etc/nixos.bak-<timestamp>/
=========================================
```

---

## 5. Error Handling Strategy

### Global Error Trap

Installed immediately after `set -euo pipefail`:

```bash
BACKUP_DIR=""   # populated by Step 6; referenced by trap

cleanup_on_error() {
    local exit_code=$?
    local line_no=$1
    echo ""
    fail "Unexpected error (exit $exit_code) at line $line_no"
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        warn "Previous /etc/nixos/ is preserved at: $BACKUP_DIR"
        warn "To restore: sudo rm -rf /etc/nixos && sudo cp -a $BACKUP_DIR /etc/nixos"
    fi
    exit 1
}

trap 'cleanup_on_error $LINENO' ERR
```

### Step-level Error Handling

Each step uses an explicit `|| { fail "..."; ERRORS=$((ERRORS+1)); }` style rather
than relying on `set -e` alone where the error is actionable/recoverable.

Steps that are non-recoverable (backup, nixos-rebuild) call `exit 1` directly after
printing the failure message.

### Dry-run Safety

In dry-run mode, all mutations are replaced with `echo "[DRY-RUN] would: <command>"`.
The `trap` is still active but `ERRORS` tracks skipped vs. failed.

---

## 6. Hardware Config Detection Accuracy

The sentinel string used to detect the repo template:

```
# This is a template hardware configuration.
```

This exact string appears on line 1 of the current `hosts/default/hardware-configuration.nix`.
It will NOT appear in any file generated by `nixos-generate-config`, making it a
reliable discriminator.

---

## 7. Full Flag Behaviour Table

| Flag | `BACKUP_DIR` | Copy files | HW Config | nixos-rebuild |
|---|---|---|---|---|
| *(none)* | Created | Yes | Prompt or auto | Yes |
| `--yes` | Created | Yes | Auto (keep if real, regen if template) | Yes |
| `--regen-hardware` | Created | Yes | Always regenerate | Yes |
| `--keep-hardware` | Created | Yes | Always keep from backup | Yes |
| `--dry-run` | Not created | Printed | Printed | Printed |
| `--help` | N/A | N/A | N/A | N/A |

---

## 8. Example Usage

```bash
# Full interactive deploy
sudo bash scripts/deploy.sh

# Non-interactive (CI/automated) deploy, keep existing hardware config
sudo bash scripts/deploy.sh --yes --keep-hardware

# Force fresh hardware detection (new hardware added)
sudo bash scripts/deploy.sh --yes --regen-hardware

# Preview without making any changes
bash scripts/deploy.sh --dry-run

# Help
bash scripts/deploy.sh --help
```

---

## 9. Implementation Checklist

- [ ] `#!/usr/bin/env bash` + `set -euo pipefail`
- [ ] Colour variables matching `preflight.sh` exactly (`RED`, `GREEN`, `YELLOW`, `NC`)
- [ ] `pass()`, `fail()`, `warn()`, `info()` functions matching `preflight.sh` signature
- [ ] `[PASS]` / `[FAIL]` / `[WARN]` prefix format
- [ ] `==> Step N:` section headers
- [ ] `ERRORS` accumulator
- [ ] `BACKUP_DIR` global variable set before any mutations
- [ ] `trap 'cleanup_on_error $LINENO' ERR`
- [ ] Flag parsing loop (no `getopts` — plain `while [[ $# -gt 0 ]]` for readability)
- [ ] Mutual exclusion check for `--regen-hardware` + `--keep-hardware`
- [ ] `--help` usage block
- [ ] Root check (EUID == 0), with dry-run exemption
- [ ] Dependency check (rsync, nixos-generate-config, nixos-rebuild)
- [ ] rsync with `--delete` and `--exclude` for `.git/` and `.github/`
- [ ] `cp -a` fallback if rsync missing
- [ ] `is_template_hardware_config()` function using sentinel grep
- [ ] Hardware config decision tree faithfully implemented
- [ ] `chown -R root:root /etc/nixos` + permission normalization
- [ ] `nixos-rebuild switch --flake /etc/nixos#vexos`
- [ ] Backup path printed on failure
- [ ] Final coloured banner block
- [ ] `chmod +x` on the script itself (noted in README update)

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Partial copy leaves `/etc/nixos/` in broken state | Backup is a full `cp -a` before mutation begins; trap restores path |
| Wrong hardware config causes boot failure | Default interactive path favours keeping existing; `--keep-hardware` available |
| `nixos-rebuild` fails mid-switch | Nix is transactional; current boot entry untouched; backup available for manual restore |
| Running on non-NixOS system | `nixos-rebuild` not found → Step 4 dependency check fails early |
| Flake lock drift | Script deploys the repo as-is including `flake.lock`; user should run `nix flake update` separately if desired |
| `/etc/nixos/` path owned by wrong user after copy | Step 9 normalizes ownership and permissions unconditionally |
| Template hardware config deployed to production | Sentinel detection + regeneration path prevents this |

---

## 11. Files to Create / Modify

| File | Action |
|---|---|
| `scripts/deploy.sh` | **CREATE** — full script per this spec |
| `README.md` | **UPDATE** — add "Automated Deployment" section referencing `scripts/deploy.sh` |
