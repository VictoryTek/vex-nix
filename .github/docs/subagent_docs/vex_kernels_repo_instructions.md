# vex-kernels Repository — Setup Instructions for GitHub Copilot

> **Purpose of this document:** Paste the "Copilot Prompt" section below
> directly into GitHub Copilot (Agent mode) inside a fresh, empty workspace
> that will become the `vex-kernels` GitHub repository. Copilot should be
> able to create every file from scratch using only those instructions.
>
> The "Notes for the User" section after the prompt explains manual steps
> (creating the repo, generating signing keys, configuring GitHub Pages, filling in hashes).

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

**Binary cache:** GitHub Actions builds kernels on a 16-core runner and publishes the resulting NARs to **GitHub Pages** as a standard Nix binary cache. Consumers add the GitHub Pages URL as a substituter and the repo's ed25519 public key as a trusted key. No third-party services required.

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

### File 4 — `.github/workflows/build.yml`

Create `.github/workflows/build.yml`. This workflow builds the kernel on a
16-core runner, signs and exports NARs, and deploys them to GitHub Pages as
a binary cache.

```yaml
name: Build and Cache Kernels

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:
  schedule:
    - cron: '0 6 * * 1'

jobs:
  build-bazzite:
    name: Build linux-bazzite kernel
    runs-on: ubuntu-22.04-16-core
    permissions:
      contents: read
      pages: write
      id-token: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main

      - name: Restore Nix store cache
        uses: actions/cache@v4
        with:
          path: /tmp/nix-cache
          key: nix-bazzite-${{ hashFiles('kernels/bazzite/default.nix') }}
          restore-keys: nix-bazzite-

      - name: Build linux-bazzite
        run: |
          nix build .#packages.x86_64-linux.linux-bazzite \
            --no-link --out-link /tmp/linux-bazzite -L

      - name: Export and sign NARs
        env:
          NIX_SIGNING_KEY: ${{ secrets.NIX_SIGNING_KEY }}
        run: |
          mkdir -p ./cache
          nix copy --to "file://$(pwd)/cache?compression=zstd" \
            --no-check-sigs /tmp/linux-bazzite
          nix store sign \
            --key-file <(echo "$NIX_SIGNING_KEY") \
            --recursive /tmp/linux-bazzite
          nix copy --to "file://$(pwd)/cache?compression=zstd" \
            /tmp/linux-bazzite
          printf 'StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 50\n' \
            > ./cache/nix-cache-info

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./cache

  deploy-cache:
    name: Deploy cache to GitHub Pages
    runs-on: ubuntu-latest
    needs: build-bazzite
    permissions:
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

---

### File 5 — `README.md`

Create `README.md` at the repository root:

```markdown
# vex-kernels

Custom Linux kernels packaged for NixOS as a Nix flake.

Currently provided:

| Kernel | Base | Key Patches |
|--------|------|-------------|
| Bazzite (`linux-bazzite`) | kernel.org 6.17.7 | BORE scheduler, Steam Deck/ROG Ally handheld patches, AMD VRR |

## Binary Cache

Kernels are built by GitHub Actions (16-core runner) and served as a Nix
binary cache via GitHub Pages. Without the cache, the first build takes
**1–2+ hours**. With the cache, installation is instant.

Add to your NixOS configuration:

```nix
nix.settings = {
  substituters        = [ "https://YOUR_GITHUB_USERNAME.github.io/vex-kernels" ];
  trusted-public-keys = [ "vex-kernels-1:YOUR_PUBLIC_KEY_HERE" ];
};
```

Replace `YOUR_GITHUB_USERNAME` with your GitHub username and
`YOUR_PUBLIC_KEY_HERE` with the public key generated during repo setup.

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
6. Commit and push — GitHub Actions will rebuild and deploy the cache automatically.

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

  # Binary cache — fetches the pre-built kernel from GitHub Pages instead
  # of compiling locally (compilation takes 1-2+ hours without cache).
  nix.settings = {
    extra-substituters = [
      "https://YOUR_GITHUB_USERNAME.github.io/vex-kernels"
    ];
    extra-trusted-public-keys = [
      "vex-kernels-1:YOUR_PUBLIC_KEY_HERE"
    ];
  };
})
```

---

### Important Caveats

1. **Kernel compilation time:** The first `nix build` without a populated
   cache takes **1–2+ hours** on modern hardware. This is normal. GitHub
   Actions CI is intentionally configured to skip the actual build and
   build kernels on a 16-core GitHub Actions runner and deploy them to a GitHub Pages binary cache.

2. **GitHub Actions + GitHub Pages cache:** The 16-core GitHub Actions runner
   (free for public repos) handles the full kernel build. After the first
   workflow run completes (triggered automatically on each push), subsequent
   `nixos-rebuild` runs on any machine will pull the pre-built NAR from
   the GitHub Pages cache in seconds.

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

#### 2. Generate signing keys and configure GitHub

```bash
# Generate ed25519 signing key pair
nix-store --generate-binary-cache-key vex-kernels-1 \
  /tmp/vex-kernels-private.pem \
  /tmp/vex-kernels-public.pem

cat /tmp/vex-kernels-public.pem   # ← paste this as YOUR_PUBLIC_KEY_HERE everywhere
cat /tmp/vex-kernels-private.pem  # ← add as GitHub Secret (next step)
```

1. Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `NIX_SIGNING_KEY`
   - Value: paste contents of `/tmp/vex-kernels-private.pem`

2. Go to your repo → **Settings → Pages**
   - Set Source to **GitHub Actions** → Save

3. Replace every occurrence of `YOUR_PUBLIC_KEY_HERE` in README.md and
   in VexOS `modules/kernel.nix` with the actual public key string.

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
| GitHub Actions + GitHub Pages as binary cache | Zero third-party dependencies. A 16-core GitHub Actions runner (free for public repos) handles kernel compilation. NARs are signed with a repo-owned ed25519 key and deployed to GitHub Pages, which serves them as a standard Nix substituter. The public key and substituter URL are fully under the repo owner's control. |
| `inputs.nixpkgs.follows` NOT set in vex-kernels | Kernel patches in nixpkgs are tied to specific kernel versions. If VexOS follows a different nixpkgs revision that ships a different 6.17.x, `buildLinux` may fail to apply the patches. Each repo pins its own nixpkgs to guarantee compatibility. |
| Use Fedora x86_64 config as `configfile` | This is the exact config Bazzite ships. Using nixpkgs' generic defconfig would miss many gaming/handheld tunings. `make olddefconfig` handles any conflicts. |
| 4 separate patch fetches, not a tarball | Allows per-patch version pinning and clear visibility into what's applied. Easy to add/remove individual patches without re-fetching everything. |
| `pkgs.vexKernels.linuxPackages-bazzite` overlay shape | Mirrors the `pkgs.cachyosKernels.*` shape used by `nix-cachyos-kernel`, which VexOS already consumes. Consistent ergonomics for kernel selection in `modules/kernel.nix`. |
| 16-core GitHub Actions runner for full builds | Kernel builds take 1–2 hours; a standard 2-core runner would time out. The 16-core runner (free for public repos) completes the full kernel build and then deploys NARs to GitHub Pages as a binary cache. |

---

### Bazzite Kernel Update Checklist

When a new Bazzite release is tagged (e.g., new ba## or new x.y.z version):

- [ ] Check https://github.com/bazzite-org/kernel-bazzite/releases
- [ ] Update `version` in `kernels/bazzite/default.nix` if kernel.org version changed
- [ ] Update `bazziteRelease` (e.g., `ba28` → `ba30`)
- [ ] Update `bazziteBranch` if minor version changed (e.g., `bazzite-6.17` → `bazzite-6.18`)
- [ ] Invalidate all hash placeholders and re-run `nix build` to get new hashes
- [ ] Commit and push — GitHub Actions will rebuild and deploy the cache automatically
- [ ] Run `nix flake update vex-kernels` in VexOS to pick up the new revision
