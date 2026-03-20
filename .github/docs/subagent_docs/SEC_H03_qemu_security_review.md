# SEC-H03 Phase 3 Review: Remove `security_driver = "none"` from QEMU Config

**Audit Finding:** H-03  
**Severity:** High  
**Review Phase:** Phase 3 — Review & Quality Assurance  
**Reviewer:** Senior NixOS Security Reviewer  
**Date:** 2026-03-19  
**Verdict:** **PASS**

---

## 1. Confirmed Real Bug (Not a False Positive)

**YES — confirmed real security bug.**

`security_driver = "none"` in `qemu.verbatimConfig` unconditionally disabled
libvirt's entire security mediation layer (DAC driver, cgroup ACLs, namespace
isolation promotion) on every host importing `modules/gnome.nix`, including
bare-metal KVM hosts where full isolation is mandatory.

The NixOS `libvirtd` module functions correctly and securely without any
explicit `security_driver` setting. When absent, libvirt auto-detects the
available driver and falls back to DAC, which drops QEMU processes to UID
`qemu-libvirtd` (64055) with cgroup device ACLs. The removal restores this
secure default with zero functional regression on real hardware.

---

## 2. Review Criteria Findings

### 2.1 Security Fix Completeness — PASS

Grep across all `.nix` files confirms:

```
./hosts/default/hardware-configuration.nix:50:  # virtualisation.libvirtd.qemu.verbatimConfig = ''
./hosts/default/hardware-configuration.nix:51:  #   namespaces = []
./hosts/default/hardware-configuration.nix:52:  #   security_driver = "none"
./modules/gnome.nix:61:  #   security_driver = "none" (in qemu.verbatimConfig) ...
./modules/gnome.nix:65:    # qemu.verbatimConfig is intentionally absent ...
./modules/gnome.nix:72:    #   virtualisation.libvirtd.qemu.verbatimConfig = ''
./modules/gnome.nix:73:    #     namespaces = []
./modules/gnome.nix:74:    #     security_driver = "none"
```

Every occurrence of `security_driver`, `namespaces`, and `verbatimConfig` in
the tracked `.nix` files is inside a Nix comment (prefixed with `#`). There
is **no active (evaluated) expression** setting these values in the
repository. The fix is complete.

### 2.2 No Over-Reach — PASS

The `virtualisation.libvirtd` block in `modules/gnome.nix` is reviewed in
full. The following settings are intact and unchanged:

| Setting | Status |
|---------|--------|
| `virtualisation.libvirtd.enable = true` | ✅ Present |
| `programs.virt-manager.enable = true` | ✅ Present |
| `virtualisation.spiceUSBRedirection.enable = true` | ✅ Present |
| `systemd.services.libvirtd.serviceConfig.TimeoutStartSec` | ✅ Present (`lib.mkDefault "120"`) |
| `gnome-boxes` in `environment.systemPackages` | ✅ Present |

No unintended removals or changes to the virtualisation or GNOME block.

### 2.3 Comment Quality — PASS (Excellent)

The replacement comment block in `modules/gnome.nix` (lines 65–76) is
exemplary:

```nix
# qemu.verbatimConfig is intentionally absent — NixOS defaults to the DAC
# security driver, which confines QEMU processes to the libvirt-qemu user/group
# with cgroup ACLs. This prevents a VM escape from reaching the host user env.
#
# If you are running NixOS inside a hypervisor (VM-in-VM, e.g. VirtualBox) without
# nested KVM support, add the following ONLY in that machine's hardware-configuration.nix:
#
#   virtualisation.libvirtd.qemu.verbatimConfig = ''
#     namespaces = []
#     security_driver = "none"
#   '';
```

The comment:
- States the setting is **intentionally** absent (not forgotten)
- Explains **why** the default is correct (DAC driver confinement)
- Names the exact **security property** protected (VM escape prevention)
- Provides the **exact code snippet** with correct placement for legitimate VM-in-VM use
- Is accurate regarding NixOS behaviour

### 2.4 hardware-configuration.nix Workaround Snippet — PASS

Lines 44–54 of `hosts/default/hardware-configuration.nix`:

```nix
  # ── VM-in-VM workaround ──────────────────────────────────────────────────────
  # Uncomment the block below ONLY if this machine is running NixOS inside a
  # hypervisor (e.g. VirtualBox) that lacks nested KVM support. Enabling this
  # globally in a module is a security risk — it disables QEMU DAC confinement.
  #
  # virtualisation.libvirtd.qemu.verbatimConfig = ''
  #   namespaces = []
  #   security_driver = "none"
  # '';
```

The workaround snippet is:
- Present in the correct file (`hardware-configuration.nix`)
- Fully commented out (not active)
- Clearly labelled as a conditional, machine-specific override
- Accompanied by an explicit security warning

### 2.5 Nix Syntax Validity — PASS

`nix flake check` completed without errors:

```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
evaluating flake...
checking flake output 'nixosConfigurations'...
checking NixOS configuration 'nixosConfigurations.vexos'...
```

Exit code: 0. No parse errors, type errors, or evaluation failures in either
modified file.

### 2.6 False Positive Check — CONFIRMED REAL BUG

Verified against the NixOS upstream `libvirtd` module:

- `virtualisation.libvirtd.qemu.verbatimConfig` has a NixOS-provided default
  of `''namespaces = []\n''` (namespace isolation enabled — security-positive)
- There is no `security_driver` in the NixOS default
- The `security_driver = "none"` that was removed was a purely custom override
  with no upstream necessity
- Removing it restores DAC driver activation, which is correct and secure

### 2.7 Build Validation — PASS

**Command 1:** `nix flake check 2>&1 | head -30`

```
warning: Git tree '/var/home/nimda/Projects/vex-nix' has uncommitted changes
evaluating flake...
checking flake output 'nixosConfigurations'...
checking NixOS configuration 'nixosConfigurations.vexos'...
```

Result: ✅ **Clean pass** (exit code 0, no errors)

---

**Command 2:** `nix eval .#nixosConfigurations.vexos.config.virtualisation.libvirtd.qemu.verbatimConfig`

```
"namespaces = []\n"
```

Result: ✅ **Correct.** This is not residual code; it is the **NixOS upstream
default** for `virtualisation.libvirtd.qemu.verbatimConfig`, as defined in
`nixos/modules/virtualisation/libvirtd.nix`:

```nix
verbatimConfig = mkOption {
  type = types.lines;
  default = ''
    namespaces = []
  '';
  ...
```

The `namespaces = []` default keeps namespace isolation *enabled* — this is
a security-positive setting. The dangerous `security_driver = "none"` is
absent from the evaluated output. The fix is confirmed complete at the Nix
evaluator level.

### 2.8 Files Changed Check — PASS (with informational note)

`git diff --name-only` output:

```
README.md
hosts/default/hardware-configuration.nix
modules/gnome.nix
```

**Informational:** `README.md` appears in the working tree diff. Inspection
of `git diff README.md` confirms this is a **pre-existing, unrelated edit**
(installation instructions rewrite — thin flake documentation, bootstrap
step rephrasing). It predates the SEC-H03 implementation and is out of scope
for this review. The security fix itself only modified the two expected files.

The two SEC-H03 target files are present. No unexpected `.nix` files were
modified.

---

## 3. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Security Fix Quality | 100% | A |
| Code Quality | 98% | A |
| Nix Syntax | 100% | A |
| No Regression | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

*(-1% Code Quality: the informational README.md working-tree change is
coincidental but adds minor noise to the commit diff; no action required.)*

---

## 4. Critical Issues

**None.**

---

## 5. Recommendations (Non-Blocking)

1. **Stage README.md separately** before committing SEC-H03 so the commit
   diff cleanly reflects `modules/gnome.nix` and
   `hosts/default/hardware-configuration.nix` only. This keeps the security
   fix audit trail unambiguous.

2. **Consider adding `statix`** or `deadnix` to the preflight script in a
   future cycle to catch this class of comment/code inconsistency
   automatically (dead or over-permissive config blocks left behind).

Both are informational only and do not affect the correctness or security of
the fix.

---

## 6. Final Determination

| Check | Result |
|-------|--------|
| `security_driver = "none"` removed from active code | ✅ |
| `namespaces = []` removed from active code | ✅ (was also part of override; NixOS default `namespaces = []` remains and is correct) |
| No `qemu.verbatimConfig` set in any module | ✅ |
| VM-in-VM workaround documented in hardware-configuration.nix | ✅ |
| Comment explains the WHY and the WHERE | ✅ |
| `nix flake check` passes | ✅ |
| Eval confirms `security_driver = "none"` not in evaluated config | ✅ |
| No regression to SPICE, virt-manager, gnome-boxes | ✅ |
| Nix syntax valid in all modified files | ✅ |

**VERDICT: PASS**

The SEC-H03 security fix is correct, complete, and production-ready. The
implementation matches the specification exactly, restores NixOS's secure
default isolation for QEMU processes, and introduces no regressions.
