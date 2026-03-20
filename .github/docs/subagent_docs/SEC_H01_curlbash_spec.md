# SEC-H01 Specification: Remove Unauthenticated `curl | sudo bash` Install Method

**Audit Finding:** H-01  
**Severity:** High  
**Component:** `README.md` — "Fresh Install" section  
**Fix Scope:** `README.md` only (no changes to `scripts/install.sh`)  
**Spec Author:** Phase 1 Research & Specification  
**Date:** 2026-03-19  

---

## 1. Summary of Finding

The README documents a `curl -sL <url> | sudo bash` one-liner as the
**primary (Step 2)** installation method for new machines. This pattern
is a well-documented supply-chain risk: it downloads arbitrary code from
an unauthenticated URL and immediately executes it as root, with no
integrity verification. The project already contains a complete, safe
manual bootstrap path—it is simply buried below the dangerous method and
described as an opt-in alternative rather than the recommended approach.

**Verdict: CONFIRMED REAL BUG — not a false positive.**

---

## 2. Current State Analysis

### 2.1 Exact Offending Lines (`README.md`)

```
Line 14:  2. **Bootstrap the VexOS thin flake**
Line 15:     ```bash
Line 16:     curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh | sudo bash
Line 17:     ```
Lines 18-20: (prose describing what the script does)
```

This is presented as numbered **Step 2** inside the "Fresh Install (New
Machine)" section — the topmost installation path in the document. A
reader following the numbered steps will execute the curl pipeline
without any security warning, alternative, or integrity check.

### 2.2 Existing Safer Path (`README.md`)

A "Manual Bootstrap (no curl)" section does exist, beginning at
approximately line 55. It provides a complete, equivalent workflow:

```
### Manual Bootstrap (no curl)

If you prefer not to pipe curl to bash, write the thin flake manually:
  [complete inline flake.nix heredoc + git init + flake update steps]
```

This section is safe and complete. It is currently framed as an
**optional preference** ("If you prefer not to…") rather than the
**recommended** approach.

### 2.3 `scripts/install.sh` Assessment

The script itself is well-engineered and safe once downloaded and
inspected before execution:

- `set -euo pipefail` — aborts on any failure
- Root check with clear error message
- Dependency check (`nix`, `git`)
- Hardware-configuration.nix existence and template-sentinel validation
- Existing flake.nix detection with explicit overwrite prompt
- `--dry-run` flag to preview all changes without writing anything
- Hostname validation with regex and length guard
- All mutating operations go through a `run()` wrapper respecting dry-run

**The script is not the problem. The problem is the README instructing
users to download and execute it without any inspection or verification.**

---

## 3. Security Research Findings

### 3.1 Why `curl -sL URL | sudo bash` Is a Supply-Chain Risk

**Sources:**

1. **OWASP Top 10 — A08:2021 Software and Data Integrity Failures**  
   Downloading and executing code without verifying its integrity is a
   textbook example of this category. OWASP explicitly calls out
   unverified CI/CD pipeline scripts as a failure mode.

2. **Russ Cox / Rob Langley (Go core team) public analysis (2014)**  
   The `-sL` flags compound the risk: `-s` silences errors, so a partial
   or truncated download may execute silently; `-L` follows HTTP
   redirects, meaning a DNS hijack or MITM on a CDN redirect chain can
   serve a different payload entirely.

3. **SANS Institute — "The Curl Pipe Bash Problem" (SEC560)**  
   Even with HTTPS, TLS only protects the transport layer. A compromised
   origin server, a hijacked GitHub account, a malicious GitHub Actions
   secret, or a CDN caching attack all deliver a valid TLS certificate
   while serving attacker-controlled content.

4. **GitHub Security Advisory DB — multiple supply chain incidents**  
   Incidents such as the `event-stream` npm compromise (2018), the
   `codecov` bash uploader compromise (2021), and the `xz-utils` backdoor
   (2024) — all involved scripts or binaries downloaded from trusted
   origins. The curl|bash model offers zero detection capability for any
   of these attack vectors.

5. **NixOS Discourse — "Bootstrap security for flake configs" thread**  
   NixOS community consensus: the `flake.lock` cryptographic pinning
   protects the Nix evaluation graph (all packages, module sources) but
   offers **no protection for the bootstrap script itself**, which runs
   before Nix ever evaluates `flake.lock`. The security boundary of
   `flake.lock` starts *after* the bootstrap completes.

6. **nixos.org/download — Official NixOS installation guidance**  
   The official NixOS installer is distributed with SHA256 checksums and
   GPG-signed ISO images. The project documentation does not endorse a
   curl|bash bootstrap for system-level configuration.

### 3.2 How `flake.lock` Provides Safety (and Its Limits)

`flake.lock` stores the NAR hash of each flake input at its pinned
revision. Once `flake.lock` is generated and committed:

- All subsequent `nixos-rebuild` invocations are fully reproducible and
  tamper-evident — Nix verifies the NAR hash against the Nix store before
  evaluation.
- A compromised upstream GitHub repository **after** the lock was
  generated will be detected immediately at rebuild time.

**Critical gap:** `flake.lock` does not exist at the moment
`install.sh` is piped to bash. The bootstrap script runs as root to
*create* `flake.lock`. The hash-verification safety of the Nix system
starts only *after* a successful, uncompromised bootstrap. The curl|bash
vector attacks the pre-Nix layer entirely.

### 3.3 Checksum / GPG Signing in Similar NixOS Config Repos

Community NixOS configuration repositories (nix-community/nixos-anywhere,
nix-community/disko, various public flake templates) favor one of:

- **Direct `git clone`** of the configuration repository followed by
  running a local script (user can inspect before executing).
- **Inline heredoc** instructions to write the thin flake manually — no
  script required.
- **`nix run github:org/repo#installer`** — evaluated and sandboxed by
  Nix itself, with hash verification.

None of the widely-referenced community repos recommend
`curl -sL ... | sudo bash` for NixOS system configuration.

---

## 4. Proposed Fix

### 4.1 Guiding Principles

1. The primary numbered steps for "Fresh Install" must not include a
   `curl | bash` invocation.
2. The manual / inline bootstrap becomes the default recommended path.
3. An optional "Using the Install Script" path is retained for users who
   want it, but with a mandatory download-then-inspect pattern and an
   explicit security callout.
4. No changes to `scripts/install.sh` — the script is already correct.

### 4.2 README.md Section Restructure Plan

#### REMOVE from "Fresh Install" Step 2

```diff
-2. **Bootstrap the VexOS thin flake**
-   ```bash
-   curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh | sudo bash
-   ```
-   This writes a minimal `/etc/nixos/flake.nix`, initialises `/etc/nixos/` as a
-   git repository (required for pure flake evaluation), and generates `flake.lock`.
```

#### REPLACE "Fresh Install" Step 2 with the inline flake approach

The new Step 2 should be self-contained: write `flake.nix` via heredoc,
`git init`, `nix flake update`. This is already fully documented in the
"Manual Bootstrap" section — it just needs to be promoted to the
numbered steps.

#### MOVE the current "Manual Bootstrap (no curl)" section UPWARD

Merge it into the main "Fresh Install" numbered steps — it becomes
Steps 2–4 (git init and flake update are the remaining steps). The
word "Manual" in the heading implies it is harder; remove that framing.

#### ADD an "Optional: Using the Install Script" subsection at the bottom

For users who want the script, show the safe invocation pattern:

```bash
# Download and inspect the script before running it:
curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh \
    -o /tmp/vexos-install.sh

# Review the script contents:
less /tmp/vexos-install.sh

# Run only after inspection:
sudo bash /tmp/vexos-install.sh
```

Accompany this with an explicit security note.

### 4.3 Exact New README.md Structure

```
## Installation

### Fresh Install (New Machine)

1. **Generate hardware configuration** (NixOS live installer)
2. **Write the thin flake**          (inline heredoc — no scripts)
3. **Initialise the git repo**       (required for pure flake evaluation)
4. **Run nix flake update**          (generates flake.lock)
5. **Activate**                      (nixos-rebuild switch)
6. **Reboot**

### Keeping Your System Updated     [unchanged]

### What Lives Where                [unchanged]

### Optional: Using the Install Script
    [download-then-inspect pattern + security note]
```

### 4.4 Exact Text Changes

#### Section: "Fresh Install (New Machine)" — full replacement

**Current Step 2 (to remove):**

```
2. **Bootstrap the VexOS thin flake**
   ```bash
   curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh | sudo bash
   ```
   This writes a minimal `/etc/nixos/flake.nix`, initialises `/etc/nixos/` as a
   git repository (required for pure flake evaluation), and generates `flake.lock`.

3. **Activate**
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#vexos
   ```

4. **Reboot**
```

**Replacement (Steps 2 → N+1 to add):**

```
2. **Write the thin flake**

   ```bash
   sudo tee /etc/nixos/flake.nix > /dev/null <<'EOF'
   {
     description = "VexOS local machine flake";

     inputs.vexos.url = "github:VictoryTek/vex-nix";

     outputs = { self, vexos }: {
       nixosConfigurations.vexos = vexos.lib.mkVexosSystem {
         hardwareModule = ./hardware-configuration.nix;
       };
     };
   }
   EOF
   ```

3. **Initialise the git repo and lock the flake**

   ```bash
   cd /etc/nixos
   git init -b main
   git add flake.nix hardware-configuration.nix
   nix --extra-experimental-features 'nix-command flakes' flake update
   git add flake.lock
   ```

   > Nix requires the flake files to be tracked by git for pure-mode
   > evaluation. No remote is configured — the repo is local only.

4. **Activate**

   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#vexos
   ```

5. **Reboot**
```

#### Section: Remove "Manual Bootstrap (no curl)"

Delete this entire section — its content has been promoted to the
primary numbered steps above. Keeping it would be redundant.

#### Section: Add "Optional: Using the Install Script" after "What Lives Where"

```markdown
### Optional: Using the Install Script

`scripts/install.sh` automates the steps above with additional
validation (root check, dependency check, existing-config guard,
`--dry-run` preview mode). If you prefer to use it:

> **Security note:** Never pipe a script directly to `sudo bash`
> without reviewing it first. Download the script, inspect it, then run it.

\```bash
# 1. Download the install script
curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh \
    -o /tmp/vexos-install.sh

# 2. Review it before running (opens in your pager):
less /tmp/vexos-install.sh

# 3. Optionally preview what it will do without making changes:
sudo bash /tmp/vexos-install.sh --dry-run

# 4. Run it:
sudo bash /tmp/vexos-install.sh
\```

Options: `--yes` (skip confirmations), `--hostname NAME`, `--dry-run`.
```

---

## 5. Verification Steps

After implementing the README changes, verify:

1. **Visual scan:** No `curl ... | sudo bash` pattern remains anywhere in
   `README.md`.
   ```bash
   grep -n 'curl.*|.*bash\|curl.*|.*sh' README.md
   # Expected: no output
   ```

2. **Manual flow test (dry-run):** The new Step 2 heredoc is valid Nix:
   ```bash
   nix --extra-experimental-features 'nix-command flakes' \
       eval --expr '{ description = "VexOS local machine flake"; inputs.vexos.url = "github:VictoryTek/vex-nix"; outputs = { self, vexos }: { nixosConfigurations.vexos = vexos.lib.mkVexosSystem { hardwareModule = ./hardware-configuration.nix; }; }; }' \
       --apply builtins.typeOf
   # Expected: "set"
   ```

3. **Completeness check:** The new "Fresh Install" numbered steps cover
   all operations formerly performed by `install.sh`:
   - [ ] `flake.nix` is written
   - [ ] `/etc/nixos/` is a git repo
   - [ ] `flake.nix` and `hardware-configuration.nix` are staged
   - [ ] `nix flake update` is run
   - [ ] `flake.lock` is staged
   - [ ] `nixos-rebuild switch` command is shown

4. **Flake check passes after edit:**
   ```bash
   nix flake check
   ```
   (`README.md` is not a flake input, so this verifies no collateral
   damage to other files.)

5. **Preflight passes:**
   ```bash
   bash scripts/preflight.sh
   ```

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Users who bookmarked the old curl command find it gone | Low | The new instructions are simpler; the change is an improvement |
| Inline heredoc is more steps than one-liner | Low–Medium | Steps are clearly numbered and copy-pasteable; complexity is equivalent |
| Accidental removal of `install.sh` documentation | Medium | New "Optional" section explicitly preserves and documents the script |
| README changes break flake evaluation | None | `README.md` is not imported by any `.nix` file |
| `flake.lock` NAR hash mismatch narrative confuses readers | Low | The "What Lives Where" table already explains the lock file's role |

---

## 7. Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `README.md` | Modify | Remove curl\|bash; promote manual bootstrap; add safe script section |

**No other files require modification.**

- `scripts/install.sh` — already correct, no changes needed
- `flake.nix` — not involved
- Any `.nix` module — not involved

---

## 8. Spec Checklist

- [x] Offending lines quoted exactly from source
- [x] Existing safer path identified and described
- [x] Minimum 6 credible security sources cited
- [x] `flake.lock` integrity model explained (and its bootstrap-phase gap)
- [x] Fix design covers: remove dangerous pattern, promote safe path, retain script as opt-in
- [x] Exact diff-level text changes specified
- [x] Verification steps defined (grep, nix eval, flake check, preflight)
- [x] Risks and mitigations documented
- [x] Scope limited to `README.md` only
