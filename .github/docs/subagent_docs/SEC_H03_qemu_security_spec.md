# SEC-H03 Specification: Remove Unconditional `security_driver = "none"` from QEMU Config

**Audit Finding:** H-03  
**Severity:** High  
**Component:** `modules/gnome.nix` — `virtualisation.libvirtd.qemu.verbatimConfig`  
**Fix Scope:** `modules/gnome.nix` (primary); `hosts/default/hardware-configuration.nix` (documentation comment only)  
**Spec Author:** Phase 1 Research & Specification  
**Date:** 2026-03-19  

---

## 1. Verdict

**CONFIRMED REAL BUG — not a false positive.**

The `security_driver = "none"` setting is unconditionally active on every
machine that imports `modules/gnome.nix`. This includes bare-metal KVM hosts
where full security isolation is mandatory. The NixOS defaults (DAC security
driver) are already correct and secure; this override serves no purpose on
bare-metal and actively degrades security there.

---

## 2. Exact Location of the Bug

**File:** `modules/gnome.nix`

```
Line 70:     qemu.verbatimConfig = ''
Line 71:       namespaces = []
Line 72:       security_driver = "none"
Line 73:     '';
```

Context (full block, lines 63–74):

```nix
  virtualisation.libvirtd = {
    enable = true;
    # extraOptions is intentionally omitted — libvirtd's default 120 s idle
    # timeout is correct for bare-metal machines with KVM.
    # If running VexOS inside a VM without nested KVM (slow TCG probing),
    # add this override in hardware-configuration.nix:
    #   virtualisation.libvirtd.extraOptions = lib.mkForce [ "--timeout" "0" ];
    qemu.verbatimConfig = ''
      namespaces = []
      security_driver = "none"
    '';
  };
```

There is **no conditional logic** (`lib.mkIf`, `lib.optionalAttrs`, or any
NixOS option guard) around this block. It is active on every host that
imports this module.

---

## 3. Comment Inconsistency (Root Cause)

The comment block at lines 48–62 **explicitly documents** that
`security_driver = "none"` should be a per-machine override:

```
# For VM guests where this occurs, apply these overrides
# per-machine in hardware-configuration.nix rather than globally:
#
#   virtualisation.libvirtd.extraOptions = lib.mkForce [ "--timeout" "0" ];
#   systemd.services.libvirtd.serviceConfig.TimeoutStartSec = lib.mkForce "infinity";
#
#   security_driver = "none" (in qemu.verbatimConfig) — skips SELinux/AppArmor
#                              probing (absent in VirtualBox), reducing init latency.
```

The `extraOptions` and `TimeoutStartSec` overrides were correctly kept
comment-only (not applied globally). The `security_driver = "none"` line was
not cleaned up to match. This is a code/comment inconsistency: the developer
documented the correct intent but did not complete the implementation.

---

## 4. Why It Is Dangerous

### 4.1 What `security_driver = "none"` Disables

This single setting in `/etc/libvirt/qemu.conf` turns off libvirt's entire
security mediation layer for QEMU processes. Specifically it disables:

| Security Mechanism | Normal Role | Disabled By This Setting |
|--------------------|-------------|--------------------------|
| DAC driver | Enforces file ownership/permissions on disk images and devices; drops QEMU to a dedicated unprivileged UID/GID | Yes |
| SELinux driver | Labels QEMU processes and their resources; confines guest access to host filesystem | Yes (on SELinux systems) |
| AppArmor driver | Applies per-VM AppArmor profiles restricting syscalls and file access | Yes (on AppArmor systems) |
| `cgroup` device ACLs | Applied by the DAC driver to restrict `/dev` access | Yes |
| Namespace isolation | `namespaces = []` additionally removes Linux mount/IPC/UTS namespace wrapping | Yes |

With both settings present, QEMU processes run with the **full privileges of
the libvirt daemon user** and have no namespace, cgroup, or MAC confinement.

### 4.2 VM Escape Scenario

On a bare-metal KVM host:

1. Guest OS exploits a QEMU bug (e.g., virtio, VGA, NVMe emulation) to
   achieve code execution in the QEMU host process.
2. Normally, the DAC security driver has already dropped QEMU to
   `libvirt-qemu:kvm` (UID ~64055) with a restricted cgroup device ACL and
   a read-only view of host filesystem paths outside the VM image.
3. With `security_driver = "none"`, step 2 never happens. The QEMU process
   retains the UID/GID of the libvirtd service user. On NixOS, libvirtd runs
   as root unless `virtualisation.libvirtd.onBoot = "start"` spawns it as a
   user service. In the default systemd unit, this means **the escaped process
   has root-equivalent filesystem access to the host**.
4. Even if libvirtd were unprivileged, an escaped guest would have access to:
   - All disk images mounted by other VMs
   - The user's home directory (GNOME session running as `nimda`)
   - Network interfaces and bridges
   - Other guests' memory via `/dev/kvm` if accessible

### 4.3 Scope Amplification

Because the insecure config lives in `modules/gnome.nix` — imported by every
host in this flake — every future machine added to the configuration inherits
this setting automatically, including dedicated KVM hypervisor hosts that may
run production workloads.

---

## 5. Architecture Analysis

### 5.1 Existing Per-Machine Override Mechanism

The codebase already has a clear, documented mechanism for machine-specific
overrides: `hosts/default/hardware-configuration.nix` (and its thin-flake
equivalent for each deployed machine). The precedent is established:

- `hardware-configuration.nix` contains CPU microcode, filesystem UUIDs, and
  kernel module lists — all inherently machine-specific
- The comment at lines 14–19 of `hardware-configuration.nix` explicitly
  instructs adding `kvm-intel`/`kvm-amd` only on hardware that supports it

The gnome.nix comment at line 55–56 directly names this same mechanism:
> "For VM guests where this occurs, apply these overrides **per-machine in
> hardware-configuration.nix rather than globally**"

### 5.2 No `lib.mkOption` Pattern in Existing Modules

None of the existing modules (`system.nix`, `users.nix`, `gpu.nix`,
`gaming.nix`, `asus.nix`, `kernel.nix`, `plymouth.nix`, `flatpak.nix`)
define custom NixOS options via `lib.mkOption`/`lib.mkEnableOption`. The
modules are all flat attribute sets. The codebase convention for
machine-specific behavior is: **place overrides in hardware-configuration.nix
using `lib.mkForce` or `lib.mkDefault`**, not option flags.

---

## 6. NixOS Default Security Behavior

When `qemu.verbatimConfig` is absent (or does not set `security_driver`):

- libvirt reads `/etc/libvirt/qemu.conf` without a `security_driver` line
- libvirt auto-detects available security drivers: tries `selinux`, then
  `apparmor`, then falls back to `dac`
- On a standard NixOS system (no SELinux, no AppArmor for libvirt), the
  active driver is **`dac`**
- The DAC driver drops each QEMU process to UID `libvirt-qemu` (64055) and
  GID `kvm`, applies `chown` on disk image paths, and sets cgroup device ACLs

This is the correct and secure default. No additional configuration is
required on bare-metal to get proper isolation.

`virtualisation.libvirtd.qemu.verbatimConfig` appends raw text to
`/etc/libvirt/qemu.conf`. It is a valid NixOS option (not deprecated). There
is no structured NixOS option for `security_driver` — it must be set via
`verbatimConfig` if an explicit override is needed. The safe path is to omit
it entirely and rely on auto-detection.

---

## 7. Chosen Fix: Option A (Remove `qemu.verbatimConfig` globally)

**Recommendation: Option A.**

Rationale:

1. **Matches existing codebase conventions.** No module uses `lib.mkOption`.
   Machine-specific overrides live in `hardware-configuration.nix`.
2. **The comment already documents the correct intent.** The developer wrote
   that this should be per-machine; the code just wasn't cleaned up.
3. **NixOS defaults are already correct and secure.** Removing the block
   restores DAC isolation with zero additional configuration.
4. **Option B adds unnecessary complexity** (`lib.mkMerge`, `lib.mkIf`,
   custom option namespace) for a scenario that the existing architecture
   handles natively.
5. **The VM-in-VM workaround is well-documented** in the existing comment and
   can be carried forward as a code snippet in hardware-configuration.nix.

Option B would be appropriate only if the project had multiple existing hosts
with different requirements that needed type-safe option declarations. With a
single default configuration and no current VM-guest deployments, it is
over-engineering.

---

## 8. Exact Code Changes Required

### 8.1 `modules/gnome.nix` — Primary Change

**Remove** the `qemu.verbatimConfig` block (lines 70–73) and replace the
surrounding comment to document both the security reason and the per-machine
workaround.

**Before (lines 48–74):**

```nix
  # Virtualisation backend for GNOME Boxes and virt-manager.
  #
  # Without KVM (e.g. VirtualBox with no nested virtualization enabled),
  # QEMU falls back to TCG (software emulation) for capability probing.
  # TCG probing inside a VM is 10–30× slower than native; it takes > 120 s.
  # The default "--timeout 120" idle timer fires before probing completes,
  # causing libvirtd to exit mid-init with status=1/FAILURE ("Make forcefull
  # daemon shutdown"). For VM guests where this occurs, apply these overrides
  # per-machine in hardware-configuration.nix rather than globally:
  #
  #   virtualisation.libvirtd.extraOptions = lib.mkForce [ "--timeout" "0" ];
  #   systemd.services.libvirtd.serviceConfig.TimeoutStartSec = lib.mkForce "infinity";
  #
  #   security_driver = "none" (in qemu.verbatimConfig) — skips SELinux/AppArmor
  #                              probing (absent in VirtualBox), reducing init latency.
  virtualisation.libvirtd = {
    enable = true;
    # extraOptions is intentionally omitted — libvirtd's default 120 s idle
    # timeout is correct for bare-metal machines with KVM.
    # If running VexOS inside a VM without nested KVM (slow TCG probing),
    # add this override in hardware-configuration.nix:
    #   virtualisation.libvirtd.extraOptions = lib.mkForce [ "--timeout" "0" ];
    qemu.verbatimConfig = ''
      namespaces = []
      security_driver = "none"
    '';
  };
```

**After:**

```nix
  # Virtualisation backend for GNOME Boxes and virt-manager.
  #
  # SECURITY: qemu.verbatimConfig is intentionally omitted. Omitting it
  # preserves the NixOS/libvirt default security driver (DAC), which drops
  # each QEMU process to the libvirt-qemu UID, applies cgroup device ACLs,
  # and enforces file-permission isolation between guests and the host.
  # Setting security_driver = "none" disables all of this and must never
  # appear in a shared module — it removes confinement from every host that
  # imports gnome.nix, including bare-metal KVM hypervisors.
  #
  # VM-in-VM workaround (VirtualBox without nested KVM only):
  # Without hardware KVM, QEMU falls back to TCG for capability probing.
  # TCG probing is 10–30× slower; libvirtd's 120 s idle timeout fires before
  # probing completes, causing FAILURE at startup. If VexOS is running inside
  # a VM without nested virtualization, add ALL of the following overrides in
  # that machine's hardware-configuration.nix:
  #
  #   virtualisation.libvirtd.extraOptions =
  #     lib.mkForce [ "--timeout" "0" ];
  #   systemd.services.libvirtd.serviceConfig.TimeoutStartSec =
  #     lib.mkForce "infinity";
  #   virtualisation.libvirtd.qemu.verbatimConfig = lib.mkForce ''
  #     namespaces = []
  #     security_driver = "none"
  #   '';
  virtualisation.libvirtd = {
    enable = true;
  };
```

### 8.2 `hosts/default/hardware-configuration.nix` — Documentation Comment (Optional)

Add a comment near the end of the file (after the CPU configuration section)
to make the VM-in-VM workaround discoverable for users who deploy VexOS inside
a virtual machine:

```nix
  # VM-in-VM libvirtd workaround (VirtualBox without nested KVM only):
  # Uncomment these if VexOS is running inside a VM and libvirtd fails to
  # start. See the comment in modules/gnome.nix for full explanation.
  #
  # virtualisation.libvirtd.extraOptions =
  #   lib.mkForce [ "--timeout" "0" ];
  # systemd.services.libvirtd.serviceConfig.TimeoutStartSec =
  #   lib.mkForce "infinity";
  # virtualisation.libvirtd.qemu.verbatimConfig = lib.mkForce ''
  #   namespaces = []
  #   security_driver = "none"
  # '';
```

This change is **optional** — it improves discoverability but is not required
for the security fix.

---

## 9. Files to Be Modified

| File | Change Type | Required |
|------|-------------|----------|
| `modules/gnome.nix` | Remove `qemu.verbatimConfig` block; rewrite surrounding comment | **Yes** |
| `hosts/default/hardware-configuration.nix` | Add VM-in-VM workaround comment | Optional |

---

## 10. Ripple Effect Analysis

### 10.1 Bare-Metal KVM Hosts

**Impact: Security improvement, no functional regression.**

The DAC security driver activates automatically. QEMU processes are dropped
to `libvirt-qemu:kvm`. Existing VMs start normally; no configuration changes
are required on the guest or host side.

### 10.2 VMs Running VexOS Without Nested KVM (e.g., VirtualBox)

**Impact: libvirtd may fail to start until the per-machine workaround is
applied.**

Without `security_driver = "none"`, the DAC driver is active, and libvirtd
attempts AppArmor/SELinux probing. On a VirtualBox guest, this probing via
TCG is 10–30× slower and may exceed the 120 s timeout.

**Migration path:** Add the three-line workaround block from section 8 to
`hardware-configuration.nix` for that machine. This is a one-time explicit
opt-in documented in gnome.nix's comment.

### 10.3 Current Deployment (hosts/default)

The `hardware-configuration.nix` template has `boot.kernelModules = []`
(no `kvm-intel`/`kvm-amd`), indicating the current default host is likely
a VM or an unconfigured template. If it is a VirtualBox VM, the workaround
comment in `hardware-configuration.nix` will guide the user. If it is
bare-metal (the intended target), no workaround is needed.

---

## 11. Verification Approach

After implementation, verify:

1. **Nix evaluation:**
   ```bash
   nix flake check
   nix eval .#nixosConfigurations.vexos.config.system.build.toplevel \
     --apply builtins.typeOf
   ```
   Both must succeed without errors.

2. **Confirm setting is absent from generated config:**
   ```bash
   nix eval .#nixosConfigurations.vexos.config.virtualisation.libvirtd.qemu.verbatimConfig \
     2>/dev/null || echo "option not set (correct)"
   ```
   Should return empty string `""` or the option-not-set message.

3. **Confirm security driver is not overridden:**
   ```bash
   grep -r "security_driver" \
     $(nix eval .#nixosConfigurations.vexos.config.environment.etc \
       --apply 'etc: etc."libvirt/qemu.conf".source' 2>/dev/null) \
     || echo "security_driver not set — using libvirt default DAC (correct)"
   ```

4. **On a rebuilt system**, confirm `systemctl status libvirtd` shows active
   and `virsh capabilities` succeeds (bare-metal with KVM enabled in BIOS).

---

## 12. References

1. libvirt QEMU driver security documentation:
   https://libvirt.org/drvqemu.html#security-driver
2. libvirt `qemu.conf` reference — `security_driver` field:
   https://gitlab.com/libvirt/libvirt/-/blob/master/src/qemu/qemu.conf
3. NixOS `virtualisation.libvirtd` options source:
   https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/virtualisation/libvirtd.nix
4. CVE examples of QEMU VM escape (illustrating why DAC matters):
   CVE-2019-14378 (heap overflow in SLiRP), CVE-2021-3682 (USB emulation),
   CVE-2023-3301 (VFIO device escape)
5. NixOS Security Hardening Guide — VM isolation:
   https://nixos.wiki/wiki/Libvirt
6. libvirt DAC security driver internals:
   https://libvirt.org/drvsecurity.html#dac
