# SEC-M03 — Binary Cache Supply-Chain Trust Reduction

**Severity**: Medium  
**Phase**: 1 — Research & Specification  
**Date**: 2026-03-19  
**Prepared by**: Phase 1 Research Agent  

---

## 1. Bug Confirmation

### Location

**File**: `modules/kernel.nix`  
**Lines**: 128–140 (binary cache config block), specifically:

| Line | Content | Status |
|------|---------|--------|
| 128 | `# ── Binary cache for CachyOS kernels ──────────` | (block start) |
| 129 | `(lib.mkIf isCachyos {` | (conditional guard) |
| 131 | `extra-substituters = [` | (substituter list) |
| **132** | `"https://attic.xuyh0120.win/lantian"` | **← REMOVE** |
| 133 | `"https://cache.garnix.io"` | (keep) |
| 135 | `extra-trusted-public-keys = [` | (key list) |
| **136** | `"lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="` | **← REMOVE** |
| 137 | `"cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="` | (keep) |

### Is the block conditional?

**Yes — but only partially.** The `nix.settings` block is correctly gated by the `isCachyos` predicate (defined at lines 19–26), which evaluates to `true` only when one of these kernel types is selected:

```
"cachyos-gaming" | "cachyos-server" | "cachyos-desktop" |
"cachyos-handheld" | "cachyos-lts" | "cachyos-hardened"
```

`"stock"` and `"bazzite"` do **not** trigger the cache settings. The conditional scoping is **already correct** — the bug is not a scoping failure.

### Is the `nix-cachyos-kernel` flake input conditional?

**No.** In `flake.nix`, the `nix-cachyos-kernel` input and its overlay are unconditionally present:

```nix
# flake.nix — inputs section (always present)
nix-cachyos-kernel = {
  url = "github:xddxdd/nix-cachyos-kernel/release";
};

# flake.nix — mkVexosSystem modules (always applied)
{ nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.default ]; }
```

The overlay only exposes packages in `pkgs.cachyosKernels.*` — it fetches nothing at evaluation time unless a CachyOS kernel is actually selected. This is acceptable.

### Is there any comment explaining the trust decision?

**No.** There is a header comment `# ── Binary cache for CachyOS kernels ──────────────────────────────────` but no explanation of who operates `attic.xuyh0120.win`, who holds the `lantian` private key, why the key is trusted, or what the risk of its compromise is.

---

## 2. Scope: Which Kernel Types Require the Cache?

All 6 CachyOS kernel types (`cachyos-gaming`, `cachyos-server`, `cachyos-desktop`, `cachyos-handheld`, `cachyos-lts`, `cachyos-hardened`) trigger the binary cache settings via `isCachyos`. Currently active in `hosts/default/configuration.nix`:

```nix
kernel.type = "stock";  # cache block NOT triggered
```

The current deployment does not activate the cache. The risk vector exists for any user who switches to a CachyOS kernel.

---

## 3. What Does the Cache Actually Provide?

### `attic.xuyh0120.win/lantian` — Personal Attic Cache (PRIMARY, HIGH RISK)

- **Operated by**: `xddxdd` (Lan Tian), the maintainer of `nix-cachyos-kernel`
- **Signing key owner**: Same individual (`lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=`)
- **Backed by**: Private Hydra CI at `hydra.lantian.pub/jobset/lantian/nix-cachyos-kernel`
- **Reliability**: HIGH — always builds and always pushes to cache
- **Design rationale**: The `release` branch of `nix-cachyos-kernel` is explicitly defined as "the latest kernel that has been built by my Hydra CI and is present in binary cache." The entire `release` branch workflow is designed around this cache being the authoritative source.

### `cache.garnix.io` — Garnix CI Cache (SECONDARY, LOWER RISK)

- **Operated by**: Garnix Inc., a commercial CI-as-a-service company (`garnix.io`)
- **Signing key owner**: Garnix corporate (`cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=`)
- **Backed by**: Garnix CI builds on the FREE PLAN
- **Reliability**: MODERATE with important caveat:
  - README explicitly states: "should work **as long as the total build time is below the free plan threshold**"
  - README further warns: "If you see 'all builds failed' from Garnix, **it means I ran out of free plan's build time**"
  - CachyOS kernels are large compilation units. Free-plan quota exhaustion is a real, documented occurrence.
- **Security posture**: Commercial, professional security practices, SLA, documented public key on their website

**Key finding**: Without `attic.xuyh0120.win/lantian`, Nix falls back to `cache.garnix.io` when quota is available, and to source compilation when it is not (30–90+ minutes for kernel builds). The `release` branch tracking means new kernels only land there after Hydra has verified them, so Garnix likely saw the same builds — but quota exhaustion remains a real risk.

---

## 4. Risk Model

### Why Key Pinning Does Not Fully Mitigate the Risk

`nix.settings.extra-trusted-public-keys` implements **public-key pinning**: Nix will only accept store paths signed by one of the pinned keys. This protects against:
- Man-in-the-middle substitution from an unsigned or differently-signed binary
- A malicious cache that uses a different key

It does **not** protect against:
- **Private key compromise**: If an attacker obtains the private key corresponding to `lantian:EeAUQ+W+...`, they can sign arbitrary Nix store paths with it. Nix will accept these as a valid substitution without any warning.
- **Server compromise with key access**: `attic.xuyh0120.win` is a personal server. If the server is compromised, the private key stored on it is also compromised.
- **There is no revocation mechanism** in Nix binary caches. Once a key is compromised and the attacker has published a malicious package, any system that fetches the affected cache path will silently install the malicious binary.

### The Threat Scenario

1. Attacker compromises `attic.xuyh0120.win` or obtains the `lantian` private signing key through any means.
2. Attacker publishes a modified `linux-cachyos-bore` (or any other kernel variant) signed with the stolen key to the Attic instance.
3. Any VexOS user with `kernel.type = "cachyos-gaming"` (or any other CachyOS type) runs `nixos-rebuild switch`.
4. Nix finds the signed binary in the trusted substituter, accepts it without verification, and installs the malicious kernel.
5. On next boot: **full kernel-level compromise** — rootkits, keyloggers, bypassing all userspace security controls.

### Comparative Trust Assessment

| Cache | Operator | Key Management | Incident Response | Risk Level |
|-------|----------|---------------|-------------------|------------|
| `attic.xuyh0120.win/lantian` | Individual (xddxdd) | Personal server, single point | No published SLA or incident response | **HIGH** |
| `cache.garnix.io` | Garnix Inc. | Corporate, likely HSM or secrets manager | Commercial SLA, professional operations | **LOW** |

### Is `cache.garnix.io` a Legitimate Commercial Service?

Yes. Garnix (garnix.io) is a commercial CI and binary cache service for Nix/NixOS. Their `cache.garnix.io` public key is documented on their official website and is widely used in the NixOS ecosystem. They operate with commercial security practices and the key `cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=` is their standard, publicly documented signing key.

---

## 5. Fix Options Analysis

### Option A — Remove `attic.xuyh0120.win/lantian` Only (RECOMMENDED)

Remove the personal Attic cache and its public key from `nix.settings`. Keep `cache.garnix.io`.

**Pros**:
- Eliminates the personal server attack vector entirely
- Garnix provides the same kernel binaries when its free-plan quota allows
- Garnix key compromise is a far lower risk (commercial operator, professional key management)
- Functional loss is bounded: when Garnix has quota exhausted, Nix falls back to source build (slow but safe)
- Minimal code change, easy to review

**Cons**:
- Free-plan quota exhaustion means occasional source builds (30–90 minutes)
- `release` branch guarantee is built around Hydra CI coverage, not Garnix

**Verdict**: Strictly better security. The reliability cost is real but bounded and acceptable.

### Option B — Keep Both Caches, Add Documentation Comments

Keep `attic.xuyh0120.win/lantian` and `cache.garnix.io` but add detailed comments documenting the trust decision.

**Pros**:
- Maximum build reliability (Hydra CI always provides binaries)
- Risk is made explicit and auditable in code

**Cons**:
- The attack vector is unchanged — a personal server compromise is still exploitable
- Adding comments does not reduce the attack surface; it only acknowledges it
- A documented risk is still a real risk

**Verdict**: Inappropriate as a "security fix." This is documentation, not remediation.

### Option C — Remove Both Caches

Remove both `attic.xuyh0120.win/lantian` and `cache.garnix.io`. All CachyOS kernels build from source.

**Pros**:
- Maximally safe supply chain

**Cons**:
- 30–90+ minute kernel builds on every switch
- Defeats the primary use case of the `nix-cachyos-kernel` flake
- Unnecessarily aggressive — `cache.garnix.io` is a legitimate trusted commercial cache

**Verdict**: Disproportionate. Acceptable only if the user explicitly wants maximum isolation.

### Decision: Option A

**Rationale**: The goal is supply-chain trust reduction, not supply-chain elimination. `attic.xuyh0120.win/lantian` is the high-risk element (personal server, no revocation, kernel-level blast radius). Removing it while retaining the commercially-operated `cache.garnix.io` reduces the trust surface to a single commercial entity. When Garnix quota is exhausted, source builds are the fallback — this is safe. The commented-out re-add note allows users to consciously opt back in to the personal cache if they require guaranteed binary availability and accept the risk.

---

## 6. Exact Code Changes

### File to Modify: `modules/kernel.nix`

**Current code (lines 128–140)**:

```nix
    # ── Binary cache for CachyOS kernels ──────────────────────────────────
    (lib.mkIf isCachyos {
      nix.settings = {
        extra-substituters = [
          "https://attic.xuyh0120.win/lantian"
          "https://cache.garnix.io"
        ];
        extra-trusted-public-keys = [
          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        ];
      };
    })
```

**Replacement code**:

```nix
    # ── Binary cache for CachyOS kernels ──────────────────────────────────
    # cache.garnix.io is operated by Garnix Inc. (https://garnix.io), a commercial
    # NixOS CI and binary cache service. The nix-cachyos-kernel flake has Garnix CI
    # configured; successfully built packages are pushed to this cache and signed
    # with the documented Garnix public key.
    #
    # TRUST BASIS: Garnix is a commercial operator with professional key management.
    # Their public key is officially documented at https://garnix.io.
    #
    # CAVEAT: The nix-cachyos-kernel Garnix CI runs on the free plan and may exhaust
    # its build quota for large kernel compilations. When the cache misses, Nix falls
    # back to building from source (slow, but fully safe). The upstream `release`
    # branch minimises this: it only advances when Hydra CI has verified a successful
    # build, so Garnix CI is likely to have seen the same revision.
    #
    # INTENTIONALLY OMITTED: The personal Attic cache at attic.xuyh0120.win/lantian
    # (operated by the nix-cachyos-kernel flake maintainer, key:
    #   lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=)
    # has been removed. That cache is backed by a personal server whose private signing
    # key compromise would silently deliver a malicious kernel to any system running a
    # CachyOS variant. There is no key revocation mechanism in Nix binary caches.
    # If you require guaranteed binary cache availability and consciously accept the
    # personal-server trust, re-add both lines above.
    (lib.mkIf isCachyos {
      nix.settings = {
        extra-substituters = [
          "https://cache.garnix.io"
        ];
        extra-trusted-public-keys = [
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        ];
      };
    })
```

### Files NOT to Modify

| File | Reason |
|------|--------|
| `flake.nix` | `nix-cachyos-kernel` input and overlay remain unconditional. The overlay is evaluated lazily and fetches nothing unless a CachyOS kernel type is selected. No change required. |
| `hosts/default/configuration.nix` | `kernel.type = "stock"` does not trigger the cache block. No change required. |
| `modules/kernel.nix` — `isCachyos` predicate (lines 19–26) | Already correctly scopes cache settings to CachyOS kernel types only. No change required. |

---

## 7. Conditional Scoping Assessment

The existing `isCachyos` predicate correctly gates the `nix.settings` block. This means:

- `kernel.type = "stock"` → **no cache settings applied** (correct)
- `kernel.type = "bazzite"` → **no cache settings applied** (correct — Bazzite has its own supply chain)
- `kernel.type = "cachyos-*"` → **cache settings applied** (correct)

No changes to the conditional scoping are required.

---

## 8. Verdict

**This is a real security bug, not merely acceptable risk.**

The presence of a personal binary cache server with an undocumented signing key in `nix.settings.extra-trusted-public-keys`, combined with the kernel-level blast radius of a successful supply-chain attack, constitutes a meaningful supply-chain risk. The absence of any comment explaining the trust decision compounds the issue — future maintainers have no basis to audit or question the choice.

The fix (Option A) is minimal, non-disruptive, and strictly reduces the attack surface. CachyOS kernel functionality is fully preserved. The only potential impact is occasional source builds when Garnix's free-plan quota is exhausted, which is safe.

---

## 9. Summary

| Item | Value |
|------|-------|
| **Real bug?** | Yes — undocumented personal server in trusted substituters, kernel-level blast radius |
| **Chosen fix** | Option A: Remove `attic.xuyh0120.win/lantian` and `lantian:` key; keep `cache.garnix.io` |
| **Conditional scoping change needed?** | No — `isCachyos` guard already correct |
| **Files to modify** | `modules/kernel.nix` only |
| **Lines affected** | 128–140 (replace entire cache block) |
| **Functional impact** | Possible source builds when Garnix quota exhausted; otherwise zero impact |
| **Security improvement** | Eliminates personal-server supply-chain attack vector for kernel-level code |

---

## 10. Files to Be Modified

- `modules/kernel.nix` — lines 128–140: replace binary cache block per Section 6
