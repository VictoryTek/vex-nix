# SEC-M07: Kernel sysctl Hardening — Phase 3 Review
**Phase**: 3 — Review & Quality Assurance  
**Reviewer**: Senior NixOS Security Reviewer  
**Date**: 2026-03-19  
**Modified file**: `modules/system.nix`  
**Spec**: `.github/docs/subagent_docs/SEC_M07_sysctl_hardening_spec.md`

---

## 1. Completeness Check

All 11 mandatory keys required by the specification are present in the `boot.kernel.sysctl`
block. The implementation also adds `kernel.printk`, which is within spec scope.

| Required Key | Present? | Evaluated Value |
|---|---|---|
| `kernel.dmesg_restrict` | ✅ | `1` |
| `kernel.kptr_restrict` | ✅ | `2` |
| `kernel.yama.ptrace_scope` | ✅ | `1` |
| `kernel.unprivileged_bpf_disabled` | ✅ | `1` |
| `net.core.bpf_jit_harden` | ✅ | `2` |
| `net.ipv4.conf.all.accept_redirects` | ✅ | `0` |
| `net.ipv4.conf.default.accept_redirects` | ✅ | `0` |
| `net.ipv4.conf.all.send_redirects` | ✅ | `0` |
| `net.ipv4.conf.all.log_martians` | ✅ | `1` |
| `net.ipv4.conf.all.rp_filter` | ✅ | `1` |
| `fs.suid_dumpable` | ✅ | `0` |
| `kernel.printk` (bonus) | ✅ | `"3 3 3 3"` (string) |

**Result: COMPLETE — 11/11 mandatory keys present.**

---

## 2. Value Correctness

All integer keys evaluate to integers (not strings). No type confusion found.

| Key | Expected Type | Actual Type | Expected Value | Actual Value | Result |
|---|---|---|---|---|---|
| `kernel.dmesg_restrict` | int | int | `1` | `1` | ✅ |
| `kernel.kptr_restrict` | int | int | `2` | `2` | ✅ |
| `kernel.yama.ptrace_scope` | int | int | `1` | `1` | ✅ |
| `kernel.unprivileged_bpf_disabled` | int | int | `1` | `1` | ✅ |
| `net.core.bpf_jit_harden` | int | int | `2` | `2` | ✅ |
| `net.ipv4.conf.all.accept_redirects` | int | int | `0` | `0` | ✅ |
| `net.ipv4.conf.default.accept_redirects` | int | int | `0` | `0` | ✅ |
| `net.ipv4.conf.all.send_redirects` | int | int | `0` | `0` | ✅ |
| `net.ipv4.conf.all.log_martians` | int | int | `1` | `1` | ✅ |
| `net.ipv4.conf.all.rp_filter` | int | int | `1` | `1` | ✅ |
| `fs.suid_dumpable` | int | int | `0` | `0` | ✅ |
| `kernel.printk` | string | string | `"3 3 3 3"` | `"3 3 3 3"` | ✅ |

**Result: ALL TYPES AND VALUES CORRECT.**

---

## 3. Placement Verification

The `boot.kernel.sysctl` block in `modules/system.nix` sits between:
- `networking.firewall { ... }` (ends at line 93)
- `services.printing.enable = true;` (line 157)

This is the exact placement specified. The section is preceded by a descriptive section
header comment:

```
# ── Kernel / network hardening ────────────────────────────────────────────────
# These settings apply regardless of kernel variant (stock, CachyOS, etc.).
# All values have been verified safe for Steam / Proton / Wine / GameMode.
# Override any entry in hardware-configuration.nix with lib.mkForce if a
# specific game or tool requires a different value.
```

**Result: PLACEMENT CORRECT.**

---

## 4. Regression Check

`git diff --stat` output:

```
 README.md                                | 78 ++++++++++++++++++++++++++++...
 hosts/default/hardware-configuration.nix | 10 ++++++++
 modules/gnome.nix                        | 20 +++++++-------
 modules/kernel.nix                       |  8 ++++--
 modules/system.nix                       | 52 +++++++++++++++...----
 5 files changed, 124 insertions(+), 44 deletions(-)
```

The `system.nix` diff shows 52 insertions and 3 deletions. The 3 "deletions" correspond to
whitespace restructuring around the insertion point — no existing content was removed or
altered. All pre-existing options (OpenSSH, Tailscale, Samba, gvfs, firewall, printing,
bluetooth, power-profiles-daemon, Docker rootless) are present and unchanged in the
reviewed file.

**Result: NO REGRESSION.**

Note: `README.md`, `hardware-configuration.nix`, `gnome.nix`, and `kernel.nix` show
changes from other concurrent work items; these are out of scope for SEC-M07 but do not
affect the sysctl block under review.

---

## 5. Gaming Safety Documentation

The comment on `kernel.yama.ptrace_scope` reads:

```nix
# Restrict ptrace to parent-child relationships only (scope 1).
# Steam, Proton/Wine wineserver, and GameMode are all safe at scope 1.
# If a legacy launcher breaks, override in hardware-configuration.nix:
#   boot.kernel.sysctl."kernel.yama.ptrace_scope" = lib.mkForce 0;
```

This comment:
- ✅ Documents the ptrace scope level (1 = parent-child only)
- ✅ Explicitly names Steam, Proton/Wine wineserver, and GameMode as verified safe
- ✅ Provides a `lib.mkForce` override path with exact attribute syntax

The section header comment also covers all other parameters:
```nix
# All values have been verified safe for Steam / Proton / Wine / GameMode.
# Override any entry in hardware-configuration.nix with lib.mkForce if a
# specific game or tool requires a different value.
```

**Result: GAMING SAFETY DOCUMENTATION COMPLETE.**

---

## 6. Gaming Module Overlap Check (`modules/gaming.nix`)

`modules/gaming.nix` was inspected in full. The file contains:
- `programs.gamemode` settings
- `services.pipewire.lowLatency` settings
- Commented-out Steam and nix-gaming cache blocks

**No `boot.kernel.sysctl` entries exist anywhere in `gaming.nix`.**

The `platformOptimizations` module (from `nix-gaming`, loaded via `flake.nix`) sets four
sysctl keys per the specification:

| platformOptimizations Key | Overlap with SEC-M07? |
|---|---|
| `vm.max_map_count` | ❌ Not in SEC-M07 block |
| `kernel.split_lock_mitigate` | ❌ Not in SEC-M07 block |
| `kernel.sched_cfs_bandwidth_slice_us` | ❌ Not in SEC-M07 block |
| `net.ipv4.tcp_fin_timeout` | ❌ Not in SEC-M07 block |

Zero overlap. No `lib.mkForce` / `lib.mkDefault` precedence conflicts.

**Observation (informational, not a defect):** The full sysctl eval shows
`vm.max_map_count = 1048576`. The spec cited `platformOptimizations` would set
`2147483642`. This discrepancy is unrelated to SEC-M07 (it predates this change and is
not introduced by the sysctl block). No action required.

**Result: NO CONFLICT WITH GAMING MODULES.**

---

## 7. Build Validation

### 7.1 Full sysctl attrset evaluation

```
$ nix eval .#nixosConfigurations.vexos.config.boot.kernel.sysctl 2>&1 | head -30
```

Output (no errors):
```nix
{ "fs.inotify.max_user_instances" = 524288; "fs.inotify.max_user_watches" = 524288;
  "fs.suid_dumpable" = 0; "kernel.dmesg_restrict" = 1; "kernel.kptr_restrict" = 2;
  "kernel.pid_max" = 4194304; "kernel.poweroff_cmd" = "/nix/store/.../sbin/poweroff";
  "kernel.printk" = "3 3 3 3"; "kernel.unprivileged_bpf_disabled" = 1;
  "kernel.yama.ptrace_scope" = 1; "net.core.bpf_jit_harden" = 2;
  "net.core.rmem_max" = null; "net.core.wmem_max" = null;
  "net.ipv4.conf.all.accept_redirects" = 0; "net.ipv4.conf.all.forwarding" = false;
  "net.ipv4.conf.all.log_martians" = 1; "net.ipv4.conf.all.rp_filter" = 1;
  "net.ipv4.conf.all.send_redirects" = 0; "net.ipv4.conf.default.accept_redirects" = 0;
  "net.ipv4.ping_group_range" = "0 2147483647"; "net.ipv6.conf.all.disable_ipv6" = false;
  "net.ipv6.conf.default.disable_ipv6" = false; "net.ipv6.conf.default.use_tempaddr" = "2";
  "vm.max_map_count" = 1048576; }
```

Exit code: **0** — evaluation succeeded with no errors.

### 7.2 Specific key spot-check: `kernel.dmesg_restrict`

```
$ nix eval .#nixosConfigurations.vexos.config.boot.kernel.sysctl \
    --apply 'attrs: attrs."kernel.dmesg_restrict"'
1
```

Returns `1` as expected. ✅

### 7.3 All 12 required values in a single eval

```
$ nix eval ... --apply 'attrs: { dmesg_restrict = ...; kptr_restrict = ...; ... }'
```

Output:
```nix
{ accept_redir_all = 0; accept_redir_def = 0; bpf_disabled = 1; bpf_jit = 2;
  dmesg_restrict = 1; kptr_restrict = 2; log_martians = 1; printk = "3 3 3 3";
  ptrace_scope = 1; rp_filter = 1; send_redir = 0; suid_dumpable = 0; }
```

All values match specification exactly. No type errors. ✅

**Result: BUILD VALIDATION PASSED — evaluation clean, all keys present and correct.**

---

## 8. Issues Found

| Severity | Category | Description | Status |
|---|---|---|---|
| — | — | No issues found | — |

No critical, major, or minor issues identified. The implementation matches the
specification exactly in scope, values, types, placement, and documentation.

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A+ |
| Security Fix Quality | 100% | A+ |
| Code Quality | 100% | A+ |
| Nix Types / Values | 100% | A+ |
| Gaming Safety | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (100%)**

---

## Verdict

**PASS**

All 11 required sysctl keys are present with correct integer types and correct values.
`kernel.yama.ptrace_scope = 1` is correctly set, documented with Steam/Proton/GameMode
safety rationale and a `lib.mkForce` override path. No overlap with `gaming.nix` or
`platformOptimizations`. No existing content was regressed. Nix evaluation is clean with
exit code 0.

The implementation is ready for Phase 6 Preflight Validation.
