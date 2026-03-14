# vex-kernels Repository — Setup Instructions for GitHub Copilot

> **Purpose of this document:** Paste the "Copilot Prompt" section below
> directly into GitHub Copilot (Agent mode) inside a fresh, empty workspace
> that will become the `vex-kernels` GitHub repository. Copilot should be
> able to create every file from scratch using only those instructions.
>
> The "Notes for the User" section after the prompt explains manual steps
> (creating the repo, registering garnix, filling in hashes).

---

## Copilot Prompt

> Paste everything from this line down to the "Notes for the User" section
> into GitHub Copilot.

---

You are a NixOS flake packaging expert. Create the entire `vex-kernels`
repository from scratch. This repo packages the Bazzite gaming kernel for
NixOS and exposes it as a flake output that the VexOS project can consume.

Read every instruction carefully and create all listed files with the exact
content specified. Where placeholder values appear (marked `# FILL IN`) the
user will substitute real values after first build.

---

### Overview

**Repository name:** `vex-kernels`
**Purpose:** Package the Bazzite kernel (from `bazzite-org/kernel-bazzite`)
for NixOS using `buildLinux`. Expose a `pkgs.vexKernels.linuxPackages-bazzite`
overlay output so that the VexOS NixOS flake can set
`boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;`.

**Binary cache:** [garnix.io](https://garnix.io) — free for public GitHub repos.
The garnix GitHub App automatically builds every push and caches results.
Consumers add a single substituter URL and public key; no account needed
on their side.

**Architecture:** x86_64-only.

**Bazzite kernel source facts (as of 2026-03-13, version 6.17.7-ba28):**
- Upstream kernel tarball: `linux-6.17.7.tar.xz` from kernel.org
- Repository: `https://github.com/bazzite-org/kernel-bazzite`, branch `bazzite-6.17`
- The repo is a fork of Fedora's kernel-ark. It applies four patches on top
  of stock kernel.org 6.17.7:
  1. `patch-1-redhat.patch` — Fedora/ARK patchset (BORE scheduler, fsync,
     performance work, in-tree Fedora driver additions)
  2. `patch-2-handheld.patch` — Handheld hardware patches (Steam Deck LCD/OLED,
     ROG Ally, OneXPlayer, Surface devices, HHD input support)
  3. `patch-3-akmods.patch` — AKMOD out-of-tree driver support (broadcom-wl,
     evdi, etc.)
  4. `patch-4-amdgpu-vrr-whitelist.patch` — AMD VRR whitelist for ugreen adaptor

---

### File 1 — `flake.nix`

Create `flake.nix` at the repository root with this exact content:

```nix
{
  description = "VexOS custom kernels — Bazzite gaming kernel for NixOS";

  inputs = {
    # Do NOT follow the consumer's nixpkgs.
    # Kernel patch compatibility is tied to the kernel version in this nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs   = nixpkgs.legacyPackages.${system};
    in
    {
      # ── Raw kernel derivation ─────────────────────────────────────────────
      packages.${system} = {
        linux-bazzite =
          pkgs.callPackage ./kernels/bazzite { };
      };

      # ── linuxPackages set (contains kernel + all modules/extraModules) ─────
      # Consumers can also reference this directly:
      #   inputs.vex-kernels.legacyPackages.x86_64-linux.linuxPackages-bazzite
      legacyPackages.${system} = {
        linuxPackages-bazzite =
          pkgs.linuxKernel.packagesFor
            self.packages.${system}.linux-bazzite;
      };

      # ── Overlay — the primary integration point for VexOS ────────────────
      # Apply in your NixOS config with:
      #   nixpkgs.overlays = [ inputs.vex-kernels.overlays.default ];
      # Then use:
      #   boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;
      overlays.default = final: prev:
        let
          linux-bazzite =
            prev.callPackage ./kernels/bazzite { };
        in
        {
          vexKernels = prev.recurseIntoAttrs {
            inherit linux-bazzite;
            linuxPackages-bazzite =
              prev.linuxKernel.packagesFor linux-bazzite;
          };
        };

      # ── Flake checks ──────────────────────────────────────────────────────
      checks.${system} = {
        # Verify the kernel derivation evaluates without error.
        # Does NOT build the kernel (too slow for CI checks).
        linux-bazzite-eval = pkgs.runCommand "linux-bazzite-eval" { } ''
          echo "Version: ${self.packages.${system}.linux-bazzite.version}"
          touch $out
        '';
      };
    };
}
```

---

### File 2 — `kernels/bazzite/default.nix`

Create `kernels/bazzite/default.nix` with this exact content:

```nix
# kernels/bazzite/default.nix
#
# Bazzite Gaming Kernel for NixOS
# ================================
# Based on linux-6.17.7 from kernel.org with Bazzite's four-patch set
# sourced from github.com/bazzite-org/kernel-bazzite (branch bazzite-6.17).
#
# Patch summary:
#   patch-1-redhat   — Fedora/ARK patchset: BORE scheduler, fsync, performance
#   patch-2-handheld — Handheld device patches: Steam Deck, ROG Ally, etc.
#   patch-3-akmods   — AKMOD driver support
#   patch-4-amdgpu   — AMD VRR whitelist
#
# Updating:
#   1. Check https://github.com/bazzite-org/kernel-bazzite/releases for latest.
#   2. Update `version`, `bazziteRelease`, and patch URLs below.
#   3. Run: nix build .#linux-bazzite 2>&1 | grep "got:"
#      and replace each sha256 placeholder with the reported hash.

{ lib
, buildLinux
, fetchurl
, ...
} @ args:

let
  # ── Version pins ───────────────────────────────────────────────────────────
  # Kernel.org upstream version
  version       = "6.17.7";

  # Bazzite release suffix (ba## from the release tag, e.g. 6.17.7-ba28)
  bazziteRelease = "ba28";

  # Branch in bazzite-org/kernel-bazzite containing the patches
  bazziteBranch  = "bazzite-6.17";

  # Module directory version — matches what `uname -r` would report.
  # For NixOS the kernel installs its modules under /lib/modules/${version}.
  modDirVersion  = version;

  # ── Patch sources ─────────────────────────────────────────────────────────
  bazziteRawBase =
    "https://raw.githubusercontent.com/bazzite-org/kernel-bazzite/${bazziteBranch}";

  mkBazzitePatch = name: file: {
    inherit name;
    patch = fetchurl {
      url  = "${bazziteRawBase}/${file}";
      # FILL IN: run `nix build` and replace with the hash reported by Nix.
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };

in
buildLinux (args // {
  pname         = "linux-bazzite";
  inherit version modDirVersion;

  # ── Kernel source tarball from kernel.org ──────────────────────────────────
  src = fetchurl {
    url  = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${version}.tar.xz";
    # FILL IN: run `nix build` and replace with the hash reported by Nix.
    hash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };

  # ── Base kernel config ────────────────────────────────────────────────────
  # Fetches Fedora's x86_64 config directly from bazzite-org/kernel-bazzite.
  # This is the exact config Bazzite uses, base of the Fedora ARK build.
  # `buildLinux` runs `make olddefconfig` on top of this, so any new config
  # options introduced by patches are auto-resolved to their safe defaults.
  configfile = fetchurl {
    url  = "${bazziteRawBase}/kernel-x86_64-fedora.config";
    # FILL IN: run `nix build` and replace with the hash reported by Nix.
    hash = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";
  };

  # ── Bazzite patch set ─────────────────────────────────────────────────────
  kernelPatches = [
    (mkBazzitePatch "bazzite-redhat-ark"   "patch-1-redhat.patch")
    (mkBazzitePatch "bazzite-handheld"     "patch-2-handheld.patch")
    (mkBazzitePatch "bazzite-akmods"       "patch-3-akmods.patch")
    (mkBazzitePatch "bazzite-amdgpu-vrr"   "patch-4-amdgpu-vrr-whitelist.patch")
  ];

  # ── NixOS-critical overrides ───────────────────────────────────────────────
  # The Fedora config is a complete starting point. These overrides ensure
  # the kernel cooperates with NixOS's init system and module loading.
  # They are applied AFTER `make olddefconfig` resolves the base config.
  structuredExtraConfig = with lib.kernel; {
    # NixOS boot requirements
    DEVTMPFS       = yes;
    DEVTMPFS_MOUNT = yes;
    TMPFS          = yes;
    # Needed by NixOS's module loading (modprobe/udev)
    MODULE_SIG         = lib.mkForce no;  # NixOS re-signs as needed
    MODULE_SIG_FORCE   = lib.mkForce no;
    # NixOS uses systemd-boot / GRUB; no built-in EFI stub required
    EFI_STUB = lib.mkForce yes;
    # Ensure the kernel can be booted under QEMU for testing
    VIRTIO_PCI = yes;
    VIRTIO_BLK = yes;
    VIRTIO_NET = yes;
  };

  # ── Package metadata ──────────────────────────────────────────────────────
  extraMeta = {
    branch      = "6.17";
    description = "Bazzite gaming kernel ${version}-${bazziteRelease}: "
      + "Fedora ARK base + BORE scheduler + handheld patches";
    maintainers = [ ];  # Add yourself if you like
    platforms   = [ "x86_64-linux" ];
  };
})
```

---

### File 3 — `kernels/bazzite/.gitkeep`

Create an empty placeholder so the git history preserves the patches
subdirectory reference:

```
# This directory holds the Bazzite kernel derivation.
# Patches are fetched at build time from bazzite-org/kernel-bazzite.
# See default.nix for the complete derivation.
```

(Create this as a file named `kernels/bazzite/PATCHES.md`.)

---

### File 4 — `garnix.yaml`

Create `garnix.yaml` at the repository root. garnix reads this to decide
which outputs to build and cache. We limit it to the one package we expose
to avoid wasting build minutes on checks.

```yaml
# garnix.yaml
#
# garnix.io CI configuration for vex-kernels.
# https://garnix.io/docs/ci/yaml_config/
#
# garnix automatically caches everything it builds.
# Consumers add:
#   nix.settings.substituters        = [ "https://cache.garnix.io" ];
#   nix.settings.trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];

builds:
  include:
    # Only build the kernel package — checks and devShells are excluded
    # because the kernel build already takes 1-2 hours.
    - packages.x86_64-linux.linux-bazzite
  exclude: []
```

---

### File 5 — `.github/workflows/build.yml`

Create `.github/workflows/build.yml`. This workflow validates the flake
structure and checks that the derivation evaluates, but does **not** compile
the kernel (garnix handles the full build and caching in the background).

```yaml
# .github/workflows/build.yml
#
# Validates flake structure on every push and pull request.
# Actual kernel compilation is handled by the garnix GitHub App —
# install it at https://garnix.io/docs/getting-started/github-app/

name: Flake Check

on:
  push:
    branches: [ "main" ]
  pull_request:

jobs:
  flake-check:
    name: nix flake check (no build)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main

      - name: Magic Nix Cache
        uses: DeterminateSystems/magic-nix-cache-action@main

      - name: Show flake outputs
        run: nix flake show

      - name: Check flake (evaluate only, no build)
        run: nix flake check --no-build

  eval-kernel:
    name: Evaluate kernel derivation
    runs-on: ubuntu-latest
    needs: flake-check

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main

      - name: Magic Nix Cache
        uses: DeterminateSystems/magic-nix-cache-action@main

      - name: Evaluate derivation metadata
        run: |
          nix eval .#packages.x86_64-linux.linux-bazzite.version
          nix eval .#packages.x86_64-linux.linux-bazzite.pname
```

---

### File 6 — `README.md`

Create `README.md` at the repository root:

```markdown
# vex-kernels

Custom Linux kernels packaged for NixOS as a Nix flake.

Currently provided:

| Kernel | Base | Key Patches |
|--------|------|-------------|
| Bazzite (`linux-bazzite`) | kernel.org 6.17.7 | BORE scheduler, Steam Deck/ROG Ally handheld patches, AMD VRR |

## Binary Cache

Kernels are built and cached by [garnix.io](https://garnix.io).
Without the cache, the first build takes **1–2+ hours**.
With the cache, installation is instant.

Add to your NixOS configuration:

```nix
nix.settings = {
  substituters        = [ "https://cache.garnix.io" ];
  trusted-public-keys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];
};
```

## Usage in a NixOS Flake

### Step 1 — Add input

```nix
inputs = {
  vex-kernels = {
    url = "github:YOUR_GITHUB_USERNAME/vex-kernels";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### Step 2 — Apply overlay

```nix
nixpkgs.overlays = [ inputs.vex-kernels.overlays.default ];
```

### Step 3 — Select kernel

```nix
boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;
```

## Updating the Bazzite kernel

1. Check [releases](https://github.com/bazzite-org/kernel-bazzite/releases)
   for the latest tag (e.g., `6.17.9-ba05`).
2. Edit `kernels/bazzite/default.nix`:
   - Update `version`, `bazziteRelease`, and if needed `bazziteBranch`.
3. Reset all `hash` fields to `"sha256-AAAA...="` (any invalid hash).
4. Run `nix build .#linux-bazzite 2>&1 | grep "got:"` for each fetch.
5. Replace placeholders with the reported hashes.
6. Commit and push — garnix will rebuild and cache automatically.

## Source

Kernel patches from: [bazzite-org/kernel-bazzite](https://github.com/bazzite-org/kernel-bazzite)

The Bazzite kernel is built on top of Fedora's
[kernel-ark](https://gitlab.com/cki-project/kernel-ark) with additional
handheld and gaming patches.
```

---

### How VexOS Consumes This Flake

Once the `vex-kernels` repo is published to GitHub, make the following three
changes to the VexOS repository (`vex-nix`):

#### 1. `flake.nix` — Uncomment and fill in the `vex-kernels` input block

Find the TODO comment block and replace it:

```nix
# Before (comment to remove):
# vex-kernels = {
#   url = "github:<owner>/vex-kernels";
#   inputs.nixpkgs.follows = "nixpkgs";
# };

# After:
vex-kernels = {
  url = "github:YOUR_GITHUB_USERNAME/vex-kernels";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

#### 2. `flake.nix` — Uncomment the overlay in `mkVexosSystem`

Find the TODO overlay comment and uncomment it:

```nix
# Before (comment to remove):
# { nixpkgs.overlays = [ inputs.vex-kernels.overlays.default ]; }

# After:
{ nixpkgs.overlays = [ inputs.vex-kernels.overlays.default ]; }
```

#### 3. `modules/kernel.nix` — Wire up the bazzite case

Find the `bazzite` `mkIf` block (currently throws an error) and replace
the entire block:

```nix
# Replace the entire bazzite `mkIf` block with:
(lib.mkIf (cfg.type == "bazzite") {
  boot.kernelPackages = pkgs.vexKernels.linuxPackages-bazzite;

  # Binary cache — fetches the pre-built kernel from garnix.io instead
  # of compiling locally (compilation takes 1-2+ hours without cache).
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

---

### Important Caveats

1. **Kernel compilation time:** The first `nix build` without a populated
   cache takes **1–2+ hours** on modern hardware. This is normal. GitHub
   Actions CI is intentionally configured to skip the actual build and
   delegate it to garnix.

2. **garnix free tier:** garnix is free for public repos. After the first
   garnix-triggered build completes (triggered automatically on each push),
   subsequent `nixos-rebuild` runs on any machine will pull the pre-built
   NAR from `cache.garnix.io` in seconds.

3. **Hash placeholders:** Every `hash = "sha256-AAA...="` in
   `kernels/bazzite/default.nix` is a placeholder that will cause Nix to
   fail with a message like:
   ```
   error: hash mismatch in fixed-output derivation
     specified: sha256-AAAA...
     got:       sha256-<real hash here>
   ```
   Copy the `got:` value and paste it into the corresponding `hash` field.
   Run `nix build` again after each fix. There are 6 hashes to fill in
   (kernel source, kernel config, and 4 patches).

4. **Tracking upstream:** The Bazzite team releases new kernel versions
   frequently (tagged `6.x.y-baNNN` on the releases page). Check
   https://github.com/bazzite-org/kernel-bazzite/releases to keep
   `version` and `bazziteRelease` current. The patch filenames
   (`patch-1-redhat.patch`, etc.) are stable but their contents change
   with each bump.

5. **Fedora config in NixOS:** The derivation uses the Fedora x86_64 kernel
   config as its base, then `buildLinux` runs `make olddefconfig` to
   resolve any NixOS-specific options. The `structuredExtraConfig` overrides
   in `default.nix` enforce NixOS-critical settings. If you encounter boot
   issues, `journalctl -b -p err` and comparing against a working NixOS
   kernel config is the first debugging step.

6. **No `nixpkgs.follows` for the flake's own nixpkgs:** The comment in
   `flake.nix` explains why: kernel.org patch compatibility is tied to the
   kernel version present in the exact nixpkgs revision this flake pins.
   Using `inputs.nixpkgs.follows = "nixpkgs"` from VexOS could cause patch
   application failures if VexOS's nixpkgs is on a different kernel minor
   version.

---

End of Copilot Prompt.

---

## Notes for the User

### Manual Steps Required After Copilot Creates the Files

#### 1. Create the GitHub repository

Go to https://github.com/new and create a **public** repository named
`vex-kernels`. Do not initialize it with a README (Copilot already wrote one).

Push the generated files:

```bash
cd /path/to/vex-kernels
git init
git add .
git commit -m "feat: initial Bazzite kernel flake for NixOS"
git remote add origin https://github.com/YOUR_USERNAME/vex-kernels.git
git push -u origin main
```

#### 2. Install the garnix GitHub App

Visit https://garnix.io/docs/getting-started/github-app/ and install the
garnix app on your `vex-kernels` repo. After the first push, garnix will
pick up the build automatically (look for a commit check on GitHub labeled
"garnix"). The first build takes 1–2 hours.

#### 3. Fill in the sha256 hashes

Before pushing, you **must** fill in the 6 hash placeholders in
`kernels/bazzite/default.nix`. The easiest method:

```bash
# In the vex-kernels directory with Nix installed:
nix build .#packages.x86_64-linux.linux-bazzite 2>&1 | grep "got:"
```

Each failure prints the correct hash. Replace the placeholder and re-run
until all 6 pass. Commit the filled-in hashes before pushing to GitHub.

Alternatively, use `nix-prefetch-url` for each URL:

```bash
nix-prefetch-url --type sha256 \
  "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.7.tar.xz"
```

Convert the raw sha256 output to the `sha256-<base64>=` format with:

```bash
nix hash to-sri sha256:<raw-hash>
```

#### 4. Update VexOS flake.nix

After the repo is live and hashes are filled in, apply the three changes
described in the "How VexOS Consumes This Flake" section above to the
`vex-nix` repository. Then run:

```bash
cd /path/to/vex-nix
nix flake update vex-kernels
sudo nixos-rebuild build --flake .#vexos
```

---

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `bazzite-org/kernel-bazzite` not `ublue-os/bazzite` | Bazzite only moved the kernel to its own org repo (`bazzite-org/kernel-bazzite`) in late 2025. The main `ublue-os/bazzite` is an OCI container image builder, not the kernel source. |
| garnix over Cachix or self-hosted Hydra | garnix is zero-config for public repos: install the GitHub App, push, and the cache is populated automatically. No account setup, no API keys, no self-hosted infrastructure. The public key `cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=` is stable and documented. |
| `inputs.nixpkgs.follows` NOT set in vex-kernels | Kernel patches in nixpkgs are tied to specific kernel versions. If VexOS follows a different nixpkgs revision that ships a different 6.17.x, `buildLinux` may fail to apply the patches. Each repo pins its own nixpkgs to guarantee compatibility. |
| Use Fedora x86_64 config as `configfile` | This is the exact config Bazzite ships. Using nixpkgs' generic defconfig would miss many gaming/handheld tunings. `make olddefconfig` handles any conflicts. |
| 4 separate patch fetches, not a tarball | Allows per-patch version pinning and clear visibility into what's applied. Easy to add/remove individual patches without re-fetching everything. |
| `pkgs.vexKernels.linuxPackages-bazzite` overlay shape | Mirrors the `pkgs.cachyosKernels.*` shape used by `nix-cachyos-kernel`, which VexOS already consumes. Consistent ergonomics for kernel selection in `modules/kernel.nix`. |
| GitHub Actions only evaluates, doesn't build | Kernel builds are too slow for standard GitHub Actions runners (1-2 hours). Garnix is the CI/build engine; GitHub Actions just validates the flake evaluates correctly. |

---

### Bazzite Kernel Update Checklist

When a new Bazzite release is tagged (e.g., new ba## or new x.y.z version):

- [ ] Check https://github.com/bazzite-org/kernel-bazzite/releases
- [ ] Update `version` in `kernels/bazzite/default.nix` if kernel.org version changed
- [ ] Update `bazziteRelease` (e.g., `ba28` → `ba30`)
- [ ] Update `bazziteBranch` if minor version changed (e.g., `bazzite-6.17` → `bazzite-6.18`)
- [ ] Invalidate all hash placeholders and re-run `nix build` to get new hashes
- [ ] Commit and push — garnix rebuilds and caches automatically
- [ ] Run `nix flake update vex-kernels` in VexOS to pick up the new revision
