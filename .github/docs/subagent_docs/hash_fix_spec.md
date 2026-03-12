# Hash Fix Specification: PhotoGIMP fetchFromGitHub Placeholder Hash

## Summary

A fixed-output derivation build failure was reported during `sudo nixos-rebuild switch --flake /etc/nixos#vexos`. The root cause is a placeholder (all-zeros) SHA-256 hash in `home/photogimp.nix` that was left as a development stub. The correct hash is now known from the build error output and must be substituted.

---

## Error Message (Verbatim)

```
error: hash mismatch in fixed-output derivation '/nix/store/3dh05s8yj2sjnpl7w9b7ka8mr7sn2sb5-source.drv':
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=
```

---

## Root Cause Analysis

### File Containing the Placeholder

| Property | Value |
|----------|-------|
| **File** | `home/photogimp.nix` |
| **Line** | 29 |
| **Variable** | `hash` inside `pkgs.fetchFromGitHub { ... }` |

### Affected Derivation

```nix
photogimp = pkgs.fetchFromGitHub {
  owner = "Diolinux";
  repo  = "PhotoGIMP";
  rev   = photogimpVersion;   # "3.0"
  hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";   # ← PLACEHOLDER
};
```

- **Source**: `https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz`
- **Package**: PhotoGIMP v3.0 — a GIMP configuration overlay that makes GIMP resemble Adobe Photoshop
- **Used by**: `home.activation.installPhotoGIMP` (copies GIMP config files) and `xdg.dataFile."icons/hicolor"` (installs PhotoGIMP icons)

### Why This Hash Was a Placeholder

The comment in `home/photogimp.nix` explicitly documents this as an intentional temporary stub:

```nix
# Obtain the correct hash by running:
#   nix-prefetch-url --unpack \
#     "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
# OR: set hash = ""; and Nix will report the correct hash on the first
# failed build attempt — replace the empty string with the reported value.
hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```

The all-zeros base64 string (`AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`) is the base64 encoding of 32 zero bytes, which is the conventional "placeholder" hash used in NixOS development workflows to trigger a build-time hash reveal. The build error has now revealed the real hash.

---

## Required Change

### File: `home/photogimp.nix`

**Line 29** — single-line substitution:

| | Value |
|-|-------|
| **Old** | `hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";` |
| **New** | `hash = "sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=";` |

#### Full Context (lines 23–31 for unambiguous targeting)

```nix
  photogimp = pkgs.fetchFromGitHub {
    owner = "Diolinux";
    repo  = "PhotoGIMP";
    rev   = photogimpVersion;
    # Obtain the correct hash by running:
    #   nix-prefetch-url --unpack \
    #     "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
    # OR: set hash = ""; and Nix will report the correct hash on the first
    # failed build attempt — replace the empty string with the reported value.
-   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
+   hash = "sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=";
  };
```

---

## Scope of Change

- **Only one file** requires editing: `home/photogimp.nix`
- **No other files** contain the placeholder hash (all other occurrences are in `.github/docs/subagent_docs/` documentation files, not Nix source)
- **No flake inputs**, `flake.lock`, or other modules are affected
- The change is a pure value substitution — no logic, imports, or structure changes

---

## Verification Steps (Post-Implementation)

After applying the hash substitution, the following commands should be run to confirm the fix:

1. **Nix evaluation check** (fast, no download required):
   ```bash
   nix flake check
   ```

2. **Full build validation**:
   ```bash
   nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf
   ```

3. **Confirm hash resolves correctly** (optional, requires network):
   ```bash
   nix-prefetch-url --unpack \
     "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
   ```
   Expected output: `sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=`

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Hash is still wrong after substitution | Very Low — hash came directly from Nix's own build error | Re-run preflight; error message will show the real hash again |
| Other placeholder hashes exist | None — grep across all `.nix` files found only one instance | Confirmed by exhaustive grep search |
| Breakage of unrelated modules | None — change is isolated to a single `hash =` field | No imports, options, or derivation structure changed |

---

## Implementation Instructions for Phase 2 Subagent

1. Read `home/photogimp.nix`
2. Locate line 29 (the `hash = "sha256-AAAAAA...` line inside `pkgs.fetchFromGitHub`)
3. Replace the placeholder value with the correct hash:
   - **Old string**: `hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";`
   - **New string**: `hash = "sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=";`
4. Do NOT modify any other line in the file
5. Do NOT remove the explanatory comments above the hash field
6. Return the modified file path: `home/photogimp.nix`
