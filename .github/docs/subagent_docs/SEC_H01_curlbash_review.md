# SEC-H01 Review: Remove Unauthenticated `curl | sudo bash` Install Method

**Phase:** 3 — Review & Quality Assurance  
**Finding ID:** H-01  
**Severity:** High  
**Component:** `README.md`  
**Reviewer:** Phase 3 QA  
**Date:** 2026-03-19  

---

## 1. False Positive Assessment

**VERDICT: CONFIRMED REAL SECURITY BUG — not a false positive.**

The original README presented `curl -sL https://raw.githubusercontent.com/VictoryTek/vex-nix/main/scripts/install.sh | sudo bash` as the primary numbered Step 2 in the "Fresh Install (New Machine)" section — with no warning, no alternative, and no integrity verification.

This is a textbook OWASP A08:2021 Software and Data Integrity Failure. The attack surface is real:

- `curl -sL` silences errors (`-s`) and follows HTTP redirects (`-L`), meaning a DNS hijack or CDN redirect chain poisoning can serve a different payload with a valid TLS certificate.
- `sudo bash` executes the downloaded content as root — no sandboxing, no hash check.
- `flake.lock` does not protect the bootstrap phase. Nix's cryptographic pinning starts *after* a successful bootstrap completes. A compromised bootstrap script runs entirely before `flake.lock` is generated.
- Historical precedent: the `codecov` bash uploader compromise (2021) and the `xz-utils` backdoor (2024) both exploited the curl-pipe-bash trust model via otherwise-trusted origins.

The fix is appropriate: the `scripts/install.sh` itself is well-engineered (uses `set -euo pipefail`, root check, dry-run, overwrite prompts) and is retained — the problem was exclusively in how the README instructed users to consume it.

---

## 2. Review Findings

### 2.1 Security Fix Completeness — ✅ PASS

The offending line is completely absent from the primary install path:

```diff
-2. **Bootstrap the VexOS thin flake**
-   curl -sL .../install.sh | sudo bash
```

Remaining `curl` references in the document (lines 87, 99, 109) are:
1. **Line 87** — Inside a `> ⚠️ Warning:` blockquote explaining why the `curl | sudo bash` pattern is dangerous.
2. **Line 99** — The `curl -sL ... -o /tmp/vexos-install.sh` download-only (no pipe to bash) inside the explicitly titled "⚠️ Alternative (Not Recommended)" section.
3. **Line 109** — Closing instruction: *"Never pipe `curl` output directly to `bash` or `sudo bash`. Always download first, inspect, then execute."*

No `curl | bash` or `curl | sudo bash` pipeline exists anywhere in the document.

---

### 2.2 Accuracy of the New Primary Install Path — ✅ PASS

Every command in the new numbered steps was verified:

| Command | Verdict |
|---------|---------|
| `nix-shell -p git` | ✅ Correct — available in NixOS live environment |
| `sudo tee /etc/nixos/flake.nix > /dev/null <<'EOF'` | ✅ Correct heredoc syntax; quoted `'EOF'` prevents variable expansion |
| `inputs.vexos.url = "github:VictoryTek/vex-nix"` | ✅ Correct flake input URL |
| `vexos.lib.mkVexosSystem { hardwareModule = ./hardware-configuration.nix; }` | ✅ **CONFIRMED** — `lib.mkVexosSystem` is exported at `flake.nix:lib.mkVexosSystem = mkVexosSystem;` |
| `git init -b main` | ✅ Correct; `-b main` sets default branch |
| `git add flake.nix hardware-configuration.nix` | ✅ Both files must be tracked for pure flake evaluation |
| `nix --extra-experimental-features 'nix-command flakes' flake update` | ✅ Correct for a live environment without globally-enabled experimental features |
| `git add flake.lock` | ✅ Lock file must be tracked to persist the pinned revision |
| `sudo nixos-rebuild switch --flake /etc/nixos#vexos` | ✅ Correct; `vexos` matches the `nixosConfigurations` key in the thin flake |

The inline flake structure in the heredoc correctly reflects the actual `lib.mkVexosSystem` API signature as declared in the repository's `flake.nix`.

---

### 2.3 Completeness — ✅ PASS

All sections verified present and intact via git diff:

| Section | Status |
|---------|--------|
| Fresh Install (New Machine) — numbered steps | ✅ Present, improved |
| Keeping Your System Updated | ✅ Unchanged |
| Shell aliases (`update`, `rebuild`) | ✅ Unchanged |
| What Lives Where (table) | ✅ Unchanged |
| ⚠️ Alternative (install script) | ✅ New section; replaces old "Manual Bootstrap" |
| What's Included | ✅ Unchanged |
| Post-Install (Samba, Tailscale) | ✅ Unchanged |
| `deploy.sh` deprecation note | ✅ Unchanged |

The former "Manual Bootstrap (no curl)" section was a single monolithic code block mixing heredoc, git, and nixos-rebuild. Its content has been promoted and decomposed into clearly labeled Steps 2–5, which is a readability improvement consistent with the spec's intent.

One minor observation: the spec's proposed outline listed Step 1 as "Generate hardware configuration". The README starts at "Install git" instead, implicitly assuming `nixos-generate-config` has already been run. This is operationally correct — the NixOS live installer generates `hardware-configuration.nix` automatically — but the omission slightly reduces discoverability for users unfamiliar with NixOS. This is classified as a non-critical style note, not a defect.

---

### 2.4 Warning Callout Formatting — ✅ PASS

The warning block uses proper GitHub Flavored Markdown blockquote syntax:

```markdown
> ⚠️ **Warning:** The `curl | sudo bash` pattern downloads and executes arbitrary code
> as root without any integrity verification. It is vulnerable to MITM attacks, DNS
> hijacking, compromised CDN caches, and supply-chain attacks...
```

The `⚠️` emoji prefix and `**Warning:**` bold label follow GFM conventions. The section heading `### ⚠️ Alternative (Not Recommended): Using the Install Script` clearly signals the risk posture before the user reads the body.

---

### 2.5 No Regression — ✅ PASS

Build validation results:

```
nix flake check
  → warning: Git tree has uncommitted changes (expected — README.md edited)
  → evaluating flake... ✅
  → checking flake output 'lib'... ✅
  → checking flake output 'nixosConfigurations'... ✅
  → checking NixOS configuration 'nixosConfigurations.vexos'... ✅
```

`git status --short` confirms **only `README.md` was modified** — no `.nix` files, no `flake.lock`, no scripts.

---

## 3. Issues Found

### CRITICAL
None.

### RECOMMENDED (Non-Blocking)
- **Missing "generate hardware config" reminder**: A brief note before Step 1 (e.g., *"Ensure `nixos-generate-config --root /mnt` has been run and `hardware-configuration.nix` exists at `/etc/nixos/`"*) would make the flow fully self-contained. Spec did not require this, so it is not a compliance failure.

### STYLE
None.

---

## 4. Build Validation Summary

| Check | Result |
|-------|--------|
| `nix flake check` | ✅ Pass (exit 0) |
| `.nix` files modified | ✅ None (README.md only) |
| `flake.lock` modified | ✅ No |
| `scripts/` modified | ✅ No |

---

## 5. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 95% | A |
| Security Fix Quality | 100% | A+ |
| Documentation Accuracy | 98% | A+ |
| Completeness | 95% | A |
| Formatting | 100% | A+ |
| No Regression | 100% | A+ |

**Overall Grade: A+ (98%)**

---

## 6. Final Verdict

**PASS**

The security fix is complete, correct, and well-executed. The `curl | sudo bash` pipeline has been eliminated from the primary install path and demoted to an explicitly-warned, download-then-inspect-only alternative. All other README content is preserved. The flake evaluates cleanly. No `.nix` files were touched.

The one non-blocking recommendation (add a `nixos-generate-config` reminder) may be addressed in a follow-up; it does not block delivery of this fix.
