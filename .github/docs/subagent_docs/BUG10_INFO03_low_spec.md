# BUG10–INFO03 Low/Informational Combined Fix Specification

**Date:** 2026-03-19  
**Severity:** Low (BUG-10, BUG-11, BUG-12, BUG-13) / Informational (INFO-01, INFO-02, INFO-03)  
**Status:** Ready for Implementation

---

## Research Summary

### BUG-10 — GameMode `gpu_device`

From the upstream `gamemode.ini` source (FeralInteractive/gamemode `example/gamemode.ini`):

```ini
; Setting this to the keyphrase "accept-responsibility" will allow gamemode to
; apply GPU optimisations such as overclocks
apply_gpu_optimisations=0

; The DRM device number on the system (usually 0), ie. the number in
; /sys/class/drm/card0/
gpu_device=0
```

`apply_gpu_optimisations = "accept-responsibility"` explicitly opts in to GPU clock
manipulation. `gpu_device` identifies the DRM card node (`/sys/class/drm/card<N>`).
On ASUS laptops using `supergfxd` in Hybrid mode, the integrated GPU is card0 and the
discrete dGPU is card1 (or higher). Targeting card0 applies GPU overclocking to the
integrated GPU rather than the discrete one GameMode is intended to boost — the wrong
outcome.

**Design decision:** Remove the entire `gpu` block from `programs.gamemode.settings`.
Without `apply_gpu_optimisations = "accept-responsibility"`, GameMode performs no GPU
manipulation at all. This is safe on all hardware topologies. Users who want GPU
optimizations and know their device index should add the block in their
`hardware-configuration.nix` override.

---

### BUG-11 — PipeWire Quantum

Standard latency reference points at 48000 Hz:

| Quantum | Latency   | Use case                              |
|---------|-----------|---------------------------------------|
| 64      | ~1.33 ms  | Extreme pro-audio; requires RT kernel + dedicated audio hardware |
| 128     | ~2.67 ms  | Semi-pro audio; still risky on shared CPU consumer machines |
| 256     | ~5.33 ms  | Gaming balance — low-latency for gaming, stable under CPU load |
| 512     | ~10.67 ms | Standard NixOS default; comfortable for desktop/multimedia |

The existing comment already says "increase to 128 or 256 if audio cuts out". 256 is the
standard recommendation for gaming systems that need low latency without xruns under
variable CPU load (the dominant workload in gaming). 128 still causes xruns on many
consumer machines during GPU-heavy scenes.

**Decision:** Change `quantum` from `64` to `256`.

---

### BUG-12 — libvirtd `--timeout 0`

The `libvirtd --timeout <seconds>` option sets the number of seconds after the last
client disconnects before libvirtd exits. `0` disables idle exit (daemon stays running
forever). The compiled-in default is **120 seconds** (`man libvirtd`).

On bare-metal machines with KVM, TCG probing is fast (sub-second); the 120 s default
idle timer is far beyond what probing needs and libvirtd will idle-exit cleanly after
the last VM is stopped, freeing memory. `--timeout 0` on bare metal means libvirtd
never exits on idle, holding resident memory indefinitely.

The existing comment correctly identifies the only context where `--timeout 0` is
needed: VMs without nested KVM (VirtualBox or similar), where TCG software-emulation
probing exceeds 120 s.

**Decision:** Remove `extraOptions = [ "--timeout" "0" ]` entirely. The Nix attribute
can be deleted (no default value means libvirtd uses its built-in 120 s idle timeout).
Update the block comment to instruct VM users on how to restore the setting in their
host-specific `hardware-configuration.nix`.

---

### BUG-13 — `boot.shell_on_fail`

`boot.shell_on_fail` is a kernel command-line parameter handled by the NixOS initrd
(ultimately by `systemd` or `ash` in the initrd). When present, a boot failure drops
to an interactive root shell in the early userspace. There is no authentication — the
shell is root.

This is distinct from:
- `rd.emergency` / `rd.break` — systemd-specific emergency shell parameters
- NixOS option `boot.initrd.systemd.emergencyAccess` — controls whether
  `systemd-sulogin-shell` is spawned in initrd emergencies

On machines without full-disk encryption (FDE), physical access during a boot-failure
event yields an unauthenticated root shell that can mount the filesystem read-write.
VexOS does not mandate FDE.

The NixOS-recommended posture for production or shared machines is to omit
`boot.shell_on_fail`. When omitted:
- systemd-based initrds (as used here with `boot.initrd.systemd.enable = true`) will
  reach an emergency state and display a diagnostic message, then reboot or wait.
- The `rd.systemd.show_status=auto` parameter already in kernelParams surfaces
  failure status without a shell.

**Decision:** Remove `"boot.shell_on_fail"` from `boot.kernelParams`.

---

### INFO-01 — Hostname validation in `install.sh`

The `HOSTNAME` variable is shell-interpolated directly into a here-doc Nix expression:

```bash
nixosConfigurations.'"${HOSTNAME}"' = vexos.lib.mkVexosSystem {
```

A value such as `x}` would produce:

```nix
nixosConfigurations.x} = vexos.lib.mkVexosSystem {
```

— a Nix parse error. Characters like `'`, `"`, `$`, `{`, `}`, `;`, `\n` can cause
either malformed Nix or shell injection.

Valid constraints for a `nixosConfigurations` attribute name / RFC 1123 hostname label:
- Starts with an ASCII letter
- Contains only letters, digits, hyphens (`-`), and underscores (`_`)
- Maximum 63 characters per RFC 1123 label

The fix is a regex guard immediately after argument parsing:

```bash
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || [[ ${#HOSTNAME} -gt 63 ]]; then
    fail "--hostname must start with a letter, contain only letters, digits, hyphens, and underscores, and be at most 63 characters."
    exit 1
fi
```

---

### INFO-02 — Nix `max-jobs` / `cores` auto-detection

When `nix.settings.max-jobs` and `nix.settings.cores` are not set in the NixOS module,
the Nix daemon uses its own compiled-in defaults:

- `max-jobs`: `"auto"` in the NixOS `nix` module (confirmed in nixpkgs since ≈22.05).
  Nix maps `"auto"` to the number of logical CPUs at daemon startup.
- `cores`: `0` — means each individual build job may use all available CPU cores.

Removing the hardcoded `2` values from `modules/system.nix` restores auto-detection.
The zram swap and `download-buffer-size` settings already mitigate RAM pressure. Users
on severely RAM-constrained machines (< 4 GB) can add the overrides in their own
`hardware-configuration.nix`.

---

### INFO-03 — `builtins.elem` vs `builtins.substring`

`builtins.elem value list` returns `true` if `value` is an element of `list`. It is an
exact membership check, avoids string indexing arithmetic, and is self-documenting.

The current `builtins.substring 0 7 cfg.type == "cachyos"` check:
- Would match any future type whose first 7 characters are `"cachyos"` even if it is
  not in the supported list
- Is fragile: off-by-one in the length constant fails silently
- Requires the reader to mentally decode the substring arithmetic

Correct replacement using `builtins.elem` against the actual enum list:

```nix
isCachyos = builtins.elem cfg.type [
  "cachyos-gaming"
  "cachyos-server"
  "cachyos-desktop"
  "cachyos-handheld"
  "cachyos-lts"
  "cachyos-hardened"
];
```

---

## BUG-10: GameMode `gpu_device = 0` Hardcoded

**File:** `modules/gaming.nix`

### Current code

```nix
programs.gamemode = {
  enable = true;
  enableRenice = true;
  settings = {
    general = {
      renice = 10;
    };
    gpu = {
      apply_gpu_optimisations = "accept-responsibility";
      gpu_device = 0;
    };
  };
};
```

### Problem

`apply_gpu_optimisations = "accept-responsibility"` enables GPU clock manipulation.
`gpu_device = 0` targets `/sys/class/drm/card0`, which on ASUS laptops using
`supergfxd` in Hybrid mode is typically the integrated GPU (iGPU), not the discrete
GPU that games run on. The wrong GPU gets targeted, providing no gaming benefit and
risking unintended manipulation of the iGPU power state.

### Proposed fix

Remove the `gpu` block entirely. GameMode will manage CPU/scheduler/renice
improvements but perform no GPU manipulation. Users who confirm their dGPU is at the
expected DRM device index can add the block in `hardware-configuration.nix`:

```nix
programs.gamemode = {
  enable = true;
  enableRenice = true;
  settings = {
    general = {
      renice = 10;
    };
    # GPU optimisations are disabled by default — gpu_device index varies across
    # hardware topologies (especially ASUS laptops using supergfxd in Hybrid mode
    # where the dGPU is not device 0). To enable, add to hardware-configuration.nix:
    #
    #   programs.gamemode.settings.gpu = {
    #     apply_gpu_optimisations = "accept-responsibility";
    #     gpu_device = 1;  # Check: ls /sys/class/drm/ — find your dGPU card number
    #   };
  };
};
```

### Files to change

- `modules/gaming.nix`

---

## BUG-11: PipeWire Quantum Too Aggressive

**File:** `modules/gaming.nix`

### Current code

```nix
# ── PipeWire Low Latency ─────────────────────────────────────────────
# Extends the PipeWire configuration in configuration.nix.
# Theoretical latency: quantum/rate = 64/48000 ≈ 1.33ms
# If audio cuts out, increase quantum to 128 or 256.
services.pipewire.lowLatency = {
  enable = true;
  quantum = 64;
  rate = 48000;
};
```

### Problem

`quantum = 64` at 48000 Hz is approximately 1.33 ms — an extreme pro-audio setting
that requires a real-time kernel, dedicated audio hardware, and a stable CPU load.
Under the variable CPU load typical of gaming (GPU driver interrupts, shader
compilations, physics bursts), the audio thread regularly misses its 1.33 ms deadline,
producing xruns (audible dropouts/crackles). The existing comment already acknowledges
"audio cuts out" as a known symptom.

### Proposed fix

Change `quantum` to `256` (~5.33 ms at 48000 Hz). This is the standard gaming balance:
low enough that audio latency is imperceptible for gaming, high enough that PipeWire's
processing thread survives variable CPU load on consumer hardware. Update comment to
document the latency and the fallback.

```nix
# ── PipeWire Low Latency ─────────────────────────────────────────────
# Extends the PipeWire configuration in configuration.nix.
# Theoretical latency: quantum/rate = 256/48000 ≈ 5.33ms — gaming balance.
# If audio still cuts out, increase quantum to 512 (standard desktop default).
# For pro-audio / JACK workflows, reduce to 128 or 64 (requires RT kernel).
services.pipewire.lowLatency = {
  enable = true;
  quantum = 256;
  rate = 48000;
};
```

### Files to change

- `modules/gaming.nix`

---

## BUG-12: `libvirtd --timeout 0` Global on Bare Metal

**File:** `modules/gnome.nix`

### Current code

```nix
virtualisation.libvirtd = {
  enable = true;
  extraOptions = [ "--timeout" "0" ];
  qemu.verbatimConfig = ''
    namespaces = []
    security_driver = "none"
  '';
};
```

(Preceded by an approximately 12-line comment explaining the VM-only motivation.)

### Problem

`--timeout 0` disables libvirtd's idle exit permanently. The comment correctly
identifies this as a workaround for VMs without nested KVM where TCG probing exceeds
the default 120 s idle timeout. However, the setting applies globally — on bare-metal
machines with fast KVM, libvirtd never exits when idle, holding resident memory
indefinitely after all VMs are stopped.

### Proposed fix

Remove `extraOptions = [ "--timeout" "0" ]` entirely (no attribute). The built-in
default of 120 s idle timeout resumes, which is entirely sufficient on bare metal with
KVM (probing completes in under 1 s). Update the comment to document the override
pattern for VM users who need it.

```nix
  # Virtualisation backend for GNOME Boxes and virt-manager.
  #
  # security_driver = "none" skips SELinux/AppArmor probing (absent in many
  # virtualised environments), reducing init latency on all hosts.
  # TimeoutStartSec = "infinity" ensures systemd does not pre-empt libvirtd
  # startup on any host.
  #
  # VM users WITHOUT nested KVM (e.g. VirtualBox with TCG fallback):
  # QEMU's capability probing via TCG can take > 120 s. The libvirtd built-in
  # idle timeout (120 s) fires before probing completes, causing FAILURE.
  # If you are running VexOS inside a VM without KVM, add the following to
  # your hardware-configuration.nix to disable the idle timeout:
  #
  #   virtualisation.libvirtd.extraOptions = lib.mkForce [ "--timeout" "0" ];
  #
  # This is NOT needed on bare-metal machines with KVM enabled.
  virtualisation.libvirtd = {
    enable = true;
    qemu.verbatimConfig = ''
      namespaces = []
      security_driver = "none"
    '';
  };
```

### Files to change

- `modules/gnome.nix`

---

## BUG-13: `boot.shell_on_fail` Exposes Root Shell

**File:** `modules/plymouth.nix`

### Current code

```nix
boot.kernelParams = [
  "quiet"
  "splash"
  "boot.shell_on_fail"
  "udev.log_priority=3"
  "rd.systemd.show_status=auto"
];
```

### Problem

`boot.shell_on_fail` causes the NixOS initrd to spawn an interactive, unauthenticated
root shell when a boot stage fails. On machines without full-disk encryption (FDE),
an attacker with brief physical access during a boot-failure event gains unrestricted
read-write access to the filesystem. VexOS does not mandate FDE and therefore cannot
rely on it as a mitigation.

The `rd.systemd.show_status=auto` parameter already present in `kernelParams` will
display systemd unit failure status in the initrd, providing diagnostic information
without opening a shell. Recovery can be performed from a live USB.

### Proposed fix

Remove `"boot.shell_on_fail"` from `boot.kernelParams`:

```nix
boot.kernelParams = [
  "quiet"
  "splash"
  "udev.log_priority=3"
  "rd.systemd.show_status=auto"
];
```

### Files to change

- `modules/plymouth.nix`

---

## INFO-01: `--hostname` Not Validated in `install.sh`

**File:** `scripts/install.sh`

### Current code

```bash
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
```

And later in Step 5:

```bash
FLAKE_CONTENT='{
  description = "VexOS local machine flake";

  inputs.vexos.url = "github:VictoryTek/vex-nix";

  outputs = { self, vexos, ... }: {
    nixosConfigurations.'"${HOSTNAME}"' = vexos.lib.mkVexosSystem {
      hardwareModule = ./hardware-configuration.nix;
    };
  };
}
'
```

### Problem

`$HOSTNAME` is shell-interpolated into a Nix expression without sanitisation.
Characters such as `}`, `'`, `"`, `$`, `{`, `;` would produce either a Nix parse
error or a shell injection in the here-doc. Example: `--hostname 'x}'` produces
`nixosConfigurations.x} =` which is invalid Nix and causes `nix flake update` to
fail with a confusing parse error rather than a clear user-facing message.

### Proposed fix

Add a validation block immediately after the argument-parsing `while` loop:

```bash
# Validate hostname: RFC 1123 label + valid Nix identifier characters
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || [[ ${#HOSTNAME} -gt 63 ]]; then
    fail "--hostname '${HOSTNAME}' is invalid."
    info "Hostname must:"
    info "  - Start with a letter (a-z, A-Z)"
    info "  - Contain only letters, digits, hyphens (-), and underscores (_)"
    info "  - Be at most 63 characters"
    exit 1
fi
```

Placement: insert this block **after** the `while` argument-parsing loop and **before**
the Banner echo block (i.e., between the `done` that ends argument parsing and the
`echo ""` that starts the banner).

### Files to change

- `scripts/install.sh`

---

## INFO-02: `max-jobs` and `cores` Hardcoded to 2

**File:** `modules/system.nix`

### Current code

```nix
# Limit parallel build jobs to reduce peak RAM usage during nixos-rebuild.
# Each Nix build job can consume several hundred MB; capping at 2 prevents
# the evaluator + linker from exhausting memory on machines with ≤8 GB RAM.
nix.settings.max-jobs = 2;
nix.settings.cores = 2;
```

### Problem

`max-jobs = 2` limits the Nix daemon to 2 concurrent build jobs regardless of
available CPU cores. On machines with 8–16 cores and 16+ GB RAM, this causes
`nixos-rebuild` to run several times slower than necessary — the daemon queues builds
that could run in parallel.

### Proposed fix

Remove both settings. In the NixOS `nix` module (nixpkgs ≥ 22.05), when these options
are not set, Nix uses `max-jobs = "auto"` (number of logical CPUs) and `cores = 0`
(all cores per job). The `zramSwap.enable = true` and `download-buffer-size`
settings already guard against memory pressure. RAM-constrained users can add overrides
in their hardware-specific config.

Replace the three lines with a comment-only block:

```nix
# Nix build parallelism: max-jobs and cores are not set here so Nix uses
# "auto" (all logical CPUs) for max-jobs and 0 (all cores) for cores.
# On RAM-constrained machines (≤8 GB), add to hardware-configuration.nix:
#   nix.settings.max-jobs = 2;
#   nix.settings.cores = 2;
```

### Files to change

- `modules/system.nix`

---

## INFO-03: Fragile `isCachyos` Substring Match

**File:** `modules/kernel.nix`

### Current code

```nix
let
  cfg = config.kernel;
  isCachyos = builtins.substring 0 7 cfg.type == "cachyos";
in {
```

### Problem

`builtins.substring 0 7 cfg.type == "cachyos"` performs a 7-character prefix match.
This is fragile because:

1. The magic constant `7` must match the byte-length of `"cachyos"` — easy to get wrong
   if the list of types is ever edited.
2. It matches any future type whose first 7 characters are `"cachyos"`, even one not in
   the accepted enum (e.g. `"cachyos-custom-something"` added without updating this
   check).
3. The reader must mentally decode the arithmetic rather than seeing the intent.

`builtins.elem` checks exact membership against an explicit list, which is both correct
and self-documenting.

### Proposed fix

```nix
let
  cfg = config.kernel;
  isCachyos = builtins.elem cfg.type [
    "cachyos-gaming"
    "cachyos-server"
    "cachyos-desktop"
    "cachyos-handheld"
    "cachyos-lts"
    "cachyos-hardened"
  ];
in {
```

The list above is exhaustive — it exactly matches the CachyOS variants declared in
`options.kernel.type` (the `"bazzite"` and `"stock"` types are intentionally excluded
as they do not use the CachyOS binary caches).

### Files to change

- `modules/kernel.nix`

---

## Implementation Checklist

| Bug      | File                    | Change Summary                                               |
|----------|-------------------------|--------------------------------------------------------------|
| BUG-10   | `modules/gaming.nix`    | Remove `gpu { }` block; add comment with override pattern   |
| BUG-11   | `modules/gaming.nix`    | Change `quantum = 64` → `quantum = 256`; update comment     |
| BUG-12   | `modules/gnome.nix`     | Remove `extraOptions = [ "--timeout" "0" ]`; update comment |
| BUG-13   | `modules/plymouth.nix`  | Remove `"boot.shell_on_fail"` from `kernelParams`           |
| INFO-01  | `scripts/install.sh`    | Add hostname regex + length validation after arg parsing     |
| INFO-02  | `modules/system.nix`    | Remove `max-jobs = 2` and `cores = 2`; replace with comment |
| INFO-03  | `modules/kernel.nix`    | Replace `builtins.substring` with `builtins.elem`           |

---

## Risk Assessment

| Bug     | Risk of Fix                | Mitigation                                             |
|---------|----------------------------|--------------------------------------------------------|
| BUG-10  | None — removes GPU manipulation | GPU optimisations were a best-effort feature          |
| BUG-11  | Minor audio behaviour change | 5.33 ms still imperceptible for gaming; documented   |
| BUG-12  | VM users: libvirtd may exit after 120 s idle | Comment documents override for VM users         |
| BUG-13  | Recovery slightly harder — no root shell on fail | Live USB recovery is documented best practice |
| INFO-01 | Hostnames with underscores still valid | RFC 1123 allows letters/digits/hyphens; underscore added for Nix compat |
| INFO-02 | Rebuilds use more RAM on weak machines | zramSwap mitigates; comment documents how to re-add limits |
| INFO-03 | None — pure logic equivalence on existing enum | `builtins.elem` against same set as enum       |
