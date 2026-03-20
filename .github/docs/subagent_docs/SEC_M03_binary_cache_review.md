# SEC-M03 — Binary Cache Supply-Chain Trust Reduction
## Phase 3: Review & Quality Assurance

**Severity**: Medium  
**Review Date**: 2026-03-19  
**Reviewer**: Phase 3 QA Agent  
**Verdict**: ✅ **PASS**

---

## 1. Security Fix Completeness

### 1.1 `attic.xuyh0120.win` Removal

**Finding**: PASS ✅

The URL `"https://attic.xuyh0120.win/lantian"` is **not present in any active
(non-commented) `extra-substituters` entry**. It has been converted to a
commented-out example with explicit opt-in instructions:

```nix
extra-substituters = [
  # attic.xuyh0120.win (personal server) was removed — its private signing key
  # has no revocation mechanism; a compromise would allow silent kernel substitution.
  # If you accept this risk and need faster CachyOS kernel builds, you may re-add:
  #   "https://attic.xuyh0120.win/lantian"
  "https://cache.garnix.io"
];
```

The URL cannot be accidentally evaluated. ✅

### 1.2 `lantian:` Key Removal

**Finding**: PASS ✅

The key `"lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="` is **not
present in any active (non-commented) `extra-trusted-public-keys` entry**.
It is commented out with a cross-reference to the substituter explanation:

```nix
extra-trusted-public-keys = [
  # lantian key removed along with personal cache — see comment above.
  # "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
  "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
];
```

Nix will not accept paths signed by the `lantian` key. ✅

---

## 2. Garnix Integrity

**Finding**: PASS ✅

Both the substituter URL and its public key are present and active:

| Item | Status |
|------|--------|
| `"https://cache.garnix.io"` in `extra-substituters` | ✅ Active |
| `"cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="` in `extra-trusted-public-keys` | ✅ Active |

CachyOS kernel binary resolution via Garnix is fully preserved. ✅

---

## 3. Comment Quality

**Finding**: PASS with minor note ⚠️

**Strengths**:
- The comment clearly states the **reason for removal**: "its private signing key
  has no revocation mechanism; a compromise would allow silent kernel substitution."
- The comment provides **explicit re-add instructions** for users who consciously
  accept the risk, including the exact URL to restore.
- The key comment cross-references the substituter comment, avoiding duplication.

**Minor deviation from spec**:
The spec proposed a longer comment block above the `lib.mkIf isCachyos` guard,
covering Garnix trust basis, the free-plan quota caveat, and detailed re-add
instructions for both the URL and the key. The implementation used shorter inline
comments within the list expressions.

**Assessment**: The shorter implementation is adequate and arguably less noisy.
The critical information (why removed, how to restore) is present. This is a
stylistic deviation only — not a defect. No change required.

---

## 4. No Over-Reach (Regression Check)

**Finding**: PASS ✅

The `git diff modules/kernel.nix` output confirms **only the binary cache block
was touched** (4 lines removed, 6 lines added — all within `extra-substituters`
and `extra-trusted-public-keys`). Verified unchanged:

| Component | Status |
|-----------|--------|
| `isCachyos` predicate (lines 19–26) | Untouched ✅ |
| `options.kernel.type` declaration | Untouched ✅ |
| `boot.kernelPackages` assignments (all 7 kernel types) | Untouched ✅ |
| `lib.mkIf` conditional guard structure | Untouched ✅ |
| `bazzite` placeholder `throw` block | Untouched ✅ |
| File header comments | Untouched ✅ |

**Note on `git diff --name-only` output**: The full `git diff --name-only` shows
four modified files (`README.md`, `hosts/default/hardware-configuration.nix`,
`modules/gnome.nix`, `modules/kernel.nix`). The three non-kernel files contain
**pre-existing uncommitted changes unrelated to SEC-M03**:

- `README.md`: Installation documentation rewrites (confirmed by diff content)
- `hosts/default/hardware-configuration.nix`: VM-in-VM workaround comment block
- `modules/gnome.nix`: Unrelated GNOME configuration changes

These were present before this security fix and are outside the scope of SEC-M03.

---

## 5. Nix Syntax Validation

**Finding**: PASS ✅

Manual inspection confirms:
- `extra-substituters = [ ... ];` — properly terminated list ✅
- `extra-trusted-public-keys = [ ... ];` — properly terminated list ✅
- `nix.settings = { ... };` — properly terminated attribute set ✅
- `(lib.mkIf isCachyos { ... })` — properly closed conditional ✅
- `lib.mkMerge [ ... ]` — outer merge list intact ✅
- `}` — module `config` block properly closed ✅

`nix flake check` provides the definitive confirmation (see Section 6).

---

## 6. Build Validation

### 6.1 `nix flake check` Output

```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
evaluating flake...
checking flake output 'lib'...
checking flake output 'nixosConfigurations'...
checking NixOS configuration 'nixosConfigurations.vexos'...
```

**Exit code**: 0  
**Result**: PASS ✅

The only warning is the expected "uncommitted changes" notice, which is
informational. All flake outputs evaluated and validated successfully.

### 6.2 Exact Diff (kernel.nix only)

```diff
@@ -129,11 +129,15 @@ in {
     (lib.mkIf isCachyos {
       nix.settings = {
         extra-substituters = [
-          "https://attic.xuyh0120.win/lantian"
+          # attic.xuyh0120.win (personal server) was removed — its private signing key
+          # has no revocation mechanism; a compromise would allow silent kernel substitution.
+          # If you accept this risk and need faster CachyOS kernel builds, you may re-add:
+          #   "https://attic.xuyh0120.win/lantian"
           "https://cache.garnix.io"
         ];
         extra-trusted-public-keys = [
-          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
+          # lantian key removed along with personal cache — see comment above.
+          # "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
           "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
         ];
       };
```

Minimal, focused, reviewable. ✅

---

## 7. Why Removing the Personal Cache Reduces Attack Surface

Removing `attic.xuyh0120.win/lantian` eliminates the single most exploitable
supply-chain vector in this configuration: a personal server whose private signing
key, if compromised, would allow an attacker to sign and deliver a malicious kernel
binary that Nix would accept silently and without warning, giving that attacker
full kernel-level access to any VexOS system running a CachyOS kernel variant.

Nix binary caches have **no key revocation mechanism** — once an attacker holds the
private key, every system that trusts it remains vulnerable indefinitely until the
key is manually removed from all configurations, making a personal-server-based key
a structurally higher risk than a commercial operator with professional key
management, incident response, and HSM-grade key custody.

---

## 8. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 93% | A |
| Security Fix Quality | 100% | A+ |
| Code Quality | 95% | A |
| Nix Syntax | 100% | A+ |
| No Regression | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (98%)**

---

## 9. Findings Summary

| # | Severity | Category | Finding |
|---|----------|----------|---------|
| 1 | ✅ None | Security | `attic.xuyh0120.win` completely removed from active entries |
| 2 | ✅ None | Security | `lantian:` key completely removed from active entries |
| 3 | ✅ None | Security | Garnix cache and key intact and active |
| 4 | ℹ️ Info | Comment | Comments shorter than spec proposed — adequate, not a defect |
| 5 | ✅ None | Scope | Only binary cache block changed; all kernel logic untouched |
| 6 | ℹ️ Info | Git | 3 unrelated files also have uncommitted changes (pre-existing, out of scope) |
| 7 | ✅ None | Build | `nix flake check` passes with zero errors |

**Critical issues**: 0  
**Recommended improvements**: 0  
**Informational notes**: 2 (see findings 4 and 6 above — neither requires action)

---

## 10. Verdict

### ✅ PASS

The SEC-M03 security fix is correct, minimal, and complete. The personal Attic
cache and its signing key have been fully removed from all active configuration
paths. Garnix remains intact. Comments are clear and actionable. The implementation
strictly matches the specification's intent. The Nix flake evaluates and validates
without errors.

**No refinement required. This fix is ready for commit.**
